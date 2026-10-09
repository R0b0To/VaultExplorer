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
        val alternatives: List<GlobPattern> = emptyList(),
    ) {
        fun matches(relativePath: String): Boolean {
            val normalized = relativePath.trim().replace('\\', '/').trim('/')
            if (alternatives.isNotEmpty()) {
                return alternatives.any { it.matches(normalized) }
            }
            return regex.matches(normalized)
        }

        /**
         * Exclusion matching also treats a matching folder as a match for
         * everything below it. A pattern without `/` matches any path
         * segment; slash-separated patterns match a path from the selected
         * folder root and any of its descendants.
         */
        fun matchesPathOrAncestor(relativePath: String): Boolean {
            val normalized = relativePath.trim().replace('\\', '/').trim('/')
            if (normalized.isEmpty()) return false
            if (alternatives.isNotEmpty()) {
                return alternatives.any { it.matchesPathOrAncestor(normalized) }
            }

            val pathPattern = rawPattern.replace('\\', '/').trim('/').contains('/')
            if (!pathPattern) {
                return normalized.split('/').any { regex.matches(it) }
            }

            if (regex.matches(normalized)) return true
            var separator = normalized.lastIndexOf('/')
            while (separator > 0) {
                if (regex.matches(normalized.substring(0, separator))) return true
                separator = normalized.lastIndexOf('/', separator - 1)
            }
            return false
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

        // A comma-separated list is convenient for automation extras such as
        // `Android,Download`. Keep commas inside brace alternatives
        // (`{jpg,png}`) and character classes (`[a,b]`) as glob syntax.
        val patterns = splitTopLevelAlternatives(clean)
        if (patterns.size > 1) {
            val compiled = patterns.map { compile(it, caseSensitive) }
            val options = if (caseSensitive) emptySet() else setOf(RegexOption.IGNORE_CASE)
            val unionBody = compiled.joinToString("|") { pattern ->
                pattern.regex.pattern.removePrefix("^").removeSuffix("$")
            }
            return GlobPattern(
                rawPattern = globPattern,
                regex = Regex("^(?:$unionBody)$", options),
                isRecursive = compiled.any { it.isRecursive },
                alternatives = compiled,
            )
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

    /** Splits comma-separated patterns without splitting inside glob groups. */
    private fun splitTopLevelAlternatives(pattern: String): List<String> {
        val result = mutableListOf<String>()
        var braces = 0
        var brackets = 0
        var start = 0
        pattern.forEachIndexed { index, char ->
            when (char) {
                '{' -> braces++
                '}' -> if (braces > 0) braces--
                '[' -> brackets++
                ']' -> if (brackets > 0) brackets--
                ',' -> if (braces == 0 && brackets == 0) {
                    pattern.substring(start, index)
                        .trim()
                        .takeIf { it.isNotEmpty() }
                        ?.let { result.add(it) }
                    start = index + 1
                }
            }
        }
        pattern.substring(start)
            .trim()
            .takeIf { it.isNotEmpty() }
            ?.let { result.add(it) }
        return result
    }

    /**
     * Helper to match directly without retaining [GlobPattern].
     */
    fun matches(pattern: GlobPattern?, relativePath: String): Boolean {
        if (pattern == null) return true
        return pattern.matches(relativePath)
    }
}
