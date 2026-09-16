package com.aeidolon.vaultexplorer

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.OnBackPressedCallback
import com.aeidolon.vaultexplorer.bridge.IncomingShareBridge
import com.aeidolon.vaultexplorer.bridge.LocalIncomingShareBridge

/**
 * Dedicated Share Activity running in an isolated task window.
 *
 * Inherits Flutter engine and handlers from [MainActivity], but isolates
 * task lifecycle so finish() removes only this task window.
 */
class VaultShareActivity : MainActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // 1. Pre-take persistable permissions before intent consumption
        takeIncomingUriPermissions(intent)

        // 2. super.onCreate configures FlutterEngine and runs shareIntentHandlers.handleIncomingIntent
        super.onCreate(savedInstanceState)

        // 3. Back gesture dismisses task window cleanly
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                finishAndRemoveTask()
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        takeIncomingUriPermissions(intent)
        super.onNewIntent(intent)
    }

    /**
     * Intercepts finish() (which Flutter's SystemNavigator.pop() invokes)
     * and calls finishAndRemoveTask() to tear down only this window and its Recents card.
     */
    override fun finish() {
        finishAndRemoveTask()
    }

    /**
     * Best-effort persistence for URIs provided by the sending application.
     */
    private fun takeIncomingUriPermissions(intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val flags = intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (flags == 0) return

        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_SEND) {
            val single = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            single?.let { uris.add(it) }
        } else {
            val many = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            many?.let { uris.addAll(it) }
        }

        intent.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i).uri?.let { uris.add(it) }
            }
        }

        for (uri in uris) {
            try {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: SecurityException) {
                // Non-persistable URIs retain transient access for this activity lifecycle
            }
        }
    }

    override fun onDestroy() {
        // Clear any residual bridge state so MainActivity never reads leftover items
        IncomingShareBridge.clear()
        LocalIncomingShareBridge.clear()
        IncomingShareBridge.channel = null
        LocalIncomingShareBridge.channel = null

        super.onDestroy()
    }
}