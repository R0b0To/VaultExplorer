package com.aeidolon.vaultexplorer.pip

import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.util.Rational
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * System picture-in-picture for video: when a video is playing and the person
 * leaves the app (home, recents, another app), the activity shrinks into
 * Android's PiP window instead of going away.
 *
 * Dart owns the decision of *whether* a video is worth keeping on screen. It
 * calls `setState` with `armed = true` while a video plays (and the setting
 * is on) and `armed = false` otherwise. This class only turns that into the
 * platform calls:
 *
 *  * Android 12+ (API 31): `setAutoEnterEnabled(armed)`, so the system enters
 *    PiP on its own when the person leaves, with its proper animation.
 *  * Android 8-11: enter from [onUserLeaveHint].
 *
 * While the window is up, Dart replaces the whole app with just the video
 * (see `PictureInPictureLayer`); this class reports mode changes to it with
 * `modeChanged`, and `dismissed` when the person closes the window.
 *
 * Playback controls inside the window come from the media session the
 * player already publishes; no custom actions are added here.
 */
class PictureInPictureController(private val activity: MainActivity) {

    private var channel: MethodChannel? = null
    private var armed = false
    private var aspect: Rational = Rational(16, 9)

    /** True while the activity is shown in the PiP window. */
    var isActive = false
        private set

    /** True from entering PiP until the activity is next resumed. */
    private var inPipSession = false

    private val supported: Boolean by lazy {
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    fun attach(messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(supported)
                "setState" -> {
                    val width = (call.argument<Number>("width") ?: 16).toInt()
                    val height = (call.argument<Number>("height") ?: 9).toInt()
                    armed = (call.argument<Boolean>("armed") ?: false) && supported
                    aspect = clampedRatio(width, height)
                    applyParams()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Whether the activity is (about to be) in PiP. The privacy curtain is
     * skipped for a pause in that case: it would otherwise cover the very
     * video the person asked to keep on screen.
     */
    val keepsContentVisible: Boolean
        get() = (isActive || armed) && isScreenOn()

    // A pause because the screen turned off is never a PiP entry: the curtain
    // must still cover the last frame there.
    private fun isScreenOn(): Boolean {
        val power = activity.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return power?.isInteractive ?: true
    }

    fun onUserLeaveHint() {
        // From API 31 the system enters on its own (auto-enter); entering here
        // as well would race it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        if (!armed || !supported || activity.isFinishing) return
        try {
            activity.enterPictureInPictureMode(buildParams())
        } catch (e: IllegalStateException) {
            VeLog.w(TAG, e) { "enterPictureInPictureMode refused" }
        } catch (e: IllegalArgumentException) {
            VeLog.w(TAG, e) { "enterPictureInPictureMode rejected its parameters" }
        }
    }

    fun onModeChanged(active: Boolean) {
        isActive = active
        if (active) inPipSession = true
        channel?.invokeMethod("modeChanged", mapOf("active" to active))
    }

    fun onResume() {
        inPipSession = false
    }

    /**
     * The activity stopped. If it was in the PiP window, the person closed it
     * (dragged it away or tapped X): tell Dart so the video pauses. A screen
     * that simply turned off is not a close.
     */
    fun onStop() {
        if (!inPipSession) return
        inPipSession = false
        if (!isScreenOn()) return
        channel?.invokeMethod("dismissed", null)
    }

    private fun applyParams() {
        if (!supported || activity.isFinishing || activity.isDestroyed) return
        try {
            activity.setPictureInPictureParams(buildParams())
        } catch (e: IllegalStateException) {
            VeLog.w(TAG, e) { "setPictureInPictureParams refused" }
        } catch (e: IllegalArgumentException) {
            VeLog.w(TAG, e) { "setPictureInPictureParams rejected its parameters" }
        }
    }

    private fun buildParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(aspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(armed)
        }
        return builder.build()
    }

    companion object {
        private const val TAG = "PictureInPicture"
        const val CHANNEL = "com.aeidolon.vaultexplorer/pip"

        // Android rejects ratios outside 1:2.39 .. 2.39:1.
        private const val MIN_RATIO = 1.0 / 2.39
        private const val MAX_RATIO = 2.39

        fun clampedRatio(width: Int, height: Int): Rational {
            if (width <= 0 || height <= 0) return Rational(16, 9)
            val ratio = width.toDouble() / height.toDouble()
            return when {
                ratio < MIN_RATIO -> Rational(100, 239)
                ratio > MAX_RATIO -> Rational(239, 100)
                else -> Rational(width, height)
            }
        }
    }
}
