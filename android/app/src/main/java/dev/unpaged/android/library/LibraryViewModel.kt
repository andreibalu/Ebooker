package dev.unpaged.android.library

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

// State outlives configuration changes. Pending copies are intentionally abandoned on process death.
data class LibraryUiState(
    val loading: Boolean = true,
    val books: List<LibraryBook> = emptyList(),
    val moments: Map<String, List<LibraryMoment>> = emptyMap(),
    val pending: PendingImport? = null,
    val restoreMatch: LibraryBook? = null,
    val locateTarget: LibraryBook? = null,
    val busy: Boolean = false,
    val preparing: Boolean = false,
    val completed: Int = 0,
    val total: Int = 0,
    val error: LibraryFailure? = null,
    val errorTitle: String = "Something Went Wrong",
) {
    val restoreMismatch: Boolean get() = pending?.let { imported ->
        restoreMatch?.let { !TrackIdentity.matches(imported.tracks, it.tracks) }
    } == true
}

enum class LibraryFailure { INVALID_AUDIO, DUPLICATE, TITLE, READ, STORAGE, LOAD }

class LibraryViewModel(application: Application) : AndroidViewModel(application) {
    private val store = SQLiteLibraryStore(application)
    private val repository = LocalLibraryRepository(File(application.filesDir, "audiobooks"), store,
        AndroidAudioMetadataReader())
    private val mutableState = MutableStateFlow(LibraryUiState())
    val state = mutableState.asStateFlow()
    private var job: Job? = null

    init { reload() }

    fun reload() {
        if (job?.isActive == true) return
        mutableState.update { it.copy(loading = true, error = null) }
        job = viewModelScope.launch {
            try {
                val books = withContext(Dispatchers.IO) { repository.load() }
                val moments = withContext(Dispatchers.IO) { books.associate { it.id to repository.moments(it.id) } }
                mutableState.update { it.copy(books = books, moments = moments, loading = false) }
            } catch (error: CancellationException) { throw error }
            catch (_: Exception) { mutableState.update { it.copy(loading = false, error = LibraryFailure.LOAD) } }
        }
    }

    /** Catalog writes refresh visible rows without rerunning import/file recovery. */
    fun refreshCatalogBooks() {
        viewModelScope.launch { job?.join(); refreshBooks() }
    }

    fun prepare(uris: List<Uri>, locateTarget: LibraryBook? = null) {
        if (uris.isEmpty() || job?.isActive == true || state.value.pending != null) return
        mutableState.update { it.copy(busy = true, preparing = true, completed = 0, total = uris.size, error = null, errorTitle = "Something Went Wrong") }
        job = viewModelScope.launch {
            var prepared: PendingImport? = null
            try {
                // NonCancellable hand-off prevents prompt cancellation from losing the returned
                // staging identity. The IO loop still observes the original job's cancellation.
                val operationContext = currentCoroutineContext()
                withContext(Dispatchers.IO + NonCancellable) {
                    val resolver = getApplication<Application>().contentResolver
                    prepared = repository.prepare(uris.map { AndroidImportDocument(resolver, it) },
                        checkCancelled = { operationContext.ensureActive() },
                        progress = { done, total -> mutableState.update { it.copy(completed = done, total = total) } }, allowDuplicate = locateTarget != null)
                }
                operationContext.ensureActive()
                val match = withContext(Dispatchers.IO) { prepared?.let(repository::findRestoreMatch) }
                mutableState.update { it.copy(pending = prepared, restoreMatch = locateTarget ?: match, locateTarget = locateTarget) }
                prepared = null // ownership transferred to UI state
            } catch (_: CancellationException) {
                // A user cancellation is not an error.
            } catch (error: Exception) { fail(error, LibraryFailure.READ) }
            finally {
                prepared?.let { pending -> withContext(Dispatchers.IO + NonCancellable) { repository.discard(pending) } }
                mutableState.update { it.copy(busy = false, preparing = false) }
            }
        }
    }

    fun cancelPreparation() { if (state.value.preparing) job?.cancel() }

    fun addAsNew() { mutableState.update { it.copy(restoreMatch = null, locateTarget = null) } }
    fun restore(allowMismatch: Boolean = false) {
        val pending = state.value.pending ?: return
        val orphan = state.value.restoreMatch ?: return
        operation {
            withContext(Dispatchers.IO + NonCancellable) { repository.adopt(pending, orphan, allowMismatch) }
            mutableState.update { it.copy(pending = null, restoreMatch = null, locateTarget = null) }
            refreshBooks()
        }
    }
    fun restoreFree(book: LibraryBook) { operation { withContext(Dispatchers.IO) { repository.restoreFree(book) }; dev.unpaged.android.shelves.ShelvesSession.get(getApplication()).libraryChanged(); refreshBooks() } }

