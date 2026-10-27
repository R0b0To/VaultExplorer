package com.aeidolon.vaultexplorer.pip

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.os.PowerManager
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog

/**
 * The picture-in-picture window: nothing but a SurfaceView the app's native
 * player draws into, and an immediate switch into Android's PiP mode.
 *
 * It is a separate activity on purpose. An activity in PiP *is* the window, so
 * if the app's own (Flutter) activity went into it the whole app would be
 * squeezed away with the video. With the video in its own activity the app
 * stays behind it, free to be used (the viewer closes and the person is back
 * in the file manager).
 *
 * What happens next is reported to Dart through [PictureInPictureController]:
 *  - `entered`  the PiP window is up;
 *  - `expanded` the person tapped the window to go back to full screen;
 *  - `closed`   the person dismissed the window;
 *  - `failed`   the window could not be shown.
 */
class PictureInPictureActivity : Activity(), SurfaceHolder.Callback {

    private lateinit var surfaceView: SurfaceView
    private var surfaceAttached = false
    private var resumed = false
    private var enterRequested = false
    private var inPip = false
    private var endedByApp = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getBooleanExtra(EXTRA_SECURE, false)) {
            // Same promise as the app's own window: no screenshots or
            // screen recordings of vault content.
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        surfaceView = SurfaceView(this)
        val root = FrameLayout(this)
        root.setBackgroundColor(Color.BLACK)
        root.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        setContentView(root)
        surfaceView.holder.addCallback(this)
        PictureInPictureController.windowActivity = this
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        if (!PictureInPictureController.attachWindowSurface(surfaceView)) {
            fail("nothing is playing")
            return
        }
        surfaceAttached = true
        maybeEnterPictureInPicture()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

    override fun surfaceDestroyed(holder: SurfaceHolder) = Unit

    override fun onResume() {
        super.onResume()
        resumed = true
        maybeEnterPictureInPicture()
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    // Entering needs a resumed activity and a video to show in it.
    private fun maybeEnterPictureInPicture() {
        if (enterRequested || !resumed || !surfaceAttached || isFinishing) return
        enterRequested = true
        val width = intent.getIntExtra(EXTRA_WIDTH, 16)
        val height = intent.getIntExtra(EXTRA_HEIGHT, 9)
        try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(PictureInPictureController.clampedRatio(width, height))
                .build()
            if (!enterPictureInPictureMode(params)) fail("the system refused")
        } catch (e: IllegalStateException) {
            fail("enterPictureInPictureMode threw: ${e.message}")
        } catch (e: IllegalArgumentException) {
            fail("enterPictureInPictureMode rejected its parameters: ${e.message}")
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            inPip = true
            PictureInPictureController.windowEvent("entered")
        } else if (inPip && !endedByApp && !isFinishing) {
            // Out of the PiP window without being closed: the person tapped it
            // to go back to the app. Bring the app forward and hand over.
            inPip = false
            endedByApp = true
            PictureInPictureController.windowEvent("expanded")
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            )
            finish()
        }
    }

    override fun onStop() {
        super.onStop()
        // Stopped while in the PiP window: the person dismissed it. (A screen
        // that turned off is not a dismissal.)
        if (inPip && !endedByApp && !isFinishing && isScreenOn()) {
            endedByApp = true
            PictureInPictureController.windowEvent("closed")
            finish()
        }
    }

    override fun onDestroy() {
        surfaceView.holder.removeCallback(this)
        PictureInPictureController.detachWindowSurface(surfaceView)
        if (PictureInPictureController.windowActivity === this) {
            PictureInPictureController.windowActivity = null
        }
        super.onDestroy()
    }

    /** The video's shape changed (next item): keep the window the same shape. */
    fun setAspect(width: Int, height: Int) {
        if (isFinishing || isDestroyed || !inPip) return
        try {
            setPictureInPictureParams(
                PictureInPictureParams.Builder()
                    .setAspectRatio(PictureInPictureController.clampedRatio(width, height))
                    .build(),
            )
        } catch (e: IllegalStateException) {
            VeLog.w(TAG, e) { "Could not resize the picture-in-picture window" }
        } catch (e: IllegalArgumentException) {
            VeLog.w(TAG, e) { "Resize rejected its parameters" }
        }
    }

    /** Dart is done with the window (playback ended, another video, a lock). */
    fun closeFromApp() {
        if (isFinishing || isDestroyed) return
        endedByApp = true
        finish()
    }

    private fun fail(reason: String) {
        VeLog.w(TAG) { "Picture-in-picture window failed: $reason" }
        if (endedByApp) return
        endedByApp = true
        PictureInPictureController.windowEvent("failed")
        finish()
    }

    private fun isScreenOn(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
        return power?.isInteractive ?: true
    }

    companion object {
        private const val TAG = "PictureInPictureActivity"
        const val EXTRA_WIDTH = "width"
        const val EXTRA_HEIGHT = "height"
        const val EXTRA_SECURE = "secure"
    }
}
