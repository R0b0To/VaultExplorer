package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import android.util.Base64
import androidx.documentfile.provider.DocumentFile
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom


/** Mirrors CryptomatorVault's role: looksLikeVault / open / create. */
object GocryptfsVault {
    private const val CONFIG_FILE_NAME = "gocryptfs.conf"

    // Real gocryptfs's own defaults (configfile.go): scryptDefaultLogN = 16
    // (N = 2^16 = 65536), r = 8, p = 1. p is written into gocryptfs.conf for
    // interop/record-keeping but — like the rest of this integration's
    // scrypt usage (see Scrypt.kt's own doc comment) — is never actually
    // read back or varied; Scrypt.scrypt() always computes with an implicit
    // p = 1. KeyLen/salt length both match cryptocore.KeyLen (32 bytes,
    // AES-256) — the same length gocryptfs itself uses for both its
    // masterkey-wrapping key and its scrypt salt.
    private const val MASTERKEY_LEN = 32
    private const val SCRYPT_SALT_LEN = 32
    private const val DEFAULT_SCRYPT_LOG_N = 16
    private const val DEFAULT_SCRYPT_N = 1 shl DEFAULT_SCRYPT_LOG_N
    private const val DEFAULT_SCRYPT_R = 8
    private const val DEFAULT_SCRYPT_P = 1
    private const val CONFIG_VERSION = 2

    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        return root.listFiles().any { it.name == CONFIG_FILE_NAME }
    }

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): com.aeidolon.vaultexplorer.engine.VaultOpenResult<GocryptfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val configDoc = root.listFiles().firstOrNull { it.name == CONFIG_FILE_NAME }
            ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("No gocryptfs.conf found — this doesn't look like a gocryptfs vault.")

        val configBytes = context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
            ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not read gocryptfs.conf")

        val config = try {
            GocryptfsConfig.parse(configBytes)
        } catch (e: GocryptfsConfigException) {
            return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault(e.message ?: "Malformed gocryptfs.conf")
        }

        val masterkey = try {
            GocryptfsMasterkey.unlock(config, password)
        } catch (e: GocryptfsWrongPasswordException) {
            return com.aeidolon.vaultexplorer.engine.VaultOpenResult.WrongPassword
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
        return com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success(session, root.name ?: "Vault")
    }

    /**
     * Creates a brand-new vault: fresh scrypt salt + random masterkey,
     * gocryptfs.conf with our supported flag set (see [GocryptfsConfig]'s
     * SUPPORTED_FLAGS), and a root gocryptfs.diriv. Returns an already-open
     * [com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success] (mirroring [CryptomatorVault.create]) —
     * MainActivity's CREATE_GOCRYPTFS_VAULT handler immediately closes that
     * session and reports success/failure to Dart; the vault is left locked
     * on disk and must be unlocked explicitly afterward via [open], same as
     * every other container/vault format this app creates.
     *
     * Field names/casing in the written JSON match real gocryptfs's own
     * config file schema (Creator/EncryptedKey/ScryptObject{Salt,N,R,P,
     * KeyLen}/Version/FeatureFlags), so a vault created here should also be
     * openable by a real `gocryptfs` binary — not just by this app.
     */
    fun create(context: Context, vaultRootUri: Uri, password: CharArray): com.aeidolon.vaultexplorer.engine.VaultOpenResult<GocryptfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Cannot access the selected folder.")

        if (root.listFiles().isNotEmpty()) {
            return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Selected folder is not empty.")
        }

        val random = SecureRandom()
        val masterkey = ByteArray(MASTERKEY_LEN).also { random.nextBytes(it) }

        return try {
            val scryptSalt = ByteArray(SCRYPT_SALT_LEN).also { random.nextBytes(it) }
            val encryptedKey = GocryptfsMasterkey.wrap(
                masterkey = masterkey,
                password = password,
                scryptSalt = scryptSalt,
                scryptN = DEFAULT_SCRYPT_N,
                scryptR = DEFAULT_SCRYPT_R,
                scryptKeyLen = MASTERKEY_LEN,
                random = random,
            )

            val configJson = buildConfigJson(encryptedKey, scryptSalt)
            val configDoc = root.createFile("application/octet-stream", CONFIG_FILE_NAME)
                ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not create gocryptfs.conf")
            context.contentResolver.openOutputStream(configDoc.uri, "wt")?.use {
                it.write(configJson.toByteArray(Charsets.UTF_8))
            } ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not write gocryptfs.conf")

            // Root directory's diriv. GocryptfsVaultTree.dirivFor() would
            // otherwise create this lazily on first write, but writing it
            // eagerly here means a freshly-created vault is immediately a
            // valid (if empty) listable root, matching what
            // CryptomatorVault.create() does for its own root data
            // directory.
            val rootDiriv = ByteArray(16).also { random.nextBytes(it) }
            val dirivDoc = root.createFile("application/octet-stream", GocryptfsFileNameCryptor.DIRIV_FILENAME)
                ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not create gocryptfs.diriv")
            context.contentResolver.openOutputStream(dirivDoc.uri, "wt")?.use { it.write(rootDiriv) }
                ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not write gocryptfs.diriv")

            // Build the session directly from the masterkey already in
            // memory — the exact same derivation [open] performs — instead
            // of re-reading and re-decrypting what was just written.
            val nameKey = Hkdf.deriveSha256(masterkey, "EME filename encryption", 32)
            val contentKey = Hkdf.deriveSha256(masterkey, "AES-GCM file content encryption", 32)

            val nameCryptor = GocryptfsFileNameCryptor(nameKey, 0)
            val contentCryptor = GocryptfsContentCryptor(contentKey)
            val tree = GocryptfsVaultTree(context, vaultRootUri, nameCryptor)

            val session = GocryptfsSession(
                context = context,
                vaultRootUri = vaultRootUri,
                nameCryptor = nameCryptor,
                contentCryptor = contentCryptor,
                tree = tree,
                readOnly = false,
            )
            com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success(session, root.name ?: "Vault")
        } catch (e: Exception) {
            com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Vault creation failed: ${e.message}")
        } finally {
            masterkey.fill(0)
        }
    }

    private fun buildConfigJson(encryptedKey: ByteArray, scryptSalt: ByteArray): String {
        val scryptObject = JSONObject().apply {
            put("Salt", Base64.encodeToString(scryptSalt, Base64.NO_WRAP))
            put("N", DEFAULT_SCRYPT_N)
            put("R", DEFAULT_SCRYPT_R)
            put("P", DEFAULT_SCRYPT_P)
            put("KeyLen", MASTERKEY_LEN)
        }
        val json = JSONObject().apply {
            put("Creator", "VaultExplorer")
            put("EncryptedKey", Base64.encodeToString(encryptedKey, Base64.NO_WRAP))
            put("ScryptObject", scryptObject)
            put("Version", CONFIG_VERSION)
            put(
                "FeatureFlags",
                JSONArray(listOf("GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF")),
            )
        }
        return json.toString(2)
    }
}
