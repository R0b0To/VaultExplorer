package com.aeidolon.vaultexplorer.panic

/**
 * The three configurable panic severity tiers from the "Emergency Panic &
 * Duress Systems" architecture plan, section 2. [level] is the ordinal
 * used both for persistence ([PanicSettings]) and for the "this tier
 * includes everything below it" cascade in [PanicManager.execute] --
 * CREDENTIAL_PURGE always re-runs SESSION_PURGE's steps first, and
 * NUCLEAR_WIPE always re-runs CREDENTIAL_PURGE's (which re-runs
 * SESSION_PURGE's).
 */
enum class PanicTier(val level: Int) {
    /** Transient lockout: unmount every open container, keep container
     *  files, keep Keystore master keys and every other cached credential. */
    SESSION_PURGE(1),

    /** Identity reset: everything in [SESSION_PURGE], plus every Keystore
     *  alias and cached credential (remembered passwords, automation
     *  tokens, recent/bookmark/usage state). Container files on disk are
     *  left untouched -- only the app's own memory of them is erased. */
    CREDENTIAL_PURGE(2),

    /** Destruction: everything in [CREDENTIAL_PURGE], plus the app's own
     *  internal storage, a system uninstall prompt, and process death. */
    NUCLEAR_WIPE(3),
    ;

    /** True if this tier's work fully subsumes [other]'s (i.e. [other] is
     *  the same tier or a less destructive one). */
    fun atLeast(other: PanicTier): Boolean = level >= other.level

    companion object {
        fun fromLevel(level: Int): PanicTier? = entries.find { it.level == level }
    }
}
