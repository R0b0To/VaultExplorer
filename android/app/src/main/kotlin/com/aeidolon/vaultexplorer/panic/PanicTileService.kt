package com.aeidolon.vaultexplorer.panic

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import com.aeidolon.vaultexplorer.VeLog
import java.util.concurrent.Executors

@RequiresApi(Build.VERSION_CODES.N)
class PanicTileService : TileService() {

    companion object {
        private const val TAG = "PanicTileService"
        private val tileExecutor = Executors.newSingleThreadExecutor()
    }

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        val enabled = PanicSettings.isQuickTileEnabled(this)
        tile.state = if (enabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        if (!PanicSettings.isQuickTileEnabled(this)) {
            VeLog.i(TAG) { "Tile clicked but feature is disabled in settings" }
            return
        }

        val tier = PanicSettings.getConfiguredTier(this)
        VeLog.i(TAG) { "Emergency Tile clicked. Triggering tier: $tier" }

        val appContext = applicationContext
        tileExecutor.execute {
            PanicManager.execute(appContext, tier, source = "quick_tile")
        }
    }
}
