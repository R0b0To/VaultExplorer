package com.aeidolon.vaultexplorer.pip

import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.util.Rational
import android.view.SurfaceView
import androidx.core.content.ContextCompat
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.engine.VaultPlaybackSession
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * System picture-in-picture for video. Two ways in, both decided by Dart:
 *
 *  1. **PiP window** (the viewer's picture-in-picture button): `startWindow`
 *     launches [PictureInPictureActivity], which takes over the video output
 *     and shrinks into Android's PiP window by itself. The app stays where
 *     the person leaves it (the viewer closes, and they are back in the file
 *     manager) while the video floats on top. The window reports back with
 *     `windowEvent` (`entered`, `expanded`, `closed`, `audioOnly`, `failed`); Dart ends it
 *     with `closeWindow` and follows the video's shape with `setWindowRatio`.
 *
 *  2. **Automatic** ("automatic picture-in-picture"): the whole activity
 *     becomes the PiP window when the app is left. Dart calls `setState` with
 *     `armed = true` while a video plays and the setting is on, `armed =
 *     false` otherwise.
 *       - Android 12+ (API 31): `setAutoEnterEnabled(armed)`, so the system
 *         enters PiP on its own when the person leaves, with its proper
 *         animation.
 *       - Android 8-11: enter from [onUserLeaveHint].
 *     While that window is up, Dart replaces the app with just the video (see
 *     `PictureInPictureLayer`), reporting `modeChanged` / `dismissed`.
 *
 * Both windows carry the buttons built by [PictureInPictureActions]: previous /
 * play-pause / next, and **audio only**. Audio only closes the video window and
 * leaves the sound playing from the media notification (the player and its
 * media session keep running; only the video is gone). They are kept in step
 * with the session through [VaultPlaybackSession.onSnapshotChanged].
 */
class PictureInPictureController(private val activity: MainActivity) {

    private var channel: MethodChannel? = null
    private var armed = false
    private var aspect: Rational = Rational(16, 9)

    /** True while the activity is shown in the PiP window (automatic mode). */
    var isActive = false
        private set

    /** True from entering PiP until the activity is next resumed. */
    private var inPipSession = false

    /** True while a PiP window is being set up (the activity is covered). */
    private var entering = false

    /**
     * True from the "audio only" button (automatic mode) until the activity
     * next resumes. Sending the task to the back looks to [onStop] exactly like
     * the person closing the window, which pauses the video; this tells the two
     * apart.
     */
    private var audioOnlyRequested = false

    private var controlsRegistered = false

    // The window's buttons are PendingIntents, delivered as a broadcast.
    private val controlReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != PictureInPictureActions.BROADCAST_ACTION) return
            when (intent.getIntExtra(PictureInPictureActions.EXTRA_CONTROL, 0)) {
                PictureInPictureActions.CONTROL_PREVIOUS -> VaultPlaybackSession.skipToPrevious()
                PictureInPictureActions.CONTROL_TOGGLE -> VaultPlaybackSession.togglePlayPause()
                PictureInPictureActions.CONTROL_NEXT -> VaultPlaybackSession.skipToNext()
                PictureInPictureActions.CONTROL_AUDIO_ONLY -> switchToAudioOnly()
            }
        }
    }

    private val supported: Boolean by lazy {
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    fun attach(messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        // Share / quick-capture activities run their own engine; the window
        // belongs to the main one.
        if (activity.javaClass == MainActivity::class.java) {
            current = this
            registerControls()
        }
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
                "startWindow" -> {
                    val width = (call.argument<Number>("width") ?: 16).toInt()
                    val height = (call.argument<Number>("height") ?: 9).toInt()
                    result.success(startWindow(width, height))
                }
                "closeWindow" -> {
                    windowActivity?.closeFromApp()
                    result.success(true)
                }
                "setWindowRatio" -> {
                    val width = (call.argument<Number>("width") ?: 16).toInt()
                    val height = (call.argument<Number>("height") ?: 9).toInt()
                    windowActivity?.setAspect(width, height)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Whether the activity is (about to be) in PiP, or covered by the PiP
     * window's activity. The privacy curtain is skipped for a pause in that
     * case: it would otherwise cover the very video the person asked to keep
     * on screen, and flash over the app they come back to.
     */
    val keepsContentVisible: Boolean
        get() = (isActive || armed || entering) && isScreenOn()

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
        if (!armed || !supported || activity.isFinishing || activity.isDestroyed) return
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
        entering = false
        audioOnlyRequested = false
        // Some Android versions resume the activity while it is in the PiP
        // window; only a resume out of PiP ends the session.
        if (!isActive) inPipSession = false
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
        if (audioOnlyRequested) {
            // The "audio only" button, not a dismissal: the video must not
            // pause, the sound carries on.
            audioOnlyRequested = false
            return
        }
        channel?.invokeMethod("dismissed", null)
    }

    fun onDestroy() {
        // This activity's own receiver goes in any case; the rest belongs to the
        // main activity only (a share / quick-capture activity going away must
        // not close the window).
        unregisterControls()
        if (current !== this) return
        windowActivity?.closeFromApp()
        current = null
    }

    // --- Window buttons ---

    private fun registerControls() {
        if (controlsRegistered) return
        ContextCompat.registerReceiver(
            activity,
            controlReceiver,
            IntentFilter(PictureInPictureActions.BROADCAST_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        controlsRegistered = true
        VaultPlaybackSession.onSnapshotChanged = { refreshActions() }
    }

    private fun unregisterControls() {
        if (!controlsRegistered) return
        controlsRegistered = false
        // A newer main activity may already have taken the hook over.
        if (current === this) VaultPlaybackSession.onSnapshotChanged = null
        try {
            activity.unregisterReceiver(controlReceiver)
        } catch (e: IllegalArgumentException) {
            VeLog.w(TAG, e) { "PiP control receiver was already unregistered" }
        }
    }

    /** The session changed (play / pause, a new item): redraw the window's buttons. */
    private fun refreshActions() {
        val window = windowActivity
        if (window != null) {
            window.refreshActions()
            return
        }
        // Armed too, not only in the window: the buttons must already be right
        // for the frame the system enters PiP on its own.
        if (armed || isActive) applyParams()
    }

    /**
     * The window's "audio only" button: the video window goes away and the
     * sound carries on from the media notification.
     *  - Separate window: it just closes itself.
     *  - Automatic mode (the app itself is the window): the task is sent to the
     *    back, which dismisses the window without finishing the activity the
     *    player and media session live in. [onStop] then sees the flag and
     *    does not read it as a dismissal.
     */
    private fun switchToAudioOnly() {
        val window = windowActivity
        if (window != null) {
            window.audioOnlyFromApp()
            return
        }
        if (!isActive || activity.isFinishing || activity.isDestroyed) return
        audioOnlyRequested = true
        activity.moveTaskToBack(true)
    }

    // --- PiP window (separate activity) ---

    private fun startWindow(width: Int, height: Int): Boolean {
        if (!supported || activity.isFinishing || activity.isDestroyed) return false
        windowActivity?.closeFromApp()
        val intent = Intent(activity, PictureInPictureActivity::class.java)
            .putExtra(PictureInPictureActivity.EXTRA_WIDTH, width)
            .putExtra(PictureInPictureActivity.EXTRA_HEIGHT, height)
            .putExtra(PictureInPictureActivity.EXTRA_SECURE, activity.pipWindowWantsSecureFlag())
        entering = true
        return try {
            activity.startActivity(intent)
            true
        } catch (e: RuntimeException) {
            entering = false
            VeLog.w(TAG, e) { "Could not start the picture-in-picture window" }
            false
        }
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
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(aspect)
            .setActions(PictureInPictureActions.build(activity))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(armed)
        }
        return builder.build()
    }

    private fun sendWindowEvent(event: String) {
        if (event != "entered") entering = false
        channel?.invokeMethod("windowEvent", mapOf("event" to event))
    }

    companion object {
        private const val TAG = "PictureInPicture"
        const val CHANNEL = "com.aeidolon.vaultexplorer/pip"

        // Android rejects ratios outside 1:2.39 .. 2.39:1.
        private const val MIN_RATIO = 1.0 / 2.39
        private const val MAX_RATIO = 2.39

        @Volatile
        private var current: PictureInPictureController? = null

        /** The live PiP window activity, if any (main thread only). */
        @Volatile
        var windowActivity: PictureInPictureActivity? = null

        fun clampedRatio(width: Int, height: Int): Rational {
            if (width <= 0 || height <= 0) return Rational(16, 9)
            val ratio = width.toDouble() / height.toDouble()
            return when {
                ratio < MIN_RATIO -> Rational(100, 239)
                ratio > MAX_RATIO -> Rational(239, 100)
                else -> Rational(width, height)
            }
        }

        /** The PiP window asks for the video output. False if nothing plays. */
        fun attachWindowSurface(view: SurfaceView): Boolean =
            current?.activity?.attachPipSurface(view) ?: false

        /** The PiP window is going away: the Flutter texture gets the video back. */
        fun detachWindowSurface(view: SurfaceView) {
            current?.activity?.detachPipSurface(view)
        }

        /** Tells Dart what the PiP window did: entered, expanded, closed, failed. */
        fun windowEvent(event: String) {
            current?.sendWindowEvent(event)
        }
    }
}
