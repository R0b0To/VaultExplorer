package com.aeidolon.vaultexplorer.quickcapture

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import com.aeidolon.vaultexplorer.VaultQuickCaptureActivity
import com.aeidolon.vaultexplorer.VeLog

/**
 * Quick Settings tile that jumps straight to the camera viewfinder (see
 * [VaultQuickCaptureActivity]) with no unlock prompt of any kind --
 * that's the point of this entry point, not an oversight; see
 * VaultQuickCaptureActivity's class doc.
 *
 * Off by default, same pattern as
 * [com.aeidolon.vaultexplorer.panic.PanicTileService]: the person has to
 * explicitly enable it from Settings before the tile does anything, so
 * simply having the tile available in the "Edit tiles" tray isn't itself
 * a behavior change for anyone who hasn't opted in.
 */
@RequiresApi(Build.VERSION_CODES.N)
class CaptureTileService : TileService() {

    companion object {
        private const val TAG = "CaptureTileService"

        /** startActivityAndCollapse(Intent) throws UnsupportedOperationException
         *  from API 34 onward -- only the PendingIntent overload is allowed. */
        private const val ANDROID_14 = 34
    }

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        val enabled = QuickCaptureSettings.isTileEnabled(this)
        tile.state = if (enabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        if (!QuickCaptureSettings.isTileEnabled(this)) {
            VeLog.i(TAG) { "Tile clicked but Quick Capture is disabled in settings" }
            return
        }

        val intent = Intent(this, VaultQuickCaptureActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK
        }

        if (Build.VERSION.SDK_INT >= ANDROID_14) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
