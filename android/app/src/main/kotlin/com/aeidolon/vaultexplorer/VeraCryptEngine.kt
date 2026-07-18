package com.aeidolon.vaultexplorer

/**
 * ABI-compatibility JNI shim for the original native export names.
 *
 * App code must use [ContainerEngine]. This object stays format-specific only
 * because the C++ library still exports statically named JNI symbols; keeping
 * that constraint isolated here lets the public API evolve independently.
 *
 * The native API is split into two clear tiers:
 *
 *   1. Session-establishment calls — take a real fd + password + pim because
 *      they are creating the crypto session from scratch.
 *
 *   2. Stateless calls — take volId only; the C++ side asserts an active
 *      session exists via requireActiveSession() and throws
 *      IllegalStateException("NOT_UNLOCKED: ...") if it doesn't.
 *
 */
internal object VeraCryptEngine {
    init {
        System.loadLibrary("vaultexplorer")
    }

    // ── Config ───────────────────────────────────────────────────────────

    @JvmStatic
    external fun getMaxVolumesNative(): Int

    // ── Tier 1: session establishment ──────────────────────────────────────

    /** Opens fd, runs PBKDF2, mounts the FAT layer, returns root listing.
     *  cipherId/hashId: 255 = auto-detect (try all combinations).
     *  keyfileFds: raw fds (already ParcelFileDescriptor.detachFd()'d on the
     *  Kotlin side) for any keyfiles to mix into the password before
     *  derivation. The native side takes ownership and closes every fd in
     *  this array, whether derivation succeeds or fails — callers must not
     *  touch or close them again afterward. Pass null/empty for no keyfiles. */
    @JvmStatic
    external fun deriveKeyMaterialNative(
        fd: Int, password: String, pim: Int,
        cipherId: Int = 255, hashId: Int = 255, keyfileFds: IntArray? = null
    ): ByteArray?

    @JvmStatic
    external fun getLastDerivedKeyMaterialNative(volId: Int): ByteArray?

    /** keyfileFds: see [deriveKeyMaterialNative] — same detach/ownership contract. */
    @JvmStatic
    external fun unlockAndListNative(
        fd: Int, password: String, pim: Int, volId: Int,
        cipherId: Int = 255, hashId: Int = 255, preservedKey: ByteArray? = null,
        keyfileFds: IntArray? = null
    ): Array<String>?

    /** Writes a new container to fd and formats it.
     *
     *  containerFormat: 0 = VeraCrypt, 1 = LUKS1, 2 = LUKS2 (matches
     *  ContainerFormat's native ordinal, see container_format.h).
     *
     *  cipherId/hashId: for VeraCrypt (containerFormat==0), 255 = auto
     *  (defaults to AES + SHA-512). For LUKS (containerFormat==1 or 2),
     *  both must be concrete — creation always knows exactly which
     *  algorithm it's using — restricted to AES(0)/Serpent(1)/Twofish(2)
     *  for cipherId (LUKS1 additionally requires AES specifically) and
     *  SHA-512(0)/SHA-256(1)/Argon2id(5) for hashId (Argon2id only valid
     *  for LUKS2).
     *
     *  keyfileFds: see [deriveKeyMaterialNative] for the fd ownership
     *  contract. For VeraCrypt, keyfiles mix additively into the typed
     *  password (including allowing an empty password when keyfiles alone
     *  are supplied). For LUKS, a keyfile REPLACES the typed password
     *  entirely — matching real `cryptsetup --key-file` — and only the
     *  first keyfile is used. */
    @JvmStatic
    external fun createContainerNative(
        fd: Int, password: String, pim: Int, sizeBytes: Long, fileSystem: String,
        containerFormat: Int = 0, cipherId: Int = 255, hashId: Int = 255,
        keyfileFds: IntArray? = null
    ): Boolean

    /** Creates a VeraCrypt container with an embedded hidden volume.
     *  The outer volume is created first, then the hidden volume's header
     *  is written at offset 65536 and the hidden data area at the end of
     *  the container is zero-encrypted with its own independent master key.
     *  keyfileFds / hiddenKeyfileFds: same detach/ownership contract. */
    @JvmStatic
    external fun createContainerWithHiddenNative(
        fd: Int, outerPassword: String, hiddenPassword: String,
        outerPim: Int, hiddenPim: Int, sizeBytes: Long,
        outerFileSystem: String, hiddenFileSystem: String,
        hiddenSizeBytes: Long,
        outerCipherId: Int = 255, outerHashId: Int = 255,
        hiddenCipherId: Int = 255, hiddenHashId: Int = 255,
        outerKeyfileFds: IntArray? = null, hiddenKeyfileFds: IntArray? = null
    ): Boolean

    /** Re-encrypts a VeraCrypt container's header with a new password.
     *  Decrypts the header with [oldPassword]/[oldPim], re-derives the
     *  header key from [newPassword]/[newPim] with a fresh random salt,
     *  then writes the re-encrypted header (primary + backup).
     *  Always takes ownership of [fd]. */
    @JvmStatic
    external fun changeContainerPasswordNative(
        fd: Int, oldPassword: String, newPassword: String,
        oldPim: Int, newPim: Int,
        cipherId: Int = 255, hashId: Int = 255,
        oldKeyfileFds: IntArray? = null, newKeyfileFds: IntArray? = null
    ): Boolean

