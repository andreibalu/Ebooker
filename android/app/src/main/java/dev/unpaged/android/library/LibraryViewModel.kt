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
    val pending: PendingImport? = null,
    val busy: Boolean = false,
    val preparing: Boolean = false,
    val completed: Int = 0,
    val total: Int = 0,
    val error: LibraryFailure? = null,
)

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
                mutableState.update { it.copy(books = books, loading = false) }
            } catch (error: CancellationException) { throw error }
            catch (_: Exception) { mutableState.update { it.copy(loading = false, error = LibraryFailure.LOAD) } }
        }
    }

    fun prepare(uris: List<Uri>) {
        if (uris.isEmpty() || job?.isActive == true || state.value.pending != null) return
        mutableState.update { it.copy(busy = true, preparing = true, completed = 0, total = uris.size, error = null) }
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
                        progress = { done, total -> mutableState.update { it.copy(completed = done, total = total) } })
                }
                operationContext.ensureActive()
                mutableState.update { it.copy(pending = prepared) }
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

    fun save(title: String, author: String) {
        val pending = state.value.pending ?: return
        if (job?.isActive == true) return
        operation {
            // Save is a short atomic commit: completing it must not be interrupted by UI teardown.
            withContext(Dispatchers.IO + NonCancellable) { repository.save(pending, title, author) }
            mutableState.update { it.copy(pending = null) }
            refreshBooks()
        }
    }

    fun discard() {
        val pending = state.value.pending ?: return
        if (job?.isActive == true) return
        operation {
            withContext(Dispatchers.IO + NonCancellable) { repository.discard(pending) }
            mutableState.update { it.copy(pending = null) }
        }
    }

    fun remove(book: LibraryBook) {
        if (job?.isActive == true) return
        operation {
            withContext(Dispatchers.IO + NonCancellable) { repository.remove(book) }
            refreshBooks()
        }
    }

    fun dismissError() { mutableState.update { it.copy(error = null) } }

    private fun operation(block: suspend () -> Unit) {
        mutableState.update { it.copy(busy = true, error = null) }
        job = viewModelScope.launch {
            try { block() }
            catch (error: CancellationException) { throw error }
            catch (error: Exception) { fail(error, LibraryFailure.STORAGE) }
            finally { mutableState.update { it.copy(busy = false) } }
        }
    }

    private suspend fun refreshBooks() {
        val books = withContext(Dispatchers.IO) { repository.books() }
        mutableState.update { it.copy(books = books) }
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
