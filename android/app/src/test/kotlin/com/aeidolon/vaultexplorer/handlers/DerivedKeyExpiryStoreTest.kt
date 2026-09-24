package com.aeidolon.vaultexplorer.handlers

import android.content.Context
import android.content.SharedPreferences
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * [DerivedKeyExpiryStore] decides when a cached derived key has to go, so a
 * mistake here is either a key that outlives the lifetime the user picked
 * (the whole point of the feature) or one purged early. Uses Robolectric only
 * for a real SharedPreferences implementation; the clock is injected so no
 * test sleeps.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DerivedKeyExpiryStoreTest {

    private var now = 1_000_000L
    private lateinit var prefs: SharedPreferences
    private lateinit var store: DerivedKeyExpiryStore

    private val vaultA = "content://tree/vault-a"
    private val vaultB = "content://tree/vault-b"
    private val blobA = "vc2_derived_AAAA"

    @Before
    fun setUp() {
        val context: Context = ApplicationProvider.getApplicationContext()
        prefs = context.getSharedPreferences("derived_key_expiry_test", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        now = 1_000_000L
        store = DerivedKeyExpiryStore(prefs) { now }
    }

    @Test
    fun `a path without an expiry never expires`() {
        assertNull(store.expiryOf(vaultA))
        assertNull(store.dueFor(vaultA))
        assertTrue(store.due().isEmpty())
    }

    @Test
    fun `setExpiry round-trips and null removes it`() {
        store.setExpiry(vaultA, 5_000_000L, null)
        assertEquals(5_000_000L, store.expiryOf(vaultA))

        store.setExpiry(vaultA, null, null)
        assertNull(store.expiryOf(vaultA))
    }

    @Test
    fun `an expiry only becomes due once the clock reaches it`() {
        store.setExpiry(vaultA, now + 1_000, null)
        assertNull(store.dueFor(vaultA))
        assertTrue(store.due().isEmpty())

        now += 999
        assertNull(store.dueFor(vaultA))

        now += 1 // exactly at the expiry instant counts as expired
        assertNotNull(store.dueFor(vaultA))
        assertEquals(listOf(vaultA), store.due().map { it.path })
    }

    @Test
    fun `expiries are tracked per path`() {
        store.setExpiry(vaultA, now - 1, null)
        store.setExpiry(vaultB, now + 10_000, null)

        assertEquals(listOf(vaultA), store.due().map { it.path })
        assertNull(store.dueFor(vaultB))
        assertEquals(now + 10_000, store.expiryOf(vaultB))
    }

    @Test
    fun `the blob alias is remembered when a key is stored under an expiry`() {
        store.setExpiry(vaultA, now - 1, null)

        val editor = prefs.edit().putString(blobA, "blob")
        store.recordStored(editor, vaultA, blobA)
        editor.commit()

        assertEquals(blobA, store.dueFor(vaultA)?.alias)
    }

    @Test
    fun `storing a key for a path without an expiry leaves no bookkeeping`() {
        val editor = prefs.edit().putString(blobA, "blob")
        store.recordStored(editor, vaultA, blobA)
        editor.commit()

        assertEquals(setOf(blobA), prefs.all.keys)
    }

    @Test
    fun `markPurged removes the blob and the bookkeeping and reports the path once`() {
        prefs.edit().putString(blobA, "blob").commit()
        store.setExpiry(vaultA, now - 1, blobA)

        store.markPurged(store.dueFor(vaultA)!!, blobA)

        assertFalse(prefs.contains(blobA))
        assertNull(store.expiryOf(vaultA))
        assertTrue(store.due().isEmpty())
        assertEquals(listOf(vaultA), store.takePurgedPaths())
        assertTrue(store.takePurgedPaths().isEmpty())
    }

    @Test
    fun `markPurged with keepExpiry leaves the elapsed expiry in place`() {
        prefs.edit().putString(blobA, "blob").commit()
        store.setExpiry(vaultA, now - 1, blobA)

        store.markPurged(store.dueFor(vaultA)!!, blobA, keepExpiry = true)

        assertFalse(prefs.contains(blobA))
        // A key cached again before the next launch is still already expired.
        assertNotNull(store.dueFor(vaultA))
        assertEquals(listOf(vaultA), store.takePurgedPaths())
    }

    @Test
    fun `choosing a new expiry cancels a purge that was waiting to be reported`() {
        store.setExpiry(vaultA, now - 1, null)
        store.markPurged(store.dueFor(vaultA)!!, null, keepExpiry = true)

        store.setExpiry(vaultA, now + 60_000, null)

        assertTrue(store.takePurgedPaths().isEmpty())
        assertNull(store.dueFor(vaultA))
    }

    @Test
    fun `choosing no expiry also cancels a purge that was waiting to be reported`() {
        store.setExpiry(vaultA, now - 1, null)
        store.markPurged(store.dueFor(vaultA)!!, null, keepExpiry = true)

        store.setExpiry(vaultA, null, null)

        assertTrue(store.takePurgedPaths().isEmpty())
    }

    @Test
    fun `forget drops the expiry without touching any blob`() {
        prefs.edit().putString(blobA, "blob").commit()
        store.setExpiry(vaultA, now + 1_000, blobA)

        store.forget(vaultA)

        assertNull(store.expiryOf(vaultA))
        assertTrue(prefs.contains(blobA))
    }

    @Test
    fun `path keys are stable and do not expose the path`() {
        val key = DerivedKeyExpiryStore.pathKey(vaultA)
        assertEquals(key, DerivedKeyExpiryStore.pathKey(vaultA))
        assertEquals(64, key.length)
        assertFalse(key.contains("vault"))
    }
}
