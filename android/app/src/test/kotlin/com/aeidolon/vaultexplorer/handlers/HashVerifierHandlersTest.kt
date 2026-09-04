package com.aeidolon.vaultexplorer.handlers

import com.aeidolon.vaultexplorer.handlers.HashVerifierHandlers.Companion.toHex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class HashVerifierHandlersTest {

    @Test
    fun `messageDigestNameFor accepts the four supported algorithms unchanged`() {
        assertEquals("MD5", HashVerifierHandlers.messageDigestNameFor("MD5"))
        assertEquals("SHA-1", HashVerifierHandlers.messageDigestNameFor("SHA-1"))
        assertEquals("SHA-256", HashVerifierHandlers.messageDigestNameFor("SHA-256"))
        assertEquals("SHA-512", HashVerifierHandlers.messageDigestNameFor("SHA-512"))
    }

    @Test
    fun `messageDigestNameFor rejects an unsupported or malformed algorithm name`() {
        assertThrows(IllegalArgumentException::class.java) {
            HashVerifierHandlers.messageDigestNameFor("sha-256") // wrong case
        }
        assertThrows(IllegalArgumentException::class.java) {
            HashVerifierHandlers.messageDigestNameFor("MD2")
        }
        assertThrows(IllegalArgumentException::class.java) {
            HashVerifierHandlers.messageDigestNameFor("")
        }
    }

    @Test
    fun `toHex renders known bytes as lowercase two-digit hex`() {
        // Verified against a plain-Java reimplementation of this exact
        // formatting call before writing this assertion: negative bytes
        // (0x80-0xff) and single-digit values (0x00, 0x0a, 0x7f) both need
        // the two's-complement/zero-padding behavior of "%02x" to line up.
        val bytes = byteArrayOf(0x00, 0x0A, 0x80.toByte(), 0xFF.toByte(), 0x7F, 0xDE.toByte(), 0xAD.toByte(), 0xBE.toByte(), 0xEF.toByte())
        assertEquals("000a80ff7fdeadbeef", bytes.toHex())
    }

    @Test
    fun `toHex of an empty array is an empty string`() {
        assertEquals("", ByteArray(0).toHex())
    }
}
