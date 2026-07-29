package com.aeidolon.vaultexplorer

/**
 * Shared encode/decode for the directory-entry wire format described in
 * docs/architecture.md §5.3 (ADR-003).
 *
 * Wire layout: "<F|D>|<sizeBytes>|<mtimeUnixSecs>|<name>"
 *   - Field 1 is an explicit type tag ('F'/'D'), never inferred from the
 *     name.
 *   - Field 4 (name) is *everything after the third '|'* -- parsing must
 *     split on the first three '|' only and take the remainder verbatim,
 *     so a name that itself contains '|' (legal on ext2/3/4) round-trips
 *     exactly instead of corrupting size/mtime for that entry.
 *
 * Every producer on the Kotlin side (CryfsSession, CryptomatorSession,
 * GocryptfsSession) encodes through [encode]; every consumer
 * (ContainerDocumentsProvider, ImportExportHandlers) decodes through
 * [parse] instead of hand-rolling `startsWith("[DIR] ")` /
 * `substringBefore("|")` the way this code used to -- that pattern is
 * exactly the "infer type from the name" bug ADR-003 removes.
 */
object DirEntryWire {
    data class Entry(val name: String, val isDir: Boolean, val sizeBytes: Long, val mtimeUnixSecs: Long)

    fun encode(name: String, isDir: Boolean, sizeBytes: Long, mtimeUnixSecs: Long): String {
        val size = if (isDir) 0L else sizeBytes
        return "${if (isDir) "D" else "F"}|$size|$mtimeUnixSecs|$name"
    }

    /**
     * Parses one wire entry. Returns null if [raw] doesn't have the three
     * separators this format requires (e.g. it's the "System:TRUNCATED"
     * sentinel, which callers are expected to filter out before calling
     * this -- same convention the old ad hoc parsing used).
     */
    fun parse(raw: String): Entry? {
        val firstSep = raw.indexOf('|')
        if (firstSep < 0) return null
        val secondSep = raw.indexOf('|', firstSep + 1)
        if (secondSep < 0) return null
        val thirdSep = raw.indexOf('|', secondSep + 1)
        if (thirdSep < 0) return null

        val typeTag = raw.substring(0, firstSep)
        val sizeStr = raw.substring(firstSep + 1, secondSep)
        val mtimeStr = raw.substring(secondSep + 1, thirdSep)
        val name = raw.substring(thirdSep + 1)

        return Entry(
            name = name,
            isDir = typeTag == "D",
            sizeBytes = sizeStr.toLongOrNull() ?: 0L,
            mtimeUnixSecs = mtimeStr.toLongOrNull() ?: 0L,
        )
    }
}
