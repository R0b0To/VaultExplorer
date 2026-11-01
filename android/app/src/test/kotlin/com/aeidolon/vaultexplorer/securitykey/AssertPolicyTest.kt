package com.aeidolon.vaultexplorer.securitykey

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AssertPolicyTest {
    @Test
    fun noOptionsMeansNoPinAndDefaultPresence() {
        val p = AssertPolicy.fromGocryptfsOptions(emptyList())
        assertFalse(p.pin)
        assertNull(p.up)
        assertNull(p.uv)
    }

    @Test
    fun pinTrueIsReadFromGocryptfsAssertOptions() {
        assertTrue(AssertPolicy.fromGocryptfsOptions(listOf("pin=true")).pin)
        assertFalse(AssertPolicy.fromGocryptfsOptions(listOf("pin=false")).pin)
    }

    @Test
    fun upAndUvAreParsedAndUnknownOptionsIgnored() {
        val p = AssertPolicy.fromGocryptfsOptions(listOf("up=false", "uv=true", "bogus=1", "noequals", "pin=maybe"))
        assertEquals(false, p.up)
        assertEquals(true, p.uv)
        assertFalse(p.pin) // "maybe" is not a boolean, so it is ignored
    }

    @Test
    fun optionNamesAndValuesAreCaseInsensitive() {
        val p = AssertPolicy.fromGocryptfsOptions(listOf("PIN=TRUE", " up = False "))
        assertTrue(p.pin)
        assertEquals(false, p.up)
    }
}
