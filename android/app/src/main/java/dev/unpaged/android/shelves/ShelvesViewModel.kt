package dev.unpaged.android.shelves

import android.app.Application
import android.net.ConnectivityManager
import android.net.Network
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.net.ConnectException
import java.net.UnknownHostException
import java.net.SocketException
import java.util.Calendar

data class ShelvesState(val books: List<CatalogBook> = emptyList(), val featuredIDs: List<String> = emptyList(), val results: List<CatalogBook> = emptyList(),
    val query: String = "", val language: String? = null, val genre: String? = null, val length: String? = null,
    val loading: Boolean = true, val preparing: Boolean = false, val searching: Boolean = false,
    val ready: Boolean = false, val offline: Boolean = false, val error: String? = null,
    val partial: Boolean = false, val collectionLoading: Boolean = false) {
    val filtered: Boolean get() = query.isNotBlank() || language != null || genre != null || length != null
}
class ShelvesViewModel(application: Application) : AndroidViewModel(application) {
    private val store = SQLiteCatalogStore(application)
    private val client = LibriVoxClient()
    val session = ShelvesSession.get(application)
    private val mutable = MutableStateFlow(ShelvesState())
    val state = mutable.asStateFlow()
    private var syncJob: Job? = null
    private var searchJob: Job? = null
    private var collectionJob: Job? = null
    private var foreground = true
    private val connectivity = application.getSystemService(ConnectivityManager::class.java)
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = changed()
        override fun onLost(network: Network) = changed()
        private fun changed() {
            viewModelScope.launch {
                mutable.update { it.copy(offline = !session.connected()) }
                if (foreground && session.connected()) refresh()
            }
        }
    }
    val day get() = CatalogEnvironment.heroDay(getApplication(), Calendar.getInstance().get(Calendar.DAY_OF_YEAR))
    init { connectivity.registerDefaultNetworkCallback(networkCallback); refresh() }
    fun resume() { foreground = true; refresh() }
    fun refresh() {
        if (syncJob?.isActive == true) return
        syncJob = viewModelScope.launch {
            try {
                readCache()
                mutable.update { it.copy(offline = !session.connected(), error = null) }
                if (!session.connected() || CatalogEnvironment.savedOnly(getApplication())) { mutable.update { it.copy(loading = false) }; return@launch }
                mutable.update { it.copy(preparing = true) }
                withContext(Dispatchers.IO) {
                    val cached = store.books().map { it.id }.toSet()
                    val missing = Classics.ids.filter { it !in cached }
                    val preload = coroutineScope { missing.map { id -> async {
                        try { client.book(id) } catch (cancel: CancellationException) { throw cancel } catch (_: Exception) { null }
                    } }.awaitAll().filterNotNull() }
                    store.seed(preload)
                }
                readCache()
                mutable.update { it.copy(loading = false) }
                withContext(Dispatchers.IO) {
                    var lastRead = 0L
                    CatalogSync(store, client::page).run {
                        val now = System.currentTimeMillis()
                        if (now - lastRead >= 2000) { readCacheBlocking(); lastRead = now }
                    }
                }
                readCache()
            } catch (cancel: CancellationException) { throw cancel }
            catch (error: Exception) { mutable.update { it.copy(offline = !session.connected() || isOffline(error), error = error.message) } }
            finally { mutable.update { it.copy(loading = false, preparing = false) }; if (currentCoroutineContext().isActive) search() }
        }
    }
    private suspend fun readCache() = withContext(Dispatchers.IO) { readCacheBlocking() }
    private fun readCacheBlocking() {
        val books = store.books(); val ready = store.cursor().ready
        mutable.update { snapshot -> snapshot.copy(books = books, ready = ready,
            results = if (snapshot.filtered) (snapshot.results + books.filter { matches(it, snapshot) }).distinctBy { it.id }
                .filter { matches(it, snapshot) } else snapshot.results,
            featuredIDs = if (snapshot.featuredIDs.size < 5) CatalogEnvironment.featuredIDs(getApplication(), books) else snapshot.featuredIDs) }
    }
    fun pause() { foreground = false; syncJob?.cancel(); searchJob?.cancel(); collectionJob?.cancel(); session.stopSample() }
    fun query(value: String) { mutable.update { it.copy(query = value) }; search() }
    fun language(value: String?) { mutable.update { it.copy(language = value) }; search() }
    fun genre(value: String?) { mutable.update { it.copy(genre = value) }; search() }
    fun length(value: String?) { mutable.update { it.copy(length = value) }; search() }
    private fun matches(book: CatalogBook, snapshot: ShelvesState): Boolean {
        val query = fold(snapshot.query.trim())
        return (query.isEmpty() || fold(book.title).contains(query) || fold(book.author).contains(query)) &&
            (snapshot.language == null || book.language == snapshot.language) &&
            (snapshot.genre == null || snapshot.genre in book.genres) && when (snapshot.length) {
                "< 1 hr" -> book.seconds < 3600; "1–3 hrs" -> book.seconds in 3600 until 10800
                "3–6 hrs" -> book.seconds in 10800 until 21600; "6+ hrs" -> book.seconds >= 21600; else -> true
            }
    }
    private fun search() {
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            val snapshot = state.value
            val local = withContext(Dispatchers.Default) { snapshot.books.filter { matches(it, snapshot) } }
            mutable.update { it.copy(results = local, searching = false, partial = !snapshot.ready && snapshot.filtered) }
            if (!snapshot.filtered || snapshot.ready || !session.connected()) return@launch
            if (snapshot.query.isBlank() && snapshot.genre == null) return@launch
            mutable.update { it.copy(searching = true) }
            try {
                val remote = withContext(Dispatchers.IO) {
                    val books = if (snapshot.query.isNotBlank()) client.search(snapshot.query.trim()) else client.genre(snapshot.genre!!)
                    store.seed(books); books
                }
                ensureActive()
                readCache()
                ensureActive()
                mutable.update { it.copy(results = (remote + local).distinctBy { b -> b.id }.filter { b -> matches(b, snapshot) }, partial = false) }
            } catch (cancel: CancellationException) { throw cancel }
            catch (error: Exception) { mutable.update { it.copy(partial = true, offline = !session.connected() || isOffline(error), error = error.message) } }
            finally { mutable.update { it.copy(searching = false) } }
        }
    }
    fun collection(collection: BookCollection) {
        collectionJob?.cancel()
        collectionJob = viewModelScope.launch {
            mutable.update { it.copy(collectionLoading = true) }
            try {
                if (session.connected()) withContext(Dispatchers.IO) {
                    val cached = store.books().map { it.id }.toSet()
                    val fetched = coroutineScope { collection.ids.filter { it !in cached }.map { id -> async {
                        try { client.book(id) } catch (cancel: CancellationException) { throw cancel } catch (_: Exception) { null }
                    } }.awaitAll().filterNotNull() }
                    store.seed(fetched)
                }
                readCache()
            } finally { mutable.update { it.copy(collectionLoading = false) } }
        }
    }
    override fun onCleared() { connectivity.unregisterNetworkCallback(networkCallback); session.stopSample() }
    companion object {
        val languages = listOf("English", "German", "French", "Spanish", "Italian", "Dutch", "Portuguese", "Russian")
        val genres = listOf("General Fiction", "Historical Fiction", "Science Fiction", "Fantastic Fiction", "Detective Fiction", "Romance", "Short Stories", "Poetry", "Children's Fiction", "Action & Adventure", "Humorous Fiction", "Plays", "Literary Fiction", "War & Military Fiction", "Westerns", "History", "Biography & Autobiography", "Philosophy", "Religion", "Science", "Travel & Geography")
        val lengths = listOf("< 1 hr", "1–3 hrs", "3–6 hrs", "6+ hrs")
        fun isOffline(error: Exception) = error is UnknownHostException || error is ConnectException || error is SocketException
    }
}
