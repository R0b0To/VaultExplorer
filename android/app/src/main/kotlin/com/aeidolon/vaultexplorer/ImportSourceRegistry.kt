package com.aeidolon.vaultexplorer

import android.net.Uri
import java.util.concurrent.ConcurrentHashMap
import com.aeidolon.vaultexplorer.bridge.ImportProgressBridge
import com.aeidolon.vaultexplorer.cancellation.ImportCancellation

/**
 * Remembers which on-device SAF documents were picked for a given import
 * operation (keyed by the same opId used by ImportCancellation /
 * ImportProgressBridge), so a later "delete the originals" request from
 * Dart knows what to remove.
 *
 * - File imports store each picked document Uri individually.
 * - Folder imports store the single picked tree Uri.
 *
 * Purely in-memory and process-lifetime. Entries are removed via take()
 * once consumed by handleDeleteImportSources, or overwritten if an opId
 * is ever reused.
 */
object ImportSourceRegistry {
    private data class Entry(
        val uris: List<Uri>,
        val isTree: Boolean,
        val verifiedForDeletion: Boolean = false,
    )
    private val sources = ConcurrentHashMap<Int, Entry>()

    fun recordFiles(opId: Int, uris: List<Uri>) {
        sources[opId] = Entry(uris, isTree = false)
    }

    fun recordFolder(opId: Int, treeUri: Uri) {
        sources[opId] = Entry(listOf(treeUri), isTree = true)
    }

    /** Allows source deletion only after import commit and readback checks succeed. */
    fun markVerifiedForDeletion(opId: Int) {
        sources.computeIfPresent(opId) { _, entry ->
            entry.copy(verifiedForDeletion = true)
        }
    }

    /** Removes a verified entry; unverified or unknown operations cannot delete sources. */
    fun takeForDeletion(opId: Int): Pair<List<Uri>, Boolean>? {
        val entry = sources[opId] ?: return null
        if (!entry.verifiedForDeletion) return null
        return take(opId)
    }

    /** Removes and returns any entry for [opId], or null if none/already consumed. */
    fun take(opId: Int): Pair<List<Uri>, Boolean>? {
        val entry = sources.remove(opId) ?: return null
        return entry.uris to entry.isTree
    }
}
