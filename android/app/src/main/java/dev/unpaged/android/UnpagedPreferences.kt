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
    init { removeLegacyRecaps(context) }
    companion object {
        internal fun removeLegacyRecaps(context: Context) {
            val storage = context.getSharedPreferences("unpaged", Context.MODE_PRIVATE)
            if (!storage.getBoolean("legacyRecapsRemoved", false)) {
                // Commit before these preferences can be used by the backup agent.
                storage.edit(commit = true) {
                    storage.all.keys.filter { it.startsWith("recap.") }.forEach { remove(it) }
                    putBoolean("legacyRecapsRemoved", true)
                }
            }
        }
    }
    fun backupEnabled() = storage.getBoolean("libraryBackupEnabled", true)
    fun setBackupEnabled(value: Boolean) {
        // Synchronous so a backup immediately after leaving Settings sees the new policy.
        storage.edit(commit = true) { putBoolean("libraryBackupEnabled", value) }
    }
    fun text(key: String, default: String) = storage.getString(key, default) ?: default
    fun seconds(key: String, default: Int) = storage.getInt(key, default)
    fun shelvesSource(connected: Boolean) = text("shelvesSource", "librivox").takeIf { it == "librivox" || it == "audiobookshelf" && connected } ?: "librivox"
    fun setShelvesSource(value: String) = setText("shelvesSource", value)
    fun collectionsHidden() = storage.getBoolean("librivoxCollectionsHidden", false)
    fun setCollectionsHidden(value: Boolean) { storage.edit { putBoolean("librivoxCollectionsHidden", value) } }
    fun onboardingComplete() = storage.getBoolean("onboardingComplete", storage.getInt("onboardingPhase", 0) == 3)
    fun setOnboardingComplete(value: Boolean) { storage.edit { putBoolean("onboardingComplete", value) } }
    fun shelvesFirst() = storage.getBoolean("startOnFreeBooks", false)
    fun remove(key: String) { storage.edit { remove(key) } }
    fun setText(key: String, value: String) { storage.edit { putString(key, value) } }
    fun setAiPreference(key: String, enabled: Boolean) {
        require(key in setOf("useLocalAIFeatures", "useSmartMomentNaming", "useSmartSummary", "shortenSummary"))
        storage.edit {
            putString(key, enabled.toString())
            if (key == "useLocalAIFeatures" && !enabled) {
                putString("useSmartMomentNaming", "false"); putString("useSmartSummary", "false"); putString("shortenSummary", "false")
            } else if (key == "useSmartSummary" && !enabled) putString("shortenSummary", "false")
        }
    }
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
