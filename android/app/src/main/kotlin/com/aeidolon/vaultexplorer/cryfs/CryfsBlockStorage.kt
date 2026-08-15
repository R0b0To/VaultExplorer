package com.aeidolon.vaultexplorer.cryfs

/**
 * The block-level operations [CryfsDataTree] needs from storage, extracted
 * as an interface (implemented by [CryfsBlockStore]) so the tree-rebuild
 * logic -- including the overwrite "publish" step, which a previous version
 * of this code got wrong in a way that silently corrupted data -- can be
 * exercised in a plain JVM unit test against an in-memory fake, without
 * needing a real `android.content.Context` or SAF access.
 */
interface CryfsBlockStorage {
    /** Whether blocks live on a directly-accessible local filesystem path
     *  (fast, supports true parallel I/O) rather than only through SAF
     *  (slower per-call, Binder-bound). */
    val isRaw: Boolean

    /** Loads and decrypts block [id]'s payload, or null if it doesn't exist
     *  or fails to authenticate. */
    fun load(id: CryfsBlockId): ByteArray?

    /** Encrypts and stores [payload] under block [id]. [isNewBlock] skips
     *  the read-modify-write version bump used for CryFS's integrity
     *  headers, since a brand-new id has no prior version to advance from. */
    fun store(id: CryfsBlockId, payload: ByteArray, isNewBlock: Boolean = false)

    /** Deletes block [id]. Returns whether a block was actually removed. */
    fun remove(id: CryfsBlockId): Boolean
}
