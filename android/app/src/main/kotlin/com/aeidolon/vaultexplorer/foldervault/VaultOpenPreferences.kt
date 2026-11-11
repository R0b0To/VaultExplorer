package com.aeidolon.vaultexplorer.foldervault

import android.content.Context

/**
 * Per-vault open-time options that must be honored by every code path that opens a folder vault
 * natively, not just the Dart-driven unlock.
 *
 * A Cryptomator vault is opened from two places that never share state: `VaultUnlockHandlers`
 * (Dart-driven, has a `ContainerRecord`) and `VaultAutomationReceiver` (automation and scheduled sync,
 * no Dart, no `ContainerRecord`). Both end in `ContainerLifecycleCore.unlockDirectoryVault`, which reads
 * these options, so the setting applies to all callers, including future ones.
 *
 * Keyed by the same container URI string `ContainerSessionRegistry` uses. Nothing secret lives here, so a
 * plain `SharedPreferences` file is enough (unlike `AutomationSettings`).
 */
object VaultOpenPreferences {
    private const val PREFS_NAME = "vaultexplorer_vault_open_prefs"
    private const val KEY_BACKUP_KEY_FILES_PREFIX = "kfbak:" // + container URI -> Boolean; absent = true

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Whether a read-write Cryptomator unlock writes `.bkup` copies of the key files. Default: true. */
    fun getBackupKeyFiles(context: Context, uri: String): Boolean =
        prefs(context).getBoolean(KEY_BACKUP_KEY_FILES_PREFIX + uri, true)

    fun setBackupKeyFiles(context: Context, uri: String, enabled: Boolean) {
        val editor = prefs(context).edit()
        // Store only the non-default value so removing the preference and "on" are the same state.
        if (enabled) editor.remove(KEY_BACKUP_KEY_FILES_PREFIX + uri)
        else editor.putBoolean(KEY_BACKUP_KEY_FILES_PREFIX + uri, false)
        editor.apply()
    }

    /** Drops every option stored for [uri]. Call when the vault is removed from the app. */
    fun clearVault(context: Context, uri: String) {
        prefs(context).edit().remove(KEY_BACKUP_KEY_FILES_PREFIX + uri).apply()
    }
}
