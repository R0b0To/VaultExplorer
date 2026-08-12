package com.aeidolon.vaultexplorer.gocryptfs

import java.security.SecureRandom
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assume
import org.junit.Before
import org.junit.Test
import java.util.Base64

class GocryptfsMasterkeyTest {
    private val random = SecureRandom()
    private val testScryptN = 16
    private val testScryptR = 8
    private val testScryptKeyLen = 32

    private fun freshMasterkey(): ByteArray = ByteArray(testScryptKeyLen).also { random.nextBytes(it) }

    @Before
    fun setUp() {
        // 1. Check if we are running on a real device/emulator with the native C++ library loaded
        val isNativeAvailable = try {
            com.aeidolon.vaultexplorer.NativeEngine.getCascadeIdCount()
            true
        } catch (e: UnsatisfiedLinkError) {
            false
        } catch (e: NoClassDefFoundError) {
            false
        } catch (e: ExceptionInInitializerError) {
            false
        }
        Assume.assumeTrue("Skipping test: Native C++ library not available on this host JVM", isNativeAvailable)

        // 2. Check if we are running in an environment where Android's JSONObject is fully mocked/implemented
        val isJsonAvailable = try {
            JSONObject().put("test", 1)
            true
        } catch (e: RuntimeException) {
            false // Throws "Method put in org.json.JSONObject not mocked" on local JVM
        } catch (e: NoClassDefFoundError) {
            false
        }
        Assume.assumeTrue("Skipping test: Android JSON framework not available on this host JVM", isJsonAvailable)
    }

    @Test
    fun `wrap then unlock recovers the same masterkey bytes`() {
        val masterkey = freshMasterkey()
        val password = "correct horse battery staple".toCharArray()
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val encryptedKey = GocryptfsMasterkey.wrap(masterkey, password, salt, testScryptN, testScryptR, testScryptKeyLen, random)
        
        val config = GocryptfsConfig(
            encryptedKey = encryptedKey,
            scryptSalt = salt,
            scryptN = testScryptN,
            scryptR = testScryptR,
            scryptP = 1,
            scryptKeyLen = testScryptKeyLen,
            version = 2,
            featureFlags = setOf("GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF"),
            longNameMax = 0,
            cipher = GocryptfsCipher.AES_256_GCM,
            plaintextNames = false,
        )
        val unlocked = GocryptfsMasterkey.unlock(config, password)
        assertArrayEquals(masterkey, unlocked)
    }

    @Test
    fun `wrong password is rejected`() {
        val masterkey = freshMasterkey()
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val encryptedKey = GocryptfsMasterkey.wrap(masterkey, "right password".toCharArray(), salt, testScryptN, testScryptR, testScryptKeyLen, random)
        
        val config = GocryptfsConfig(
            encryptedKey, salt, testScryptN, testScryptR, 1, testScryptKeyLen, 2,
            setOf("GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF"), 0, GocryptfsCipher.AES_256_GCM, false
        )
        assertThrows(GocryptfsWrongPasswordException::class.java) {
            GocryptfsMasterkey.unlock(config, "wrong password".toCharArray())
        }
    }

