package com.aeidolon.vaultexplorer.camera

import com.aeidolon.vaultexplorer.bridge.ImportProgressBridge
import com.aeidolon.vaultexplorer.cancellation.ImportCancellation

/**
 * Wraps another [ChunkSink] for a save that is tracked as a FileOperation on
 * the Dart side (see `opId` in VaultCameraPlugin's `saveVideoToVault`):
 * reports the bytes written through [ImportProgressBridge], so the transfer
 * button, sheet and notification show real progress, and stops at the next
 * chunk once the user cancels the operation ([ImportCancellation]).
 *
 * [cancelled] tells the caller why a write ended early, since a cancelled
 * save and a failed one both surface as `write() == false`.
 */
class TrackedChunkSink(
    private val inner: ChunkSink,
    private val opId: Int,
) : ChunkSink {
    @Volatile
    var cancelled: Boolean = false
        private set

    override fun write(data: ByteArray): Boolean {
        if (ImportCancellation.isCancelled(opId)) {
            cancelled = true
            return false
        }
        val ok = inner.write(data)
        if (ok) ImportProgressBridge.reportChunk(opId, data.size.toLong())
        return ok
    }

    override fun finish(): Boolean = inner.finish()
}