    /** PBKDF2-SHA512 via mbedTLS; no volId, no session required. */
    @JvmStatic
    external fun hashPasswordNative(
        password: String, salt: ByteArray, iterations: Int
    ): ByteArray?

    // ── Session teardown ───────────────────────────────────────────────────

    @JvmStatic
    external fun lockNative(volId: Int)

    /** Best-effort: asks an in-flight unlockAndListNative/unlockUsbAndListNative
     *  call for [volId] to abort at its next hash/cipher combination boundary
     *  (not instant — bounded by roughly one PBKDF2 round). Safe to call even
     *  if nothing is currently unlocking for [volId]. See UnlockCancelledException. */
    @JvmStatic
    external fun requestCancelUnlockNative(volId: Int)

    // ── Tier 2: stateless file operations (volId-only) ─────────────────────

    // ── Matched cipher/hash lookup (perf: skip auto-detect next unlock) ────
    @JvmStatic external fun getMatchedCipherId(volId: Int): Int
    @JvmStatic external fun getMatchedHashId(volId: Int): Int
    @JvmStatic external fun getContainerFormat(volId: Int): Int
    @JvmStatic external fun listDirectory(dirPath: String, volId: Int): Array<String>?
    @JvmStatic external fun getFileSize(fileName: String, volId: Int): Long
    @JvmStatic external fun getFolderSize(dirPath: String, volId: Int): Long
    @JvmStatic external fun readFileChunk(fileName: String, offset: Long, length: Int, volId: Int): ByteArray?
    @JvmStatic external fun writeFileChunk(fileName: String, offset: Long, data: ByteArray, volId: Int): Boolean
    @JvmStatic external fun writeBackFile(targetFileName: String, sourcePath: String, volId: Int): Boolean
    @JvmStatic external fun extractFile(targetFileName: String, destPath: String, volId: Int): Boolean
    @JvmStatic external fun deleteFile(targetFileName: String, volId: Int): Boolean
    @JvmStatic external fun createDirectory(dirPath: String, volId: Int): Boolean
    @JvmStatic external fun renameFile(oldPath: String, newPath: String, volId: Int): Boolean
    @JvmStatic external fun setLastModifiedTime(path: String, epochSeconds: Long, volId: Int): Boolean
    @JvmStatic external fun getSpaceInfo(volId: Int): LongArray?
    /** USB unlock + list. cipherId/hashId: 255 = auto-detect.
     *  keyfileFds: see [deriveKeyMaterialNative] — same detach/ownership contract. */
    @JvmStatic external fun unlockUsbAndListNative(
        password: String, pim: Int, volId: Int, deviceSizeBytes: Long,
        cipherId: Int = 255, hashId: Int = 255, preservedKey: ByteArray? = null,
        partitionOffsetHint: Long = -1L, keyfileFds: IntArray? = null
    ): Array<String>?

    /** Creates a new container directly on a raw (unformatted) USB block device.
 *  [volId] must already have a UsbMassStorageDevice registered in
 *  UsbBlockBridge (MainActivity does this before calling). Writes an MBR
 *  partition table via writeMbrPartitionTable() then formats the container
 *  starting at that partition. See createContainerNative for the
 *  cipherId/hashId/keyfileFds semantics — identical here. */
@JvmStatic
external fun createUsbContainerNative(
    volId: Int, partitionScheme: String, password: String, pim: Int, sizeBytes: Long, fileSystem: String,
    containerFormat: Int = 0, cipherId: Int = 255, hashId: Int = 255,
    keyfileFds: IntArray? = null, quickFormat: Boolean = false
): Boolean

@JvmStatic
    external fun createUsbContainerWithHiddenNative(
        volId: Int, partitionScheme: String,
        outerPassword: String, hiddenPassword: String,
        outerPim: Int, hiddenPim: Int, sizeBytes: Long,
        outerFileSystem: String, hiddenFileSystem: String,
        hiddenSizeBytes: Long,
        outerCipherId: Int = 255, outerHashId: Int = 255,
        hiddenCipherId: Int = 255, hiddenHashId: Int = 255,
        outerKeyfileFds: IntArray? = null, hiddenKeyfileFds: IntArray? = null,
        quickFormat: Boolean = false
    ): Boolean

    // ── Tier 2: stream lifecycle ───────────────────────────────────────────
    // Used exclusively by VeraCryptProxyCallback. Passes a raw C++ FIL*
    // as a Long — kept separate from the one-shot stateless methods above
    // because the pointer lifetime is tied to the ProxyFileDescriptor callback.

    @JvmStatic external fun openStream(targetFileName: String, volId: Int): Long
    @JvmStatic external fun readStream(streamPtr: Long, offset: Long, outBuffer: ByteArray, length: Int, volId: Int): Int
    @JvmStatic external fun closeStream(streamPtr: Long, volId: Int)
    @JvmStatic external fun getCascadeFingerprint(cascadeId: Int): Int
    @JvmStatic external fun getCascadeIdCount(): Int
    @JvmStatic external fun getHashIdCount(): Int
    
}