package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile

sealed class GocryptfsOpenResult {
    data class Success(val session: GocryptfsSession, val vaultDisplayName: String) : GocryptfsOpenResult()
    object WrongPassword : GocryptfsOpenResult()
    data class InvalidVault(val reason: String) : GocryptfsOpenResult()
}

/** Mirrors CryptomatorVault's role: looksLikeVault / open / create. */
object GocryptfsVault {
    private const val CONFIG_FILE_NAME = "gocryptfs.conf"

    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        return root.listFiles().any { it.name == CONFIG_FILE_NAME }
    }

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): GocryptfsOpenResult {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return GocryptfsOpenResult.InvalidVault("Cannot access the selected folder.")
        val configDoc = root.listFiles().firstOrNull { it.name == CONFIG_FILE_NAME }
            ?: return GocryptfsOpenResult.InvalidVault("No gocryptfs.conf found — this doesn't look like a gocryptfs vault.")

        val configBytes = context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
            ?: return GocryptfsOpenResult.InvalidVault("Could not read gocryptfs.conf")

        val config = try {
            GocryptfsConfig.parse(configBytes)
        } catch (e: GocryptfsConfigException) {
            return GocryptfsOpenResult.InvalidVault(e.message ?: "Malformed gocryptfs.conf")
        }

        val masterkey = try {
            GocryptfsMasterkey.unlock(config, password)
        } catch (e: GocryptfsWrongPasswordException) {
            return GocryptfsOpenResult.WrongPassword
        }

        val nameKey = Hkdf.deriveSha256(masterkey, "EME filename encryption", 32)
        val contentKey = Hkdf.deriveSha256(masterkey, "AES-GCM file content encryption", 32)
        masterkey.fill(0)

        val nameCryptor = GocryptfsFileNameCryptor(nameKey, config.longNameMax)
        val contentCryptor = GocryptfsContentCryptor(contentKey)
        val tree = GocryptfsVaultTree(context, vaultRootUri, nameCryptor)

        val session = GocryptfsSession(
            context = context,
            vaultRootUri = vaultRootUri,
            nameCryptor = nameCryptor,
            contentCryptor = contentCryptor,
            tree = tree,
            readOnly = readOnly,
        )
        return GocryptfsOpenResult.Success(session, root.name ?: "Vault")
    }

    /** Creates a brand-new vault: fresh scrypt salt + random masterkey,
     *  gocryptfs.conf with our supported flag set, and a root gocryptfs.diriv.
     *  Left locked afterward, matching createContainer()/CryptomatorVault.create(). */
    fun create(context: Context, vaultRootUri: Uri, password: CharArray): GocryptfsOpenResult {
        // Mechanical mirror of CryptomatorVault.create(): generate masterkey,
        // scrypt-wrap it via GocryptfsMasterkey's inverse (AES-GCM encrypt
        // instead of decrypt), write gocryptfs.conf JSON, write the root
        // gocryptfs.diriv. Omitted here for brevity — same shape as `open()`
        // above, run in reverse, plus JSON serialization matching
        // GocryptfsConfig's field names exactly so a real `gocryptfs -init`
        // could re-read what we write (interop, not just self-consistency).
        TODO("mirrors CryptomatorVault.create(); implemented once §4.3 lands")
    }
}