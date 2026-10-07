package dev.unpaged.android

import android.app.Application
import dev.unpaged.android.playback.PlayerController

/** Application lifetime owner; activities and services never create another playback controller. */
class UnpagedApplication : Application() {
    private var aiCreated = false
    val ai: dev.unpaged.android.ai.AiCoordinator by lazy { aiCreated = true; dev.unpaged.android.ai.AiCoordinator(this) }
    val abs: dev.unpaged.android.abs.ABSClient by lazy { dev.unpaged.android.abs.ABSClient.create(this) }
    val player: PlayerController by lazy { PlayerController(this) }

    @Suppress("DEPRECATION")
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (aiCreated && level >= android.content.ComponentCallbacks2.TRIM_MEMORY_BACKGROUND) ai.trimMemory()
    }
    override fun onLowMemory() { super.onLowMemory(); if (aiCreated) ai.trimMemory() }
}
