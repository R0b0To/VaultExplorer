package com.aeidolon.vaultexplorer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * RawFileResolver is what ChunkedFileEngine.readRange() now checks before
 * falling back to SAF (see the "Prefer a direct java.io.File over SAF..."
 * comment there) -- these tests pin down the two cases that fix actually
 * depends on: a resolvable app-private path, and a path that correctly
 * returns null so the SAF fallback still gets exercised.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class RawFileResolverTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `file under app-private filesDir resolves to a usable raw File`() {
        val file = File(context.filesDir, "vault_test_${System.nanoTime()}.bin")
        file.writeBytes(byteArrayOf(1, 2, 3))

        val resolved = RawFileResolver.getRawFileFromUri(context, android.net.Uri.fromFile(file))

        assertNotNull("expected app-private path to resolve", resolved)
        assertEquals(file.absolutePath, resolved!!.absolutePath)

        file.delete()
    }

    @Test
    fun `file outside app-private storage with no external storage permission resolves to null`() {
        // Robolectric grants no runtime/All-Files permissions by default, so
        // a path outside the app's own private directories should fail the
        // hasExternalStoragePermission() check and fall through to null --
        // which is exactly what tells ChunkedFileEngine to use SAF instead.
        val outside = File.createTempFile("vault_test_outside_", ".bin")
        outside.writeBytes(byteArrayOf(4, 5, 6))

        val resolved = RawFileResolver.getRawFileFromUri(context, android.net.Uri.fromFile(outside))

        assertNull("expected a path outside app-private storage, with no grant, to resolve to null", resolved)

        outside.delete()
    }

    @Test
    fun `non-file non-content scheme resolves to null`() {
        val resolved = RawFileResolver.getRawFileFromUri(context, android.net.Uri.parse("https://example.com/x"))
        assertNull(resolved)
    }
}
