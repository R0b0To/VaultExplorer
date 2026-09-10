package com.aeidolon.vaultexplorer.panic

import android.content.Context

/**
 * The one knob [PanicManager] itself needs at this (Phase 1) stage: which
 * tier a headless trigger should run when it doesn't specify one
 * explicitly, and whether the Quick Settings tile is meant to be active.
 *
 * Not secret -- knowing "this device is configured to wipe on panic" (or
 * which tier it's set to) gives an observer nothing actionable beyond
 * what having the app installed already reveals -- so this is a plain,
 * unencrypted SharedPreferences store, unlike the credential-bearing ones
 * tracked in [PanicPurgeRegistry].
 *
 * PanicKit pairing state (Phase 2: trusted sender package, connected
 * status) and duress configuration (Phase 5: duress credential hash,
 * decoy-vs-purge action) are deliberately NOT here -- each gets its own
 * settings object when its phase is implemented, mirroring how
 * AutomationSettings is kept separate from SecureStorageHandlers today
 * (see AutomationSettings' own doc comment for the reasoning: narrow,
 * separate stores so a bug or future feature on one can't reach another).
 */
object PanicSettings {
    private const val PREFS_NAME = "vaultexplorer_panic_settings"
    private const val PREF_CONFIGURED_TIER = "configured_tier"
    private const val PREF_QUICK_TILE_ENABLED = "quick_tile_enabled"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * Defaults to [PanicTier.SESSION_PURGE] -- the least destructive tier --
     * so a trigger firing before the user has ever visited the Settings
     * screen's Panic Level Selector (Phase 6) can never accidentally run a
     * more destructive wipe than they knowingly opted into.
     */
    fun getConfiguredTier(context: Context): PanicTier =
        PanicTier.fromLevel(prefs(context).getInt(PREF_CONFIGURED_TIER, PanicTier.SESSION_PURGE.level))
            ?: PanicTier.SESSION_PURGE

    fun setConfiguredTier(context: Context, tier: PanicTier) {
        prefs(context).edit().putInt(PREF_CONFIGURED_TIER, tier.level).apply()
    }

    /** Off by default -- Phase 3's TileService checks this before treating
     *  a tile click as a real trigger, and Phase 6's settings screen flips
     *  it once the user has actually walked through adding the tile. */
    fun isQuickTileEnabled(context: Context): Boolean =
        prefs(context).getBoolean(PREF_QUICK_TILE_ENABLED, false)

    fun setQuickTileEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(PREF_QUICK_TILE_ENABLED, enabled).apply()
    }
}
