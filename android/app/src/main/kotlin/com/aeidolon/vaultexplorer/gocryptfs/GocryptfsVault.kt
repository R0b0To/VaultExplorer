package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import android.util.Base64
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom

object GocryptfsVault {
    private const val CONFIG_FILE_NAME = "gocryptfs.conf"
    private const val MASTERKEY_LEN = 32
    private const val SCRYPT_SALT_LEN = 32
    private const val DEFAULT_SCRYPT_LOG_N = 16
    private const val DEFAULT_SCRYPT_N = 1 shl DEFAULT_SCRYPT_LOG_N
    private const val DEFAULT_SCRYPT_R = 8
    private const val DEFAULT_SCRYPT_P = 1
    private const val CONFIG_VERSION = 2

    // Correctly dispatch the HKDF string depending on the cipher used for the content
    private fun hkdfInfoForContent(cipher: GocryptfsCipher): String = when (cipher) {
        GocryptfsCipher.AES_256_GCM -> "AES-GCM file content encryption"
        GocryptfsCipher.XCHACHA20_POLY1305 -> "XChaCha20-Poly1305 file content encryption"
    }

    fun looksLikeVault(context: Context, treeUri: Uri): Boolean {
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return false
        val saf = SafDocumentOps(context)
        return saf.childOf(root, CONFIG_FILE_NAME) != null
    }

    private fun readConfigBytes(context: Context, root: DocumentFile): ByteArray? {
        val saf = SafDocumentOps(context)
        val configDoc = saf.childOf(root, CONFIG_FILE_NAME) ?: return null
        return context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
    }

    fun open(context: Context, vaultRootUri: Uri, password: CharArray, readOnly: Boolean): com.aeidolon.vaultexplorer.engine.VaultOpenResult<GocryptfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val saf = SafDocumentOps(context)
        val configDoc = saf.childOf(root, CONFIG_FILE_NAME)
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

        val nameKey = if (config.plaintextNames) ByteArray(0) else Hkdf.deriveSha256(masterkey, "EME filename encryption", 32)
        val contentKey = Hkdf.deriveSha256(masterkey, hkdfInfoForContent(config.cipher), 32)
        masterkey.fill(0)

        val nameCryptor = GocryptfsFileNameCryptor(nameKey, config.longNameMax, config.plaintextNames)
        val contentCryptor = GocryptfsContentCryptor(contentKey, config.cipher)
        val tree = GocryptfsVaultTree(context, vaultRootUri, nameCryptor, hasDirIV = config.hasDirIV)
        
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

