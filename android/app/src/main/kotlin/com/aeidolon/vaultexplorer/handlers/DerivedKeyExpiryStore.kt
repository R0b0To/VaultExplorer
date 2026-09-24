package com.aeidolon.vaultexplorer.handlers

import android.content.SharedPreferences
import java.security.MessageDigest

/**
 * Bookkeeping for the optional lifetime of a container's cached derived
 * key (see [DerivedKeyHandlers]). Lives in the same `vc2_derived_keys`
 * SharedPreferences file as the encrypted key blobs themselves, so a panic
 * wipe that clears that file (see `PanicPurgeRegistry` / `StorageShredder`)
 * takes the expiry state with it -- no second store to register.
 *
 * The expiry is an *absolute* timestamp chosen by the user when they save
 * the container's settings ("30 days from now"). It is deliberately not
 * refreshed by later unlocks and not reset when a key is re-cached: it only
 * changes when the user overwrites it.
 *
 * Everything here is keyed by a hash of the container path exactly as Dart
 * passes it to `storeDerivedKey` / `loadDerivedKey` (the URI, or the device
 * name for USB drives), never by the blob alias. The blob alias is derived
 * from a fingerprint of the container file and needs file access to compute,
 * which may be impossible (unplugged drive, unmounted SD card) at the very
 * moment an expired key has to go. The alias is therefore remembered
 * alongside the expiry the first time it is known, so a purge never needs
 * to touch the container.
 *
 * Layout inside the prefs file (`<h>` = SHA-256 hex of the path):
 *  - `vc2_dk_exp_<h>`   -- Long, expiry as epoch milliseconds
 *  - `vc2_dk_path_<h>`  -- String, the path itself (so Dart can be told
 *                          which container a purge belonged to)
 *  - `vc2_dk_alias_<h>` -- String, the alias of the cached blob
 *  - `vc2_dk_purged`    -- StringSet of paths purged since Dart last asked
 *
 * None of these prefixes can collide with a blob key, which always starts
 * with `vc2_derived_`.
 */
class DerivedKeyExpiryStore(
    private val prefs: SharedPreferences,
    private val clock: () -> Long = { System.currentTimeMillis() },
) {
    /** A vault whose cached key has outlived its configured lifetime.
     *  [alias] is null when the blob alias was never recorded; the caller
     *  then has to derive it from [path]. */
    data class Due(val pathKey: String, val path: String?, val alias: String?)

    /** Epoch-millisecond expiry configured for [path], or null for none. */
    fun expiryOf(path: String): Long? {
        val key = EXPIRY_PREFIX + pathKey(path)
        return if (prefs.contains(key)) prefs.getLong(key, 0L) else null
    }

    /**
     * Sets, replaces or (with a null [expiresAtMs]) removes the expiry for
     * [path]. [blobAlias] is the alias of the blob currently cached for it,
     * if one exists, so the purge can find it later without file access.
     *
     * Either way the user has just made an explicit choice about this vault,
     * so any earlier purge still waiting to be reported to Dart is dropped:
     * reporting it would switch caching off behind that choice.
     */
    fun setExpiry(path: String, expiresAtMs: Long?, blobAlias: String?) {
        val pk = pathKey(path)
        val editor = prefs.edit()
        if (expiresAtMs == null) {
            editor.remove(EXPIRY_PREFIX + pk)
                .remove(PATH_PREFIX + pk)
                .remove(ALIAS_PREFIX + pk)
        } else {
            editor.putLong(EXPIRY_PREFIX + pk, expiresAtMs)
                .putString(PATH_PREFIX + pk, path)
            if (blobAlias != null) editor.putString(ALIAS_PREFIX + pk, blobAlias)
        }
        val pending = prefs.getStringSet(PURGED_PATHS, null)
        if (pending != null && pending.contains(path)) {
            editor.putStringSet(PURGED_PATHS, pending.toMutableSet().apply { remove(path) })
        }
        editor.commit()
    }

    /**
     * Called while a key is being cached: adds the alias mapping to the
     * caller's own pending [editor] so it lands atomically with the blob.
     * A no-op for paths without an expiry, so vaults that never asked for
     * one leave no extra trace in the prefs file.
     */
    fun recordStored(editor: SharedPreferences.Editor, path: String, alias: String) {
        val pk = pathKey(path)
        if (prefs.contains(EXPIRY_PREFIX + pk)) editor.putString(ALIAS_PREFIX + pk, alias)
    }

    /** [path]'s entry if its expiry has passed, else null. */
    fun dueFor(path: String): Due? {
        val expiry = expiryOf(path) ?: return null
        if (expiry > clock()) return null
        val pk = pathKey(path)
        return Due(pk, path, prefs.getString(ALIAS_PREFIX + pk, null))
    }

    /** Every entry whose expiry has passed. */
    fun due(): List<Due> {
        val now = clock()
        val out = ArrayList<Due>()
        for ((key, value) in prefs.all) {
            if (!key.startsWith(EXPIRY_PREFIX) || value !is Long || value > now) continue
            val pk = key.removePrefix(EXPIRY_PREFIX)
            out.add(
                Due(
                    pathKey = pk,
                    path = prefs.getString(PATH_PREFIX + pk, null),
                    alias = prefs.getString(ALIAS_PREFIX + pk, null),
                )
            )
        }
        return out
    }

    /**
     * Records that [due]'s cached key is gone: drops the blob stored under
     * [blobAlias] (the caller deletes the matching Keystore entry) and
     * remembers the path so [takePurgedPaths] can report it to Dart.
     *
     * The expiry bookkeeping is removed too -- an elapsed expiry must not
     * linger and silently apply to a later, unrelated key -- unless
     * [keepExpiry] is set. The unlock path keeps it: Dart still has caching
     * switched on until the next launch reports the purge, so a key cached
     * again in the meantime has to stay subject to the same (already
     * elapsed) expiry rather than escape it and live forever.
     */
    fun markPurged(due: Due, blobAlias: String?, keepExpiry: Boolean = false) {
        val editor = prefs.edit()
        if (blobAlias != null) editor.remove(blobAlias)
        if (!keepExpiry) {
            editor.remove(EXPIRY_PREFIX + due.pathKey)
                .remove(PATH_PREFIX + due.pathKey)
                .remove(ALIAS_PREFIX + due.pathKey)
        }
        due.path?.let { path ->
            val pending = (prefs.getStringSet(PURGED_PATHS, null) ?: emptySet()).toMutableSet()
            pending.add(path)
            editor.putStringSet(PURGED_PATHS, pending)
        }
        editor.commit()
    }

    /** Paths purged since the last call; clears the list. */
    fun takePurgedPaths(): List<String> {
        val pending = prefs.getStringSet(PURGED_PATHS, null)?.toList() ?: return emptyList()
        prefs.edit().remove(PURGED_PATHS).commit()
        return pending
    }

    /** Drops all expiry state for [path] (container removed, or caching
     *  turned off) without touching any blob. */
    fun forget(path: String) = setExpiry(path, null, null)

    companion object {
        private const val EXPIRY_PREFIX = "vc2_dk_exp_"
        private const val PATH_PREFIX = "vc2_dk_path_"
        private const val ALIAS_PREFIX = "vc2_dk_alias_"
        private const val PURGED_PATHS = "vc2_dk_purged"

        fun pathKey(path: String): String =
            MessageDigest.getInstance("SHA-256")
                .digest(path.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }
    }
}
