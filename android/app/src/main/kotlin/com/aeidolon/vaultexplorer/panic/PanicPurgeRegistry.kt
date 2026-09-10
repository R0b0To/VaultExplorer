package com.aeidolon.vaultexplorer.panic

/**
 * Registry of SharedPreferences store names a Tier 2+ ([PanicTier.CREDENTIAL_PURGE]
 * or [PanicTier.NUCLEAR_WIPE]) panic wipe must clear as "cached credentials
 * / identity", so each subsystem that owns one of these stores can
 * register itself here instead of [PanicManager] or [StorageShredder]
 * having to hardcode every current and future credential store by name.
 *
 * Pre-seeded with every credential-bearing store that exists as of this
 * (Phase 1) implementation:
 *  - "vaultexplorer_app_secure_storage" -- [com.aeidolon.vaultexplorer.handlers.SecureStorageHandlers]'
 *    generic Dart-facing key-value store. Since this app has no other
 *    persistence layer (no shared_preferences plugin, no database), this
 *    is also where the recent-container list, dashboard bookmarks, and
 *    usage statistics the architecture plan calls out by name actually
 *    live -- clearing this store satisfies that requirement too.
 *  - "vc2_derived_keys" -- [com.aeidolon.vaultexplorer.handlers.DerivedKeyHandlers]'
 *    per-container "remembered password" cache.
 *  - "vaultexplorer_automation_settings" -- [com.aeidolon.vaultexplorer.automation.AutomationSettings]'
 *    API token and per-vault cached automation passwords/keyfiles/PIM.
 *
 * Phase 5 (Duress Unlock) and Phase 2 (PanicKit pairing) will each
 * introduce at least one more such store (duress credential hash,
 * trusted-sender pairing state) -- call [registerCredentialStore] from
 * that subsystem's own `object` init block rather than editing this file,
 * so this registry never needs to change again as new credential stores
 * are added.
 */
object PanicPurgeRegistry {
    private val _credentialPrefsNames = mutableSetOf(
        "vaultexplorer_app_secure_storage",
        "vc2_derived_keys",
        "vaultexplorer_automation_settings",
    )

    val credentialPrefsNames: Set<String>
        get() = _credentialPrefsNames

    @Synchronized
    fun registerCredentialStore(prefsName: String) {
        _credentialPrefsNames.add(prefsName)
    }
}
