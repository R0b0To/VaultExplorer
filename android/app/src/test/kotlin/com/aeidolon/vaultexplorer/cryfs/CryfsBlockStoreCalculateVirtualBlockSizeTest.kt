package com.aeidolon.vaultexplorer.cryfs

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * calculateVirtualBlockSize was already public (companion object, no
 * modifier) -- CryfsBlockStore.kt just had zero test coverage of any kind.
 * Overhead numbers below were computed independently in a standalone Java
 * program mirroring this exact arithmetic before writing these assertions,
 * rather than hand-derived and hoped to be right: ON_DISK_HEADER is 14
 * bytes ("cryfs;block;0" + a trailing NUL), ENCRYPTED_LAYER_HEADER is 2,
 * INTEGRITY_HEADER_SIZE is 2+16+4+8=30.
 */
class CryfsBlockStoreCalculateVirtualBlockSizeTest {

    @Test
    fun `xchacha20-poly1305 subtracts 86 bytes of overhead`() {
        assertEquals(4010, CryfsBlockStore.calculateVirtualBlockSize(4096, "xchacha20-poly1305"))
        assertEquals(4194218, CryfsBlockStore.calculateVirtualBlockSize(4 * 1024 * 1024, "xchacha20-poly1305"))
    }

    @Test
    fun `aes gcm variants subtract 78 bytes regardless of key size`() {
        assertEquals(4018, CryfsBlockStore.calculateVirtualBlockSize(4096, "aes-256-gcm"))
        assertEquals(4018, CryfsBlockStore.calculateVirtualBlockSize(4096, "aes-128-gcm"))
    }

    @Test
    fun `aes cfb variants subtract 62 bytes regardless of key size`() {
        assertEquals(4034, CryfsBlockStore.calculateVirtualBlockSize(4096, "aes-256-cfb"))
        assertEquals(4034, CryfsBlockStore.calculateVirtualBlockSize(4096, "aes-128-cfb"))
    }

    @Test
    fun `an unrecognized cipher name falls back to the xchacha20 overhead, not zero`() {
        // Falling back to 0 overhead here would silently overstate the
        // usable block size for a cipher this code doesn't otherwise know
        // about -- the fallback deliberately picks the *largest* known
        // overhead (40 bytes) instead, so an unrecognized name underclaims
        // rather than overclaims.
        assertEquals(4010, CryfsBlockStore.calculateVirtualBlockSize(4096, "some-future-cipher"))
    }
}
