package com.aeidolon.vaultexplorer.panic

import java.security.KeyStore
import com.aeidolon.vaultexplorer.VeLog

/**
 * Phase 1's "Keystore Purge Subsystem": deletes every alias currently
 * stored in the app's AndroidKeyStore instance.
 */
object KeystorePurge {
    private const val TAG = "PanicManager_Keystore"

    /**
     * Enumerates and deletes every AndroidKeyStore alias this app owns --
     * [com.aeidolon.vaultexplorer.handlers.SecureStorageHandlers]' secure-storage
     * master key, every per-container "remembered password" key
     * ([com.aeidolon.vaultexplorer.handlers.DerivedKeyHandlers], alias prefix
     * "vc2_derived_"), [com.aeidolon.vaultexplorer.automation.AutomationSettings]'
     * key, and anything a future feature adds.
     *
     * Deliberately unconditional rather than filtered by alias prefix:
     * `KeyStore.getInstance("AndroidKeyStore")` is already scoped to this
     * app's own UID by the OS -- no other app's keys can appear in this
     * enumeration -- so there is no legitimate alias here that a Tier 2+
     * purge should spare. Any key still under a spared alias would just
     * leave a matching cached-credential blob decryptable, which defeats
     * the entire point of a "Credential & Metadata Purge" tier.
     *
     * Returns the number of aliases actually deleted (for diagnostics /
     * the verification checklist), not a boolean -- a partial failure
     * (one alias's deleteEntry throwing) still lets the sweep continue
     * over the rest rather than aborting, since a panic wipe is
     * best-effort all the way through.
     */
    fun purgeAll(): Int {
        return try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            // java.util.Collections.list(), not a Kotlin Enumeration
            // extension -- java.security.KeyStore.aliases() returns a raw
            // java.util.Enumeration<String>, and Collections.list is the
            // one guaranteed-available way to drain it into a List without
            // consuming it twice (Enumeration has no reset/rewind).
            val aliases = java.util.Collections.list(keyStore.aliases())
            var deleted = 0
            for (alias in aliases) {
                try {
                    keyStore.deleteEntry(alias)
                    deleted++
                } catch (e: Exception) {
                    VeLog.w(TAG, e) { "purgeAll: failed to delete Keystore alias" }
                }
            }
            VeLog.i(TAG) { "purgeAll: deleted $deleted/${aliases.size} Keystore alias(es)" }
            deleted
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "purgeAll: failed to open/enumerate AndroidKeyStore" }
            0
        }
    }

    /** Number of aliases currently present, for tests/diagnostics -- not used
     *  on the purge path itself, which re-enumerates fresh in [purgeAll]. */
    fun aliasCount(): Int = try {
        java.util.Collections.list(
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.aliases(),
        ).size
    } catch (e: Exception) {
        VeLog.w(TAG, e) { "aliasCount: failed to open/enumerate AndroidKeyStore" }
        0
    }
}
