package com.aeidolon.vaultexplorer.panic

import android.content.Context
import java.io.File
import com.aeidolon.vaultexplorer.SecureFileWipe
import com.aeidolon.vaultexplorer.VeLog

/**
 * Phase 1's "Storage Shredding Subsystem": destroys SharedPreferences-backed
 * credential stores for a Tier 2 purge, and every byte of internal app
 * storage for a Tier 3 nuclear wipe.
 *
 * Every deletion here goes through [SecureFileWipe.secureDeleteFile]
 * rather than `File.delete()` -- the whole reason a Tier 2/3 wipe exists
 * is to make cached secrets and identifying metadata actually
 * unrecoverable, and a plain unlink leaves the underlying disk blocks
 * readable until the filesystem happens to reuse them (see
 * [SecureFileWipe]'s own doc comment).
 */
object StorageShredder {
    private const val TAG = "PanicManager_Storage"

    /**
     * Securely destroys one named SharedPreferences store: clears it
     * through the normal API first (so any `by lazy`-cached
     * SharedPreferences handle already held open elsewhere in this
     * process -- [com.aeidolon.vaultexplorer.handlers.SecureStorageHandlers],
     * [com.aeidolon.vaultexplorer.handlers.DerivedKeyHandlers], and
     * [com.aeidolon.vaultexplorer.automation.AutomationSettings] all have
     * one -- observes empty content immediately rather than silently
     * re-writing stale values on its next write), then finds the actual
     * backing XML file on disk and overwrites it directly -- clear()'s
     * freshly-written empty file is not itself the security property we
     * need; the *previous* content's disk blocks are, and those are what
     * [SecureFileWipe] actually destroys.
     */
    fun securelyClearPrefsFile(context: Context, prefsName: String): Boolean {
        var ok = true
        try {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit().clear().commit()
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "securelyClearPrefsFile: clear() failed" }
            ok = false
        }
        val prefsFile = File(File(context.applicationInfo.dataDir, "shared_prefs"), "$prefsName.xml")
        if (prefsFile.exists() && !SecureFileWipe.secureDeleteFile(prefsFile)) {
            ok = false
        }
        return ok
    }

    /** Tier 2 entry point: runs [securelyClearPrefsFile] over every store
     *  registered in [PanicPurgeRegistry.credentialPrefsNames]. Returns how
     *  many were cleared successfully. */
    fun purgeCredentialStores(context: Context): Int {
        var cleared = 0
        val names = PanicPurgeRegistry.credentialPrefsNames
        for (name in names) {
            if (securelyClearPrefsFile(context, name)) cleared++
        }
        VeLog.i(TAG) { "purgeCredentialStores: cleared $cleared/${names.size} store(s)" }
        return cleared
    }

    /**
     * Tier 3 only: recursively secure-deletes every file under [dir], then
     * removes the now-empty subdirectories bottom-up. [dir] itself is
     * never deleted (Android expects filesDir/cacheDir/etc. to keep
     * existing as directories for the lifetime of the process). No-op if
     * [dir] is null or doesn't exist.
     *
     * Best-effort: one file failing to wipe doesn't stop the sweep over
     * the rest -- a Tier 3 wipe can't be paused, inspected, or retried
     * once the process dies moments later, so partial progress is always
     * better than aborting on the first failure.
     */
    fun wipeDirectoryRecursively(dir: File?): Int {
        if (dir == null || !dir.exists()) return 0
        var wiped = 0
        try {
            dir.walkBottomUp().forEach { entry ->
                if (entry == dir) return@forEach
                try {
                    if (entry.isFile) {
                        if (SecureFileWipe.secureDeleteFile(entry)) wiped++
                    } else if (entry.isDirectory) {
                        entry.delete() // now empty: walkBottomUp visits children first
                    }
                } catch (e: Exception) {
                    VeLog.w(TAG, e) { "wipeDirectoryRecursively: failed on one entry, continuing" }
                }
            }
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "wipeDirectoryRecursively: failed partway through ${dir.name}" }
        }
        return wiped
    }

    /**
     * Every internal-storage location the plan's Nuclear Wipe tier calls
     * out by name: `filesDir`, `cacheDir`, the databases directory, and
     * the shared_prefs directory (which subsumes [purgeCredentialStores]'s
     * targets, but that call still runs first in [PanicManager] so the
     * Keystore-backed decrypt keys for those files' *contents* are gone
     * before the raw bytes are, not after).
     */
    fun wipeAllInternalStorage(context: Context): Int {
        val dataDir = File(context.applicationInfo.dataDir)
        var total = 0
        total += wipeDirectoryRecursively(context.filesDir)
        total += wipeDirectoryRecursively(context.cacheDir)
        total += wipeDirectoryRecursively(File(dataDir, "databases"))
        total += wipeDirectoryRecursively(File(dataDir, "shared_prefs"))
        VeLog.i(TAG) { "wipeAllInternalStorage: wiped $total file(s)" }
        return total
    }
}
