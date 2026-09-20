package com.aeidolon.vaultexplorer

import android.content.Intent
import android.os.Bundle
import androidx.activity.OnBackPressedCallback
import com.aeidolon.vaultexplorer.bridge.QuickCaptureBridge

/**
 * Dedicated entry-point Activity for the "Quick Capture" Quick Settings
 * tile (see quickcapture/CaptureTileService.kt) and the pinned
 * home-screen shortcut (see quickcapture/QuickCaptureShortcuts.kt).
 *
 * Inherits Flutter engine and handlers from [MainActivity], same as
 * [VaultShareActivity], and for the same reason: it runs in its own
 * isolated task window (finishAndRemoveTask() on back/finish) so this
 * entry point neither resumes nor pollutes whatever the main app task
 * was doing. Unlike [VaultShareActivity] there's no incoming payload to
 * stage -- just a request to show the capture screen -- so
 * [QuickCaptureBridge] is a plain boolean flag rather than a buffered
 * item list.
 *
 * Deliberately does NOT check any app-lock/PIN state before delivering
 * the request: reaching the camera preview with no unlock prompt is the
 * point of this entry point (see the feature's design notes on why
 * that's a stated decision, not an oversight) -- Dart still requires a
 * real vault to be unlocked before anything captured here can actually
 * be saved anywhere (see QuickCaptureSaveFlow / ShareDestinationSheet's
 * existing unlock step, which this reuses unmodified).
 */
class VaultQuickCaptureActivity : MainActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        QuickCaptureBridge.deliver()
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                finishAndRemoveTask()
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        QuickCaptureBridge.deliver()
    }

    override fun finish() {
        finishAndRemoveTask()
    }

    override fun onDestroy() {
        QuickCaptureBridge.clear()
        QuickCaptureBridge.channel = null
        super.onDestroy()
    }
}
