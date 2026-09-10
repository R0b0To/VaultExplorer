package com.aeidolon.vaultexplorer.panic

import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * PanicPurgeRegistry is a process-lifetime singleton (an `object`), so
 * these tests only ever add names, never assert an exact set size --
 * running alongside other tests that also register names must not make
 * this test flaky.
 */
class PanicPurgeRegistryTest {

    @Test
    fun `every credential store known as of Phase 1 is pre-registered`() {
        val names = PanicPurgeRegistry.credentialPrefsNames
        assertTrue(names.contains("vaultexplorer_app_secure_storage"))
        assertTrue(names.contains("vc2_derived_keys"))
        assertTrue(names.contains("vaultexplorer_automation_settings"))
    }

    @Test
    fun `registering a new store makes it appear in credentialPrefsNames`() {
        PanicPurgeRegistry.registerCredentialStore("test_only_store_a")
        assertTrue(PanicPurgeRegistry.credentialPrefsNames.contains("test_only_store_a"))
    }

    @Test
    fun `registering the same store twice does not throw and is a no-op the second time`() {
        PanicPurgeRegistry.registerCredentialStore("test_only_store_b")
        PanicPurgeRegistry.registerCredentialStore("test_only_store_b") // must not throw
        assertTrue(PanicPurgeRegistry.credentialPrefsNames.contains("test_only_store_b"))
    }
}
