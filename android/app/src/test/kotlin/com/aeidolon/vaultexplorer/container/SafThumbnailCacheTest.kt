package com.aeidolon.vaultexplorer.container

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Covers the pure, native-free logic in [SafThumbnailCache] -- see that
 * object's doc comment on [SafThumbnailCache.isJpegSignature] for why
 * [SafThumbnailCache.tryRead] itself isn't reachable from a plain JVM
 * test (it calls into the compiled native library via
 * NativeEngine.aesGcmDecryptNative, which only loads on a real device or
 * emulator). These tests exist so the two things that *can* be verified
 * without that -- the cache-key hashing and the JPEG sanity check -- have
 * some coverage rather than none.
 */
class SafThumbnailCacheTest {

    @Test
    fun `md5Hex matches the known digest for an empty string`() {
        // Standard, well-known MD5("") value -- also a cheap cross-check
        // that the hex encoding is lowercase, matching HashVerifierHandlers'
        // toHex() convention that produced Dart's on-disk filenames.
        assertEquals("d41d8cd98f00b204e9800998ecf8427e", SafThumbnailCache.md5Hex(""))
    }

    @Test
    fun `md5Hex matches the known digest for a simple ascii string`() {
        assertEquals("9e107d9d372bb6826bd81d3542a419d6", SafThumbnailCache.md5Hex("The quick brown fox jumps over the lazy dog"))
    }

    @Test
    fun `md5Hex is deterministic and path-sensitive`() {
        val a = SafThumbnailCache.md5Hex("folder/photo.jpg")
        val b = SafThumbnailCache.md5Hex("folder/photo.jpg")
        val c = SafThumbnailCache.md5Hex("folder/other.jpg")

        assertEquals(a, b)
        assertFalse("different paths must not hash to the same key", a == c)
    }

    @Test
    fun `isJpegSignature accepts real JPEG magic bytes`() {
        val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0x00, 0x10)
        assertTrue(SafThumbnailCache.isJpegSignature(jpeg))
    }

    @Test
    fun `isJpegSignature rejects non-JPEG bytes`() {
        val png = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47)
        assertFalse(SafThumbnailCache.isJpegSignature(png))
    }

    @Test
    fun `isJpegSignature rejects buffers shorter than the magic bytes`() {
        assertFalse(SafThumbnailCache.isJpegSignature(byteArrayOf()))
        assertFalse(SafThumbnailCache.isJpegSignature(byteArrayOf(0xFF.toByte())))
        assertFalse(SafThumbnailCache.isJpegSignature(byteArrayOf(0xFF.toByte(), 0xD8.toByte())))
    }
}
