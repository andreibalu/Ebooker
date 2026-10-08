package dev.unpaged.android.playback

/** Separate source set: this exception cannot enter a release APK. */
internal fun debugBrowserAllowed(packageName: String) = packageName == "dev.unpaged.android.e2e"
