package com.aeidolon.vaultexplorer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.FileNotFoundException
import java.util.concurrent.atomic.AtomicInteger

/**
 * OpenDiagnostics feeds always-on log lines, so what it may emit matters as much
 * as what it emits: never a path, a file name or an exception message.
 */
class OpenDiagnosticsTest {

    @Test
    fun failureTagNamesExceptionClassAndErrno() {
        val e = FileNotFoundException("/storage/emulated/0/Sync/secret.hc: open failed: EACCES (Permission denied)")
        assertEquals("FileNotFoundException/EACCES", OpenDiagnostics.failureTag(e))
    }

    @Test
    fun failureTagNeverLeaksPathOrMessage() {
        val e = FileNotFoundException("/storage/emulated/0/Sync/secret-holiday.hc: open failed: EPERM (Operation not permitted)")
        val tag = OpenDiagnostics.failureTag(e)
        assertEquals("FileNotFoundException/EPERM", tag)
        assertFalse(tag, tag.contains("secret"))
        assertFalse(tag, tag.contains("storage"))
        assertFalse(tag, tag.contains("Operation not permitted"))
    }

    @Test
    fun failureTagWithoutKnownErrnoIsJustTheClass() {
        assertEquals("SecurityException", OpenDiagnostics.failureTag(SecurityException("Permission Denial: opening provider")))
    }

    @Test
    fun failureTagDoesNotMistakeAFileNameForAnErrno() {
        // "EXAMPLE" and "EMULATED" look like errno names but are not on the whitelist.
        val e = FileNotFoundException("/storage/EMULATED/0/EXAMPLE.hc: no such file")
        assertEquals("FileNotFoundException", OpenDiagnostics.failureTag(e))
    }

    @Test
    fun occurrenceLimiterLogsFirstFiveThenPowersOfTwo() {
        val counter = AtomicInteger(0)
        val logged = (1..20).filter { OpenDiagnostics.shouldLogOccurrence(counter) }
        assertEquals(listOf(1, 2, 3, 4, 5, 8, 16), logged)
    }

    @Test
    fun occurrenceLimiterKeepsCountingAfterTheBurst() {
        val counter = AtomicInteger(0)
        repeat(100) { OpenDiagnostics.shouldLogOccurrence(counter) }
        assertEquals(100, counter.get())
        assertTrue(OpenDiagnostics.shouldLogOccurrence(counter).not()) // 101 is not a power of two
    }
}
