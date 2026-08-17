package com.aeidolon.vaultexplorer

import java.io.File
import com.aeidolon.vaultexplorer.handlers.SplitContainerMountHandlers
import com.aeidolon.vaultexplorer.handlers.SplitJoinHandlers

/**
 * Resolves an on-disk split-container part sequence by naming convention
 * (`<name>.NNN` / `<name>.partN`, matching what [SplitJoinHandlers.handleSplitContainer]
 * itself writes). Pulled out of `SplitJoinHandlers` so both directions
 * that need "given one part, find the rest" -- joining them back into a
 * single file ([SplitJoinHandlers.handleJoinContainer]) and mounting them
 * directly without ever joining ([SplitContainerMountHandlers]) -- share
 * one naming/ordering source of truth instead of drifting apart.
 */
object SplitPartResolver {
    // Matches the ".NNN" (any digit width) or ".partN" suffix
    // SplitJoinHandlers.handleSplitContainer itself writes --
    // ContainerSplitterSheet's own `_stripPartSuffix` (Dart side) mirrors
    // the same shape for the "first part" picker's default output-name
    // suggestion, but *this* is the source of truth for what the file
    // names on disk actually look like, since native is the one writing
    // them.
    private val partSuffixRegex = Regex("""^(.*)\.(\d+|part\d+)$""", RegexOption.IGNORE_CASE)

    /**
     * Resolves [firstFile]'s sibling chunk sequence in its own folder, by
     * naming convention. Returns just [firstFile] itself when its name
     * doesn't match the ".NNN"/".partN" shape at all (a plain, unsplit
     * file was picked), or when the shape matches but no ".001"-equivalent
     * sibling actually exists (e.g. the user picked part 2 of a sequence
     * whose part 1 is missing) -- in both cases callers still do something
     * sensible with what was picked instead of silently producing nothing.
     */
    fun resolvePartSequence(firstFile: File): List<File> {
        val dir = firstFile.parentFile ?: return listOf(firstFile)
        val match = partSuffixRegex.find(firstFile.name) ?: return listOf(firstFile)

        val base = match.groupValues[1]
        val suffix = match.groupValues[2]
        val isPartWord = suffix.startsWith("part", ignoreCase = true)
        val padWidth = suffix.length

        val parts = mutableListOf<File>()
        var n = 1
        while (true) {
            val name = if (isPartWord) "$base.part$n" else "$base.%0${padWidth}d".format(n)
            val candidate = File(dir, name)
            if (!candidate.exists()) break
            parts.add(candidate)
            n++
        }
        return if (parts.isEmpty()) listOf(firstFile) else parts
    }
}
