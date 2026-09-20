package com.aeidolon.vaultexplorer.camera

/**
 * A destination for a sequence of byte chunks written in order -- either
 * straight into a mounted vault ([VaultChunkWriter]) or into an
 * ephemeral-key-encrypted scratchpad file ([ScratchpadChunkWriter]),
 * transparently to the photo/video capture code in [VaultCameraSession].
 *
 * Introduced alongside the Quick Capture scratchpad flow so
 * `onJpegAvailable`/`VaultVideoRecorder.writeTo` don't need a second,
 * near-identical copy of themselves just to change where the bytes end
 * up.
 */
interface ChunkSink {
    fun write(data: ByteArray): Boolean

    /** Called exactly once after the last [write]. Default no-op for
     *  sinks (like [VaultChunkWriter]) that need no finalization step --
     *  [ScratchpadChunkWriter] overrides this to flush its AES-GCM
     *  authentication tag. */
    fun finish(): Boolean = true
}
