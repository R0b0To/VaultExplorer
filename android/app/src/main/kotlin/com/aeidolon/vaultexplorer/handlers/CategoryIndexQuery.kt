package com.aeidolon.vaultexplorer.handlers

/**
 * The pure parts of [CategoryIndexHandlers]' query: how the request becomes
 * an SQL selection, and how a returned path becomes one relative to the
 * storage root. No Android types, so it runs on the plain JVM in unit tests.
 *
 * The selection deliberately uses plain `LIKE ?` with no `ESCAPE` clause: it
 * is what MediaProvider's strict SQL validation is certain to accept. The
 * cost is that a `_` or `%` in the root path acts as a wildcard and can match
 * a sibling folder with a similar name; that only ever lets *more* rows
 * through, and [relativePath] then re-checks every row against the exact root,
 * so such a row is dropped there.
 */
internal object CategoryIndexQuery {

    /**
     * [raw] reduced to what may safely be put in a `LIKE` pattern: lower-case
     * letters and digits, no leading dot, no duplicates. Anything else (a
     * slash, a space, a wildcard) is dropped rather than escaped, since a real
     * file extension is never made of them.
     */
    fun sanitizeExtensions(raw: List<String>): List<String> =
        raw.asSequence()
            .map { it.trim().trimStart('.').lowercase() }
            .filter { ext -> ext.isNotEmpty() && ext.all { it in 'a'..'z' || it in '0'..'9' } }
            .distinct()
            .toList()

    /** [root] with exactly one trailing slash: the prefix every path under it starts with. */
    fun prefixFor(root: String): String = if (root.endsWith("/")) root else "$root/"

    /** `column LIKE <root>/% AND (column LIKE %.ext1 OR column LIKE %.ext2 ...)`. */
    fun selection(column: String, extensionCount: Int): String {
        require(extensionCount > 0) { "at least one extension is required" }
        val anyExtension = (0 until extensionCount).joinToString(" OR ") { "$column LIKE ?" }
        return "$column LIKE ? AND ($anyExtension)"
    }

    /** The bind arguments for [selection], in order: the root prefix, then one per extension. */
    fun selectionArgs(root: String, extensions: List<String>): Array<String> =
        (listOf("${prefixFor(root)}%") + extensions.map { "%.$it" }).toTypedArray()

    /**
     * [absolute] relative to [root] ("DCIM/Camera/a.jpg"), or null when it is
     * not under [root] (including the wildcard look-alikes the selection lets
     * through, and the root itself).
     */
    fun relativePath(root: String, absolute: String): String? {
        val prefix = prefixFor(root)
        return if (absolute.length > prefix.length && absolute.startsWith(prefix)) {
            absolute.substring(prefix.length)
        } else {
            null
        }
    }
}
