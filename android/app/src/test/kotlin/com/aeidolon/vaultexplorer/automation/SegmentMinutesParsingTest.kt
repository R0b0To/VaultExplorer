package com.aeidolon.vaultexplorer.automation

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `segment_minutes` arrives from Tasker, MacroDroid and adb, which do not agree
 * on how to type a number, so the parser has to take whatever shows up and
 * never let a bad value turn into a surprising recording.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class SegmentMinutesParsingTest {

    @Test
    fun `an int is taken as is`() {
        assertEquals(10, VaultAutomationReceiver.parseSegmentMinutes(10))
    }

    @Test
    fun `a long or a double is taken as whole minutes`() {
        assertEquals(5, VaultAutomationReceiver.parseSegmentMinutes(5L))
        assertEquals(5, VaultAutomationReceiver.parseSegmentMinutes(5.9))
    }

    @Test
    fun `text is parsed, ignoring surrounding spaces`() {
        assertEquals(30, VaultAutomationReceiver.parseSegmentMinutes("30"))
        assertEquals(30, VaultAutomationReceiver.parseSegmentMinutes("  30 "))
    }

    @Test
    fun `missing, unreadable and negative values mean no segmenting`() {
        assertEquals(0, VaultAutomationReceiver.parseSegmentMinutes(null))
        assertEquals(0, VaultAutomationReceiver.parseSegmentMinutes(""))
        assertEquals(0, VaultAutomationReceiver.parseSegmentMinutes("ten"))
        assertEquals(0, VaultAutomationReceiver.parseSegmentMinutes(true))
        assertEquals(0, VaultAutomationReceiver.parseSegmentMinutes(-5))
        assertEquals(0, VaultAutomationReceiver.parseSegmentMinutes("-5"))
    }

    @Test
    fun `huge values are capped at four hours`() {
        assertEquals(240, VaultAutomationReceiver.parseSegmentMinutes(100000))
        assertEquals(240, VaultAutomationReceiver.parseSegmentMinutes("999"))
    }

    @Test
    fun `the saved message names the parts only when there is more than one`() {
        assertEquals("Recording saved (1500ms)", VaultAutomationReceiver.recordingSavedMessage("Recording", 1500, 1))
        assertEquals("Recording saved (1500ms)", VaultAutomationReceiver.recordingSavedMessage("Recording", 1500, 0))
        assertEquals(
            "Audio recording saved in 3 parts (1500ms)",
            VaultAutomationReceiver.recordingSavedMessage("Audio recording", 1500, 3),
        )
    }
}
