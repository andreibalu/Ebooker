package dev.unpaged.android.playback

import androidx.media3.common.util.UnstableApi
import androidx.media3.session.SessionError
import androidx.media3.session.SessionResult
import dev.unpaged.android.UnpagedPreferences
import dev.unpaged.android.library.LibraryMoment

/** Commands delegate to the phone player's operations; the car has no separate state or engine. */
@androidx.annotation.OptIn(UnstableApi::class)
internal class CarCommands(private val preferences: UnpagedPreferences,
    private val hasBook: () -> Boolean, private val draft: () -> LibraryMoment?,
    private val save: (LibraryMoment) -> Unit, private val mark: () -> Unit,
    private val speed: () -> Float, private val setSpeed: (Float) -> Unit) {
    fun perform(action: String): SessionResult {
        if (!hasBook()) return SessionResult(SessionError.ERROR_INVALID_STATE)
        when (action) {
            CarSessionCallback.SAVE_MOMENT -> {
                val moment = draft() ?: return SessionResult(SessionError.ERROR_INVALID_STATE)
                val number = preferences.seconds("carPlayMomentSequence", 0) % 999 + 1
                preferences.setSeconds("carPlayMomentSequence", number)
                save(moment.copy(label = "CarPlay $number"))
            }
            CarSessionCallback.MARK_PROGRESS -> mark()
            CarSessionCallback.CYCLE_SPEED -> setSpeed(PlaybackRules.speeds[(PlaybackRules.speeds.indexOf(speed()) + 1) % PlaybackRules.speeds.size])
            else -> return SessionResult(SessionError.ERROR_NOT_SUPPORTED)
        }
        return SessionResult(SessionResult.RESULT_SUCCESS)
    }
}
