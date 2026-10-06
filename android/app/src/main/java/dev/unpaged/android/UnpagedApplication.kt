package dev.unpaged.android

import android.app.Application
import dev.unpaged.android.playback.PlayerController

/** Application lifetime owner; activities and services never create another playback controller. */
class UnpagedApplication : Application() {
    val abs: dev.unpaged.android.abs.ABSClient by lazy { dev.unpaged.android.abs.ABSClient.create(this) }
    val player: PlayerController by lazy { PlayerController(this) }
}
