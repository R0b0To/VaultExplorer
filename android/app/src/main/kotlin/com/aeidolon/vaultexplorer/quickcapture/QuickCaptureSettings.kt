package com.aeidolon.vaultexplorer.quickcapture

import android.content.Context

/**
 * Whether the Quick Capture Quick Settings tile is meant to be active.
 * Mirrors [com.aeidolon.vaultexplorer.panic.PanicSettings] -- a plain,
 * unencrypted SharedPreferences store, since knowing "this device has a
 * Quick Capture tile enabled" gives an observer nothing beyond what
 * seeing the tile itself (or the app being installed) already reveals.
 *
 * Deliberately its own store rather than reusing PanicSettings' prefs
 * file, for the same narrow-blast-radius reasoning PanicSettings' own
 * doc comment gives for keeping PanicKit/duress settings separate.
 */
object QuickCaptureSettings {
    private const val PREFS_NAME = "vaultexplorer_quick_capture_settings"
    private const val PREF_TILE_ENABLED = "tile_enabled"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Off by default -- [CaptureTileService] checks this before treating
     *  a tile click as a real request, and the Settings screen flips it
     *  once the person has actually opted in. */
    fun isTileEnabled(context: Context): Boolean =
        prefs(context).getBoolean(PREF_TILE_ENABLED, false)

    fun setTileEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(PREF_TILE_ENABLED, enabled).apply()
    }
}
