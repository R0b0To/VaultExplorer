package com.aeidolon.vaultexplorer.syncbridge

import android.content.Context
import java.io.File

/**
 * A zero-content marker file under `filesDir`, existence-only, written by
 * the `:syncbridge` process whenever `sync_vaults` transitions between
 * empty and non-empty, and read by the main process before it even
 * attempts to bind [ILedgerWriter] (docs/architecture.md ADR-029).
 *
 * Not sensitive: it carries no vault id, path, or name — only "at least
 * one vault is registered for sync, somewhere". A plain file rather than
 * `SharedPreferences` deliberately, since `SharedPreferences`' own
 * multi-process story (`MODE_MULTI_PROCESS`) has been deprecated and
 * unreliable since API 23; a file's `exists()` check has no such caveat
 * and is cheap enough to call from every `ContainerEngine` write hook.
 */
object SyncBridgeActiveMarker {
    private const val FILE_NAME = "syncbridge_active.marker"

    private fun file(context: Context): File = File(context.applicationContext.filesDir, FILE_NAME)

    fun isActive(context: Context): Boolean = file(context).exists()

    fun setActive(context: Context, active: Boolean) {
        val f = file(context)
        if (active) {
            if (!f.exists()) f.createNewFile()
        } else {
            if (f.exists()) f.delete()
        }
    }
}
