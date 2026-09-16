package com.aeidolon.vaultexplorer.panic

import android.content.Context

/**
 * State for the "wipe on reboot" trigger: whether it is currently armed,
 * and which [PanicTier] it will run if it fires. This is the third
 * trigger surface alongside the Quick Settings tile and the PanicKit
 * broadcast receiver -- see [PanicBootReceiver] for the actual
 * android.intent.action.BOOT_COMPLETED handling this configures.
 *
 * Deliberately its own store rather than folded into [PanicSettings],
 * for the same reason [PanicSettings]' own doc comment gives for keeping
 * PanicKit pairing and duress config separate: a narrow, single-purpose
 * store so a bug or future feature on one can't reach another.
 *
 * Not secret, for the same reason as [PanicSettings]: knowing "this
 * device is armed to wipe on its next boot" (or which tier) gives an
 * observer nothing actionable beyond what having the app installed
 * already reveals. Plain, unencrypted SharedPreferences.
 */
object PanicBootTriggerSettings {
    private const val PREFS_NAME = "vaultexplorer_panic_boot_trigger_settings"
    private const val PREF_ARMED = "armed"
    private const val PREF_ARMED_TIER = "armed_tier"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Off by default -- a fresh install, or one that has never visited
     *  the Settings screen's boot-trigger switch, must never be armed. */
    fun isArmed(context: Context): Boolean =
        prefs(context).getBoolean(PREF_ARMED, false)

    fun setArmed(context: Context, armed: Boolean) {
        prefs(context).edit().putBoolean(PREF_ARMED, armed).apply()
    }

    /**
     * Synchronous, durable disarm -- [PanicBootReceiver] calls this
     * (never [setArmed]) immediately before it calls
     * [PanicManager.execute], using commit() rather than apply() so the
     * write is guaranteed to have reached disk before the wipe itself can
     * end the process. This is what makes the trigger fire at most once
     * per arm: a NUCLEAR_WIPE tier can kill the process moments after
     * execute() is called, and by then this must have already landed.
     */
    fun disarmSynchronously(context: Context) {
        prefs(context).edit().putBoolean(PREF_ARMED, false).commit()
    }

    /**
     * Defaults to [PanicTier.SESSION_PURGE] -- the least destructive tier --
     * matching [PanicSettings.getConfiguredTier]'s own reasoning: a device
     * armed before ever picking a tier explicitly must never run something
     * more destructive than the user knowingly opted into.
     */
    fun getArmedTier(context: Context): PanicTier =
        PanicTier.fromLevel(prefs(context).getInt(PREF_ARMED_TIER, PanicTier.SESSION_PURGE.level))
            ?: PanicTier.SESSION_PURGE

    fun setArmedTier(context: Context, tier: PanicTier) {
        prefs(context).edit().putInt(PREF_ARMED_TIER, tier.level).apply()
    }
}
