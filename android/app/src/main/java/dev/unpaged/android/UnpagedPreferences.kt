package dev.unpaged.android

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import androidx.compose.runtime.*

enum class LibrarySort(val key: String, val label: String) {
    RECENT("recent", "Recently Played"), TITLE("title", "Title"), AUTHOR("author", "Author"),
    DURATION("duration", "Duration"), DATE_ADDED("dateAdded", "Date Added")
}

/** One owner for iOS-compatible preference keys. Writes are observed by every app surface. */
class UnpagedPreferences(context: Context) {
    private val storage = context.getSharedPreferences("unpaged", Context.MODE_PRIVATE)
    fun text(key: String, default: String) = storage.getString(key, default) ?: default
    fun seconds(key: String, default: Int) = storage.getInt(key, default)
    fun collectionsHidden() = storage.getBoolean("librivoxCollectionsHidden", false)
    fun setCollectionsHidden(value: Boolean) { storage.edit { putBoolean("librivoxCollectionsHidden", value) } }
    fun shelvesFirst() = storage.getBoolean("startOnFreeBooks", false)
    fun setText(key: String, value: String) { storage.edit { putString(key, value) } }
    fun setSeconds(key: String, value: Int) { storage.edit { putInt(key, value) } }
    fun setShelvesFirst(value: Boolean) { storage.edit { putBoolean("startOnFreeBooks", value) } }
    fun sort(tab: String) = LibrarySort.entries.firstOrNull { it.key == text(sortKey(tab), "recent") } ?: LibrarySort.RECENT
    fun setSort(tab: String, sort: LibrarySort) = setText(sortKey(tab), sort.key)
    private fun sortKey(tab: String) = when (tab) {
        "Favorites" -> "favoritesSortOption"
        "Shelves" -> "shelvesSortOption"
        else -> "librarySortOption"
    }
    fun observe(listener: SharedPreferences.OnSharedPreferenceChangeListener) = storage.registerOnSharedPreferenceChangeListener(listener)
    fun stopObserving(listener: SharedPreferences.OnSharedPreferenceChangeListener) = storage.unregisterOnSharedPreferenceChangeListener(listener)
}

@Composable
fun preferenceRevision(preferences: UnpagedPreferences): Int {
    var revision by remember { mutableIntStateOf(0) }
    DisposableEffect(preferences) {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> revision++ }
        preferences.observe(listener)
        onDispose { preferences.stopObserving(listener) }
    }
    return revision
}