    fun save(title: String, author: String) {
        val pending = state.value.pending ?: return
        if (job?.isActive == true) return
        operation("Could Not Import") {
            // Save is a short atomic commit: completing it must not be interrupted by UI teardown.
            withContext(Dispatchers.IO + NonCancellable) { repository.save(pending, title, author) }
            mutableState.update { it.copy(pending = null, restoreMatch = null, locateTarget = null) }
            refreshBooks()
        }
    }

    fun discard() {
        val pending = state.value.pending ?: return
        if (job?.isActive == true) return
        operation {
            withContext(Dispatchers.IO + NonCancellable) { repository.discard(pending) }
            mutableState.update { it.copy(pending = null, restoreMatch = null, locateTarget = null) }
        }
    }

    fun toggleFavorite(book: LibraryBook) {
        if (job?.isActive == true) return
        operation("Could Not Save Favorite") {
            withContext(Dispatchers.IO) { repository.toggleFavorite(book.id) }
            refreshBooks()
        }
    }

    fun saveCover(book: LibraryBook, bitmap: android.graphics.Bitmap?) {
        operation {
            withContext(Dispatchers.IO) {
                val folder = File(getApplication<Application>().filesDir, "audiobooks/${book.id}")
                check(folder.mkdirs() || folder.isDirectory)
                val cover = File(folder, "cover.png")
                if (bitmap == null) { check(!cover.exists() || cover.delete()) }
                else {
                    val temp = File(folder, "cover.tmp")
                    java.io.FileOutputStream(temp).use { output ->
                        check(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output)); output.fd.sync()
                    }
                    check(temp.renameTo(cover))
                }
                LibraryContentChanges.committed()
            }
            refreshBooks()
            refreshActiveMetadata(book.id)
        }
    }

    fun rename(book: LibraryBook, title: String) {
        if (title.isBlank()) return
        operation("Could Not Rename Audiobook") {
            withContext(Dispatchers.IO) { store.rename(book.id, title) }
            refreshBooks()
            refreshActiveMetadata(book.id)
        }
    }

    private suspend fun refreshActiveMetadata(id: String) {
        state.value.books.firstOrNull { it.id == id }?.let {
            dev.unpaged.android.playback.PlayerController.get(getApplication<Application>()).refreshBookMetadata(it)
        }
    }

    fun remove(book: LibraryBook, permanent: Boolean = false) {
        if (job?.isActive == true) return
        operation {
            dev.unpaged.android.shelves.ShelvesSession.get(getApplication()).cancelForRemoval(book)
            withContext(Dispatchers.IO + NonCancellable) {
                if (!permanent && dev.unpaged.android.UnpagedPreferences(getApplication()).backupEnabled() && book.absItemID == null)
                    repository.removeFromPhone(book)
                else {
                    repository.remove(book)
                    dev.unpaged.android.ai.RecapCache(getApplication()).remove(book)
                }
            }
            dev.unpaged.android.shelves.ShelvesSession.get(getApplication()).libraryChanged()
            refreshBooks()
        }
    }

    fun saveMoment(moment: LibraryMoment) {
        operation { withContext(Dispatchers.IO) { repository.saveMoment(moment) }; refreshBooks() }
    }

    fun deleteMoment(id: String) {
        operation { withContext(Dispatchers.IO) { repository.deleteMoment(id) }; refreshBooks() }
    }

    fun refreshPlayback() {
        viewModelScope.launch { refreshBooks() }
    }

    fun dismissError() { mutableState.update { it.copy(error = null) } }

    private fun operation(title: String = "Something Went Wrong", block: suspend () -> Unit) {
        mutableState.update { it.copy(busy = true, error = null, errorTitle = title) }
        job = viewModelScope.launch {
            try { block() }
            catch (error: CancellationException) { throw error }
            catch (error: Exception) { fail(error, LibraryFailure.STORAGE) }
            finally { mutableState.update { it.copy(busy = false) } }
        }
    }

    private suspend fun refreshBooks() {
        val books = withContext(Dispatchers.IO) { repository.books() }
        val moments = withContext(Dispatchers.IO) { books.associate { it.id to repository.moments(it.id) } }
        mutableState.update { it.copy(books = books, moments = moments) }
    }

    private fun fail(error: Exception, fallback: LibraryFailure) {
        val failure = if (error is ImportProblem) when (error.reason) {
            ImportProblem.Reason.INVALID_AUDIO, ImportProblem.Reason.EMPTY -> LibraryFailure.INVALID_AUDIO
            ImportProblem.Reason.DUPLICATE -> LibraryFailure.DUPLICATE
            ImportProblem.Reason.TITLE -> LibraryFailure.TITLE
            ImportProblem.Reason.STORAGE -> LibraryFailure.STORAGE
        } else fallback
        mutableState.update { it.copy(error = failure) }
    }
}
