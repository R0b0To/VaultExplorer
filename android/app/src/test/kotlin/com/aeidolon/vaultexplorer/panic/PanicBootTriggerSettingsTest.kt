package com.aeidolon.vaultexplorer.panic

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * [PanicBootTriggerSettings] is the one piece of state [PanicBootReceiver]
 * reads on every device boot -- getting a default wrong here means either
 * a device that silently never arms (a "reboot to wipe" that just doesn't
 * fire), or worse, one that looks unarmed while still carrying an armed
 * tier from a previous session. Mirrors [PanicTierTest]'s coverage of
 * [PanicSettings]-shaped defaults, using Robolectric for the
 * SharedPreferences-backed Context this store needs (see
 * RawFileResolverTest for the same pattern).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class PanicBootTriggerSettingsTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `a fresh install is not armed`() {
        assertFalse(PanicBootTriggerSettings.isArmed(context))
    }

    @Test
    fun `a fresh install defaults its armed tier to the least destructive one`() {
        assertEquals(PanicTier.SESSION_PURGE, PanicBootTriggerSettings.getArmedTier(context))
    }

    @Test
    fun `setArmed round-trips true and false`() {
        PanicBootTriggerSettings.setArmed(context, true)
        assertTrue(PanicBootTriggerSettings.isArmed(context))

        PanicBootTriggerSettings.setArmed(context, false)
        assertFalse(PanicBootTriggerSettings.isArmed(context))
    }

    @Test
    fun `setArmedTier round-trips every declared tier`() {
        for (tier in PanicTier.entries) {
            PanicBootTriggerSettings.setArmedTier(context, tier)
            assertEquals(tier, PanicBootTriggerSettings.getArmedTier(context))
        }
    }

    @Test
    fun `disarmSynchronously clears the armed flag`() {
        PanicBootTriggerSettings.setArmed(context, true)
        assertTrue(PanicBootTriggerSettings.isArmed(context))

        PanicBootTriggerSettings.disarmSynchronously(context)
        assertFalse(PanicBootTriggerSettings.isArmed(context))
    }

    @Test
    fun `disarmSynchronously does not touch the armed tier`() {
        PanicBootTriggerSettings.setArmedTier(context, PanicTier.NUCLEAR_WIPE)
        PanicBootTriggerSettings.setArmed(context, true)

        PanicBootTriggerSettings.disarmSynchronously(context)

        assertEquals(PanicTier.NUCLEAR_WIPE, PanicBootTriggerSettings.getArmedTier(context))
    }
}
