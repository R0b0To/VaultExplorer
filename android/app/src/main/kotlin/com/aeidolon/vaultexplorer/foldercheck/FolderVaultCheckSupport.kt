package com.aeidolon.vaultexplorer.foldercheck

import java.io.InputStream

/**
 * Shared by GocryptfsVaultCheck.verifyGocryptfsFile and
 * CryptomatorVaultCheck.verifyCryptomatorFile -- both need to read a
 * fixed-size buffer from a stream that may legitimately return short reads,
 * distinct from a normal single-shot InputStream.read(). Pulled out here
 * (rather than duplicated in both files, as it effectively was before the
 * FolderVaultChecker split) since it's the one piece of logic actually
 * shared across formats rather than merely similar between them.
 */
internal fun InputStream.readFullyInto(buf: ByteArray): Int {
    var off = 0
    while (off < buf.size) {
        val r = read(buf, off, buf.size - off)
        if (r < 0) break
        off += r
    }
    return off
}
