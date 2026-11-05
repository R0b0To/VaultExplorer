package com.aeidolon.vaultexplorer.foldervault

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.RawFileResolver
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.engine.VaultIOException
import com.aeidolon.vaultexplorer.engine.VaultOpenResult
import com.aeidolon.vaultexplorer.saf.MirrorSyncCoordinator
import com.aeidolon.vaultexplorer.saf.MirroredSafDocumentOps
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import java.io.File
import java.nio.CharBuffer
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

/**
 * Open / create / change-password for the three folder-vault formats. This is
 * the Android policy that used to be copy-pasted into GocryptfsVault,
 * CryptomatorVault and CryfsVault: pick between the verified raw path and the
 * SAF mirror, hand the password to the native core as UTF-8 bytes, and turn
 * the result into a [VaultOpenResult]. The formats themselves live in
 * cpp/foldervault.
 */
internal object FolderVaultOpener {
    private const val TAG = "FolderVaultOpener"
    private const val UNAVAILABLE = "The native vault engine is not available on this device."

    private fun utf8(chars: CharArray): ByteArray {
        val buf = Charsets.UTF_8.encode(CharBuffer.wrap(chars))
        val out = ByteArray(buf.remaining())
        buf.get(out)
        if (buf.hasArray()) buf.array().fill(0)
        return out
    }

    private fun localStateDir(context: Context): String = File(context.filesDir, "cryfs_localstate").absolutePath
    private fun tempDir(context: Context): String = context.cacheDir.absolutePath

    private fun message(out: Array<Any?>, fallback: String): String = (out[0] as? String)?.takeIf { it.isNotEmpty() } ?: fallback

    /** Storage for the pre-unlock step (reading the config) when there is no verified raw path. */
    private fun safBootstrap(context: Context, root: DocumentFile, uri: Uri): FolderVaultStorage =
        SafFolderVaultStorage(context, root, SafDocumentOps(context, allowRaw = false), null, uri)

    private fun newMirror(context: Context, uri: Uri): MirrorSyncCoordinator {
        val realOps = SafDocumentOps(context, allowRaw = false)
        return MirrorSyncCoordinator(context = context, sessionTag = UUID.randomUUID().toString(), realOps = realOps).also { coordinator ->
            try {
                val realRoot = DocumentFile.fromTreeUri(context, uri) ?: run {
                    val msg = "Cannot open vault root: $uri"
                    VeLog.e(TAG) { msg }
                    throw VaultIOException(msg)
                }
                coordinator.reset(realRoot)
            } catch (e: Exception) {
                runCatching { coordinator.teardown() }
                throw e
            }
        }
    }

    /** What a session runs on when the vault folder is only reachable through SAF: the local mirror. */
    private fun mirrorStorage(context: Context, uri: Uri, format: Int, volRef: AtomicInteger): FolderVaultStorage {
        val coordinator = newMirror(context, uri)
        try {
            val mirroredOps = MirroredSafDocumentOps(context, coordinator)
            if (format == NativeFolderVault.CRYFS) {
                val realRoot = DocumentFile.fromTreeUri(context, uri) ?: throw VaultIOException("Cannot open vault root: $uri")
                val mirrorDir = RawFileResolver.getRawFile(context, mirroredOps.root)
                    ?: throw VaultIOException("Mirror directory is not reachable as a file")
                return CryfsMirrorFolderVaultStorage(context, realRoot, coordinator, mirrorDir, uri)
            }
            return SafFolderVaultStorage(context, mirroredOps.root, mirroredOps, coordinator, uri) { volRef.get() }
        } catch (e: Exception) {
            runCatching { coordinator.teardown() }
            throw e
        }
    }

    fun <S : NativeVaultSession> open(
        context: Context,
        vaultRootUri: Uri,
        format: Int,
        sentinel: String,
        password: CharArray?,
        combinedKey: ByteArray?,
        readOnly: Boolean,
        // Raw credential bytes (gocryptfs security-key vaults: the hmac-secret output). Handed to the core
        // as-is -- never through the UTF-8 step [password] gets. The caller keeps ownership; this copies it.
        rawSecret: ByteArray? = null,
        makeSession: (handle: Long, volRef: AtomicInteger) -> S,
    ): VaultOpenResult<S> {
        if (!NativeFolderVault.isAvailable) return VaultOpenResult.InvalidVault(UNAVAILABLE)
        val root = DocumentFile.fromTreeUri(context, vaultRootUri) ?: run {
            VeLog.e(TAG) { "open failed: Cannot access folder URI $vaultRootUri" }
            return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        }
        val rawRoot: File? = RawFileResolver.getVerifiedRawVaultRoot(context, vaultRootUri, sentinel, probeWrite = !readOnly)
        val volRef = AtomicInteger(-1)
        val bootstrap = if (rawRoot == null) safBootstrap(context, root, vaultRootUri) else null
        val provider = if (rawRoot == null) object : FolderVaultSessionProvider {
            // Only built once the password is known to be right: the mirror is expensive.
            override fun buildSessionStorage(): FolderVaultStorage = mirrorStorage(context, vaultRootUri, format, volRef)
        } else null

        val pw = rawSecret?.copyOf() ?: password?.let { utf8(it) } ?: ByteArray(0)
        val out = arrayOfNulls<Any?>(2)
        try {
            val handle = try {
                NativeFolderVault.nativeOpen(
                    format, rawRoot?.absolutePath, bootstrap, provider, pw, readOnly,
                    localStateDir(context), tempDir(context), combinedKey, out,
                )
            } catch (e: Throwable) {
                VeLog.e(TAG, e) { "native open crashed" }
                return VaultOpenResult.InvalidVault("Could not open vault: ${e.message}")
            }
            return when {
                handle > 0L -> {
                    val session = makeSession(handle, volRef)
                    VaultOpenResult.Success(session, root.name ?: "Vault", out[1] as? ByteArray)
                }
                handle < 0L -> VaultOpenResult.WrongPassword
                else -> {
                    val msg = message(out, "Could not open vault.")
                    VeLog.e(TAG) { "open failed: $msg" }
                    VaultOpenResult.InvalidVault(msg)
                }
            }
        } finally {
            pw.fill(0)
            bootstrap?.close()
        }
    }

