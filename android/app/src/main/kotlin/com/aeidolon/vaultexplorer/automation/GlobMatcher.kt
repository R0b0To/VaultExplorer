package com.aeidolon.vaultexplorer.automation

/**
 * High-performance, offline glob pattern engine for batch import/export operations.
 * Supports standard glob wildcards:
 * - `*`: Matches 0 or more characters within a single directory level (does not match `/`).
 * - `**`: Matches across directory levels (recursive).
 * - `?`: Matches any single character (excluding `/`).
 * - `[abc]`, `[a-z]`: Character class ranges.
 * - `[!abc]`, `[^abc]`: Negated character classes.
 * - `{jpg,png,gif}`: Brace expansion for alternatives.
 */
object GlobMatcher {

    data class GlobPattern(
        val rawPattern: String,
        val regex: Regex,
        val isRecursive: Boolean,
    ) {
        fun matches(relativePath: String): Boolean {
            val normalized = relativePath.trim().replace('\\', '/').trim('/')
            return regex.matches(normalized)
        }
    }

    /**
     * Compiles [globPattern] into a [GlobPattern].
     * Returns a match-all pattern if [globPattern] is null or blank.
     */
    fun compile(globPattern: String?, caseSensitive: Boolean = false): GlobPattern {
        if (globPattern.isNullOrBlank()) {
            val matchAllRegex = Regex(".*")
            return GlobPattern(rawPattern = "", regex = matchAllRegex, isRecursive = true)
        }

        val clean = globPattern.trim().replace('\\', '/').trim('/')
        if (clean.isEmpty()) {
            val matchAllRegex = Regex(".*")
            return GlobPattern(rawPattern = "", regex = matchAllRegex, isRecursive = true)
        }

        val isRecursive = clean.contains("**")

        val sb = StringBuilder("^")
        var i = 0
        val len = clean.length
        while (i < len) {
            val c = clean[i]
            when (c) {
                '*' -> {
                    if (i + 1 < len && clean[i + 1] == '*') {
                        // Double star **
                        if (i + 2 < len && clean[i + 2] == '/') {
                            sb.append("(?:.*/)?")
                            i += 3
                            continue
                        } else {
                            sb.append(".*")
                            i += 2
                            continue
                        }
                    } else {
                        sb.append("[^/]*")
                    }
                }
                '?' -> sb.append("[^/]")
                '[' -> {
                    val closeIndex = clean.indexOf(']', i + 1)
                    if (closeIndex > i + 1) {
                        val inner = clean.substring(i + 1, closeIndex)
                        if (inner.startsWith("!") || inner.startsWith("^")) {
                            sb.append("[^").append(inner.substring(1)).append("]")
                        } else {
                            sb.append("[").append(inner).append("]")
                        }
                        i = closeIndex + 1
                        continue
                    } else {
                        sb.append("\\[")
                    }
                }
                '{' -> {
                    val closeIndex = clean.indexOf('}', i + 1)
                    if (closeIndex > i + 1) {
                        val inner = clean.substring(i + 1, closeIndex)
                        val choices = inner.split(',').map { Regex.escape(it.trim()) }
                        sb.append("(?:").append(choices.joinToString("|")).append(")")
                        i = closeIndex + 1
                        continue
                    } else {
                        sb.append("\\{")
                    }
                }
                '.', '(', ')', '+', '|', '^', '$', '@', '%' -> {
                    sb.append('\\').append(c)
                }
                else -> sb.append(c)
            }
            i++
        }
        sb.append('$')

        val options = if (caseSensitive) emptySet() else setOf(RegexOption.IGNORE_CASE)
        val regex = Regex(sb.toString(), options)
        return GlobPattern(rawPattern = globPattern, regex = regex, isRecursive = isRecursive)
    }

    /**
     * Helper to match directly without retaining [GlobPattern].
     */
    fun matches(pattern: GlobPattern?, relativePath: String): Boolean {
        if (pattern == null) return true
        return pattern.matches(relativePath)
    }
}