    fun create(
        context: Context,
        vaultRootUri: Uri,
        password: CharArray,
        cipher: GocryptfsCipher = GocryptfsCipher.AES_256_GCM,
        plaintextNames: Boolean = false,
    ): com.aeidolon.vaultexplorer.engine.VaultOpenResult<GocryptfsSession> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val saf = SafDocumentOps(context)
        if (saf.listChildren(root).isNotEmpty()) {
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

            val configJson = buildConfigJson(
                encryptedKey = encryptedKey,
                scryptSalt = scryptSalt,
                scryptN = DEFAULT_SCRYPT_N,
                scryptR = DEFAULT_SCRYPT_R,
                scryptP = DEFAULT_SCRYPT_P,
                longNameMax = 0,
                featureFlags = featureFlagsFor(cipher, plaintextNames),
            )

            val configDoc = root.createFile("application/octet-stream", CONFIG_FILE_NAME)
                ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not create gocryptfs.conf")
            
            context.contentResolver.openOutputStream(configDoc.uri, "wt")?.use {
                it.write(configJson.toByteArray(Charsets.UTF_8))
            } ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not write gocryptfs.conf")

            if (!plaintextNames) {
                val rootDiriv = ByteArray(16).also { random.nextBytes(it) }
                val dirivDoc = root.createFile("application/octet-stream", GocryptfsFileNameCryptor.DIRIV_FILENAME)
                    ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not create gocryptfs.diriv")
                context.contentResolver.openOutputStream(dirivDoc.uri, "wt")?.use { it.write(rootDiriv) }
                    ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not write gocryptfs.diriv")
            }

            val nameKey = if (plaintextNames) ByteArray(0) else Hkdf.deriveSha256(masterkey, "EME filename encryption", 32)
            val contentKey = Hkdf.deriveSha256(masterkey, hkdfInfoForContent(cipher), 32)

            val nameCryptor = GocryptfsFileNameCryptor(nameKey, 0, plaintextNames)
            val contentCryptor = GocryptfsContentCryptor(contentKey, cipher)
            val tree = GocryptfsVaultTree(context, vaultRootUri, nameCryptor, hasDirIV = !plaintextNames)

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

    private fun buildConfigJson(
        encryptedKey: ByteArray,
        scryptSalt: ByteArray,
        scryptN: Int,
        scryptR: Int,
        scryptP: Int,
        longNameMax: Int,
        featureFlags: List<String>,
    ): String {
        val scryptObject = JSONObject().apply {
            put("Salt", Base64.encodeToString(scryptSalt, Base64.NO_WRAP))
            put("N", scryptN)
            put("R", scryptR)
            put("P", scryptP)
            put("KeyLen", MASTERKEY_LEN)
        }

        val json = JSONObject().apply {
            put("Creator", "VaultExplorer")
            put("EncryptedKey", Base64.encodeToString(encryptedKey, Base64.NO_WRAP))
            put("ScryptObject", scryptObject)
            put("Version", CONFIG_VERSION)
            put("FeatureFlags", JSONArray(featureFlags))
            if (longNameMax > 0) put("LongNameMax", longNameMax)
        }
        return json.toString(2)
    }

    private fun featureFlagsFor(cipher: GocryptfsCipher, plaintextNames: Boolean): List<String> {
        val base = mutableListOf("HKDF")
        if (plaintextNames) {
            base.add("PlaintextNames")
        } else {
            base.addAll(listOf("Raw64", "DirIV", "EMENames", "LongNames"))
        }
        return when (cipher) {
            GocryptfsCipher.AES_256_GCM -> listOf("GCMIV128") + base
            GocryptfsCipher.XCHACHA20_POLY1305 -> listOf("XChaCha20Poly1305") + base
        }
    }

    fun changePassword(
        context: Context, vaultRootUri: Uri, oldPassword: CharArray, newPassword: CharArray,
    ): com.aeidolon.vaultexplorer.engine.VaultOpenResult<Unit> {
        val root = DocumentFile.fromTreeUri(context, vaultRootUri)
            ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Cannot access the selected folder.")
        val saf = SafDocumentOps(context)
        val configDoc = saf.childOf(root, CONFIG_FILE_NAME)
            ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("No gocryptfs.conf found — this doesn't look like a gocryptfs vault.")
        
        val configBytes = context.contentResolver.openInputStream(configDoc.uri)?.use { it.readBytes() }
            ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not read gocryptfs.conf")
        val config = try {
            GocryptfsConfig.parse(configBytes)
        } catch (e: GocryptfsConfigException) {
            return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault(e.message ?: "Malformed gocryptfs.conf")
        }

        val masterkey = try {
            GocryptfsMasterkey.unlock(config, oldPassword)
        } catch (e: GocryptfsWrongPasswordException) {
            return com.aeidolon.vaultexplorer.engine.VaultOpenResult.WrongPassword
        }

        return try {
            val random = SecureRandom()
            val newScryptSalt = ByteArray(SCRYPT_SALT_LEN).also { random.nextBytes(it) }
            val newEncryptedKey = GocryptfsMasterkey.wrap(
                masterkey = masterkey,
                password = newPassword,
                scryptSalt = newScryptSalt,
                scryptN = config.scryptN,
                scryptR = config.scryptR,
                scryptKeyLen = config.scryptKeyLen,
                random = random,
            )

            val newConfigJson = buildConfigJson(
                encryptedKey = newEncryptedKey,
                scryptSalt = newScryptSalt,
                scryptN = config.scryptN,
                scryptR = config.scryptR,
                scryptP = config.scryptP,
                longNameMax = config.longNameMax,
                featureFlags = config.featureFlags.toList(),
            )

            context.contentResolver.openOutputStream(configDoc.uri, "wt")?.use {
                it.write(newConfigJson.toByteArray(Charsets.UTF_8))
            } ?: return com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault("Could not write gocryptfs.conf")

            com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success(Unit, root.name ?: "Vault")
        } finally {
            masterkey.fill(0)
        }
    }
}