    @Test
    fun `changing password preserves the masterkey but rotates salt and wrapping`() {
        val masterkey = freshMasterkey()
        val oldSalt = ByteArray(16).also { random.nextBytes(it) }
        val oldPassword = "old password".toCharArray()
        val newPassword = "new password".toCharArray()
        val flags = setOf("GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF")

        val oldEncryptedKey = GocryptfsMasterkey.wrap(masterkey, oldPassword, oldSalt, testScryptN, testScryptR, testScryptKeyLen, random)
        val oldConfig = GocryptfsConfig(oldEncryptedKey, oldSalt, testScryptN, testScryptR, 1, testScryptKeyLen, 2, flags, 0, GocryptfsCipher.AES_256_GCM, false)
        val unlocked = GocryptfsMasterkey.unlock(oldConfig, oldPassword)

        val newSalt = ByteArray(16).also { random.nextBytes(it) }
        val newEncryptedKey = GocryptfsMasterkey.wrap(unlocked, newPassword, newSalt, oldConfig.scryptN, oldConfig.scryptR, oldConfig.scryptKeyLen, random)
        val newConfig = GocryptfsConfig(newEncryptedKey, newSalt, oldConfig.scryptN, oldConfig.scryptR, oldConfig.scryptP, oldConfig.scryptKeyLen, oldConfig.version, flags, 0, GocryptfsCipher.AES_256_GCM, false)

        val reunlocked = GocryptfsMasterkey.unlock(newConfig, newPassword)

        assertArrayEquals(masterkey, reunlocked)
        assertThrows(GocryptfsWrongPasswordException::class.java) {
            GocryptfsMasterkey.unlock(newConfig, oldPassword)
        }
        assertFalse(oldSalt.contentEquals(newSalt))
        assertFalse(oldEncryptedKey.contentEquals(newEncryptedKey))
    }