    /**
     * Writes the vault skeleton, then unlocks it normally -- the storage a session
     * should use depends on what is on disk after creation (raw access is probed
     * against the new config file), so creation and unlocking are separate steps.
     */
    fun <S : NativeVaultSession> create(
        context: Context,
        vaultRootUri: Uri,
        format: Int,
        sentinel: String,
        password: CharArray,
        options: IntArray,
        cipherName: String?,
        userEntropy: ByteArray?,
        // gocryptfs security-key vault: [rawSecret] replaces [password] (raw bytes, caller keeps
        // ownership) and [fido2Json] is the FIDO2 section recorded in the config.
        rawSecret: ByteArray? = null,
        fido2Json: String? = null,
        makeSession: (handle: Long, volRef: AtomicInteger) -> S,
    ): VaultOpenResult<S> {
        if (!NativeFolderVault.isAvailable) return VaultOpenResult.InvalidVault(UNAVAILABLE)
        val root = DocumentFile.fromTreeUri(context, vaultRootUri) ?: run {
            VeLog.e(TAG) { "create failed: Cannot access folder URI $vaultRootUri" }
            return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        }
        val storage = safBootstrap(context, root, vaultRootUri)
        val pw = rawSecret?.copyOf() ?: utf8(password)
        val out = arrayOfNulls<Any?>(2)
        val status = try {
            NativeFolderVault.nativeCreate(
                format, null, storage, pw, options, cipherName, localStateDir(context), tempDir(context), userEntropy,
                fido2Json, out,
            )
        } catch (e: Throwable) {
            VeLog.e(TAG, e) { "native create crashed" }
            pw.fill(0)
            return VaultOpenResult.InvalidVault("Failed to create vault: ${e.message}")
        } finally {
            storage.close()
        }
        pw.fill(0)
        if (status != NativeFolderVault.STATUS_OK) {
            val msg = message(out, "Failed to create vault.")
            VeLog.e(TAG) { "create failed: $msg" }
            return VaultOpenResult.InvalidVault(msg)
        }
        return if (rawSecret != null) {
            open(context, vaultRootUri, format, sentinel, null, null, false, rawSecret, makeSession)
        } else {
            open(context, vaultRootUri, format, sentinel, password, null, false, makeSession = makeSession)
        }
    }

    fun changePassword(
        context: Context,
        vaultRootUri: Uri,
        format: Int,
        sentinel: String,
        oldPassword: CharArray,
        newPassword: CharArray,
    ): VaultOpenResult<Unit> {
        if (!NativeFolderVault.isAvailable) return VaultOpenResult.InvalidVault(UNAVAILABLE)
        val root = DocumentFile.fromTreeUri(context, vaultRootUri) ?: return VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val rawRoot = RawFileResolver.getVerifiedRawVaultRoot(context, vaultRootUri, sentinel, probeWrite = true)
        val storage = if (rawRoot == null) safBootstrap(context, root, vaultRootUri) else null
        val oldBytes = utf8(oldPassword)
        val newBytes = utf8(newPassword)
        val out = arrayOfNulls<Any?>(2)
        try {
            val status = try {
                NativeFolderVault.nativeChangePassword(format, rawRoot?.absolutePath, storage, oldBytes, newBytes, out)
            } catch (e: Throwable) {
                VeLog.e(TAG, e) { "native changePassword crashed" }
                return VaultOpenResult.InvalidVault("Failed to change password: ${e.message}")
            }
            return when (status) {
                NativeFolderVault.STATUS_OK -> VaultOpenResult.Success(Unit, root.name ?: "Vault")
                NativeFolderVault.STATUS_WRONG_PASSWORD -> VaultOpenResult.WrongPassword
                else -> VaultOpenResult.InvalidVault(message(out, "Failed to change password."))
            }
        } finally {
            oldBytes.fill(0)
            newBytes.fill(0)
            storage?.close()
        }
    }
}
