package com.aeidolon.vaultexplorer.reader

/**
 * Picks the image to use as a book's cover in the file manager.
 *
 * An EPUB names its cover in the package document (see
 * [EpubPackage.findCoverPath]). A comic archive has no such metadata, so its
 * cover is its first page -- by the same rules the comic reader uses to order
 * pages (`comicPageNames` / `naturalCompare` in `comic_pages.dart`), so the
 * thumbnail is always the page the reader opens on.
 *
 * Kept free of Android classes so it can be unit-tested on the plain JVM.
 */
object BookCover {
    /**
     * Largest cover entry read for a thumbnail. Below the reader's own
     * [ZipReader.MAX_ENTRY_BYTES]: a tile preview is not worth holding a
     * 40 MB page in memory for, and a hostile or oversized first page just
     * falls through to the next candidate (or the plain file-type icon).
     */
    const val MAX_COVER_BYTES = 24L * 1024 * 1024

    /** Same set as `MediaViewerConstants.imageExtensions`. */
    private val PAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "gif", "webp", "avif", "heic")

    private val CHUNK = Regex("\\d+|\\D+")
    private val LEADING_ZEROS = Regex("^0+")

    /**
     * The first [limit] pages of a comic, in reading order.
     *
     * More than one so a first page the platform cannot decode (an AVIF or
     * HEIC page on an older Android, a corrupt file) does not cost the book
     * its thumbnail when the second page is fine.
     */
    fun comicCoverCandidates(directory: ZipDirectory, limit: Int = 3): List<ZipEntryInfo> =
        directory.entries
            .asSequence()
            .filter { !it.isDirectory && !it.isEncrypted && isPage(it.name) }
            .sortedWith { a, b -> naturalCompare(a.name, b.name) }
            .take(limit)
            .toList()

    /** An image entry that is not an archiver dropping (`__MACOSX/`, `._001.jpg`). */
    internal fun isPage(name: String): Boolean {
        val parts = name.split('/')
        for (part in parts) {
            if (part.isEmpty()) continue
            if (part.startsWith('.') || part == "__MACOSX") return false
        }
        return hasRasterExtension(parts.last())
    }

    internal fun hasRasterExtension(name: String): Boolean {
        val dot = name.lastIndexOf('.')
        if (dot < 0) return false
        return name.substring(dot + 1).lowercase() in PAGE_EXTENSIONS
    }

    /**
     * Case-insensitive comparison where digit runs compare by value, so
     * `page2.jpg` < `page10.jpg` and `001.jpg` < `002.jpg` < `010.jpg`.
     * A line-for-line port of `naturalCompare` in `comic_pages.dart`; the two
     * must agree or the thumbnail would not be the reader's first page.
     */
    fun naturalCompare(a: String, b: String): Int {
        val left = CHUNK.findAll(a.lowercase()).map { it.value }.toList()
        val right = CHUNK.findAll(b.lowercase()).map { it.value }.toList()
        val shared = minOf(left.size, right.size)
        for (i in 0 until shared) {
            val x = left[i]
            val y = right[i]
            val order = if (isDigit(x[0]) && isDigit(y[0])) {
                val xs = x.replaceFirst(LEADING_ZEROS, "")
                val ys = y.replaceFirst(LEADING_ZEROS, "")
                if (xs.length != ys.length) xs.length.compareTo(ys.length) else xs.compareTo(ys)
            } else {
                x.compareTo(y)
            }
            if (order != 0) return order
        }
        val byLength = left.size.compareTo(right.size)
        return if (byLength != 0) byLength else a.compareTo(b)
    }

    private fun isDigit(c: Char) = c in '0'..'9'
}