    @Test
    fun `GocryptfsConfig parse round-trips a hand-built gocryptfs conf`() {
        val masterkey = freshMasterkey()
        val password = "hunter2".toCharArray()
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val encryptedKey = GocryptfsMasterkey.wrap(masterkey, password, salt, testScryptN, testScryptR, testScryptKeyLen, random)

        val scryptObject = JSONObject().apply {
            put("Salt", Base64.getEncoder().encodeToString(salt))
            put("N", testScryptN)
            put("R", testScryptR)
            put("P", 1)
            put("KeyLen", testScryptKeyLen)
        }
        val json = JSONObject().apply {
            put("Creator", "VaultExplorer")
            put("EncryptedKey", Base64.getEncoder().encodeToString(encryptedKey))
            put("ScryptObject", scryptObject)
            put("Version", 2)
            put("FeatureFlags", JSONArray(listOf("GCMIV128", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF")))
        }

        val parsed = GocryptfsConfig.parse(json.toString().toByteArray(Charsets.UTF_8))
        assertEquals(testScryptN, parsed.scryptN)
        assertArrayEquals(salt, parsed.scryptSalt)
        assertArrayEquals(masterkey, GocryptfsMasterkey.unlock(parsed, password))
    }

    @Test
    fun `legacy vault without DirIV or GCMIV128 is accepted (deterministic names, AES-GCM)`() {
        val masterkey = freshMasterkey()
        val password = "hunter2".toCharArray()
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val encryptedKey = GocryptfsMasterkey.wrap(masterkey, password, salt, testScryptN, testScryptR, testScryptKeyLen, random)

        val json = JSONObject().apply {
            put("EncryptedKey", Base64.getEncoder().encodeToString(encryptedKey))
            put("ScryptObject", JSONObject().apply {
                put("Salt", Base64.getEncoder().encodeToString(salt))
                put("N", testScryptN); put("R", testScryptR); put("P", 1); put("KeyLen", testScryptKeyLen)
            })
            put("Version", 2)
            put("FeatureFlags", JSONArray(listOf("GCMIV128", "EMENames", "LongNames", "Raw64", "HKDF")))
        }

        val parsed = GocryptfsConfig.parse(json.toString().toByteArray(Charsets.UTF_8))
        assertFalse(parsed.hasDirIV)
        assertEquals(GocryptfsCipher.AES_256_GCM, parsed.cipher)
        assertArrayEquals(masterkey, GocryptfsMasterkey.unlock(parsed, password))
    }

    @Test
    fun `vault with XChaCha20Poly1305 and DirIV is accepted`() {
        val masterkey = freshMasterkey()
        val password = "hunter2".toCharArray()
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val encryptedKey = GocryptfsMasterkey.wrap(masterkey, password, salt, testScryptN, testScryptR, testScryptKeyLen, random)

        val json = JSONObject().apply {
            put("EncryptedKey", Base64.getEncoder().encodeToString(encryptedKey))
            put("ScryptObject", JSONObject().apply {
                put("Salt", Base64.getEncoder().encodeToString(salt))
                put("N", testScryptN); put("R", testScryptR); put("P", 1); put("KeyLen", testScryptKeyLen)
            })
            put("Version", 2)
            put("FeatureFlags", JSONArray(listOf("XChaCha20Poly1305", "DirIV", "EMENames", "LongNames", "Raw64", "HKDF")))
        }

        val parsed = GocryptfsConfig.parse(json.toString().toByteArray(Charsets.UTF_8))
        assertTrue(parsed.hasDirIV)
        assertEquals(GocryptfsCipher.XCHACHA20_POLY1305, parsed.cipher)
        assertArrayEquals(masterkey, GocryptfsMasterkey.unlock(parsed, password))
    }

    @Test
    fun `GCMIV128 and XChaCha20Poly1305 together are rejected as mutually exclusive`() {
        val json = JSONObject().apply {
            put("EncryptedKey", Base64.getEncoder().encodeToString(ByteArray(48)))
            put("ScryptObject", JSONObject().apply {
                put("Salt", Base64.getEncoder().encodeToString(ByteArray(16)))
                put("N", testScryptN); put("R", testScryptR); put("P", 1); put("KeyLen", testScryptKeyLen)
            })
            put("Version", 2)
            put("FeatureFlags", JSONArray(listOf("GCMIV128", "XChaCha20Poly1305", "EMENames", "LongNames", "Raw64", "HKDF")))
        }

        assertThrows(GocryptfsConfigException::class.java) {
            GocryptfsConfig.parse(json.toString().toByteArray(Charsets.UTF_8))
        }
    }

    @Test
    fun `neither GCMIV128 nor XChaCha20Poly1305 is rejected`() {
        val json = JSONObject().apply {
            put("EncryptedKey", Base64.getEncoder().encodeToString(ByteArray(48)))
            put("ScryptObject", JSONObject().apply {
                put("Salt", Base64.getEncoder().encodeToString(ByteArray(16)))
                put("N", testScryptN); put("R", testScryptR); put("P", 1); put("KeyLen", testScryptKeyLen)
            })
            put("Version", 2)
            put("FeatureFlags", JSONArray(listOf("EMENames", "LongNames", "Raw64", "HKDF")))
        }

        assertThrows(GocryptfsConfigException::class.java) {
            GocryptfsConfig.parse(json.toString().toByteArray(Charsets.UTF_8))
        }
    }

    @Test
    fun `PlaintextNames vault is accepted without EMENames or Raw64`() {
        val masterkey = freshMasterkey()
        val password = "hunter2".toCharArray()
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val encryptedKey = GocryptfsMasterkey.wrap(masterkey, password, salt, testScryptN, testScryptR, testScryptKeyLen, random)

        val json = JSONObject().apply {
            put("EncryptedKey", Base64.getEncoder().encodeToString(encryptedKey))
            put("ScryptObject", JSONObject().apply {
                put("Salt", Base64.getEncoder().encodeToString(salt))
                put("N", testScryptN); put("R", testScryptR); put("P", 1); put("KeyLen", testScryptKeyLen)
            })
            put("Version", 2)
            put("FeatureFlags", JSONArray(listOf("PlaintextNames", "GCMIV128", "HKDF")))
        }

        val parsed = GocryptfsConfig.parse(json.toString().toByteArray(Charsets.UTF_8))
        assertTrue(parsed.plaintextNames)
        assertFalse(parsed.hasDirIV)
        assertEquals(GocryptfsCipher.AES_256_GCM, parsed.cipher)
        assertArrayEquals(masterkey, GocryptfsMasterkey.unlock(parsed, password))
    }
}