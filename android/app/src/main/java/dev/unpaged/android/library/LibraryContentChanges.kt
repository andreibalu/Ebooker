package dev.unpaged.android.library

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Process-wide invalidation shared by the phone and independently opened car stores. */
internal object LibraryContentChanges {
    private val revision = MutableStateFlow(0L)
    val changes = revision.asStateFlow()
    fun committed() { revision.update { it + 1 } }
}
