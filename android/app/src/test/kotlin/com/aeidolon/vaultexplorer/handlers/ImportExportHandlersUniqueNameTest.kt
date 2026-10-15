package com.aeidolon.vaultexplorer.handlers

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * uniqueNameAgainst is the algorithm behind uniqueImportName -- the guard
 * added so import can no longer silently overwrite an existing file/folder
 * at the destination (see its own doc comment in ImportExportHandlers.kt).
 * It was extracted from a private method into an internal companion
 * function specifically so it's testable without a live container session
 * (which existingNamesFolded, the caller supplying its `existing` set,
 * actually needs) -- same pattern as isMissingContainerUri in the same
 * companion object.
 */
class ImportExportHandlersUniqueNameTest {

    @Test
    fun `name with no collision is returned unchanged`() {
        val result = ImportExportHandlers.uniqueNameAgainst(setOf("other.txt"), "photo.jpg")
        assertEquals("photo.jpg", result)
    }

    @Test
    fun `colliding name gets a numbered suffix before the extension`() {
        val result = ImportExportHandlers.uniqueNameAgainst(setOf("photo.jpg"), "photo.jpg")
        assertEquals("photo (1).jpg", result)
    }

    @Test
    fun `comparison is case-insensitive but the returned name keeps its original case`() {
        val result = ImportExportHandlers.uniqueNameAgainst(setOf("photo.jpg"), "PHOTO.JPG")
        assertEquals("PHOTO (1).JPG", result)
    }

    @Test
    fun `already-taken numbered candidates are skipped in order`() {
        val existing = setOf("photo.jpg", "photo (1).jpg", "photo (2).jpg")
        val result = ImportExportHandlers.uniqueNameAgainst(existing, "photo.jpg")
        assertEquals("photo (3).jpg", result)
    }

    @Test
    fun `extensionless name gets the suffix appended directly`() {
        val result = ImportExportHandlers.uniqueNameAgainst(setOf("myfolder"), "MyFolder")
        assertEquals("MyFolder (1)", result)
    }

    @Test
    fun `a leading dot is not treated as an extension separator -- dotfiles keep their whole name as the base`() {
        // dot == 0 fails the `dot > 0` check in uniqueNameAgainst, so a
        // dotfile like .bashrc is (correctly) treated as having no
        // extension rather than an empty base with extension ".bashrc".
        val result = ImportExportHandlers.uniqueNameAgainst(setOf(".bashrc"), ".bashrc")
        assertEquals(".bashrc (1)", result)
    }

    @Test
    fun `a trailing dot with nothing after it is not treated as an extension`() {
        val result = ImportExportHandlers.uniqueNameAgainst(setOf("file."), "file.")
        assertEquals("file. (1)", result)
    }

    @Test
    fun `only the first dot from the right counts as the extension for a multi-dot name`() {
        val result = ImportExportHandlers.uniqueNameAgainst(setOf("archive.tar.gz"), "archive.tar.gz")
        assertEquals("archive.tar (1).gz", result)
    }

    @Test
    fun `empty existing set never triggers a rename`() {
        val result = ImportExportHandlers.uniqueNameAgainst(emptySet(), "anything.txt")
        assertEquals("anything.txt", result)
    }

    // ── Case-sensitive destinations (policy sent from Dart with each pick) ──

    @Test
    fun `foldName lowercases unless case-sensitive`() {
        assertEquals("notes", ImportExportHandlers.foldName("Notes", caseSensitive = false))
        assertEquals("Notes", ImportExportHandlers.foldName("Notes", caseSensitive = true))
    }

    @Test
    fun `case-sensitive destination keeps a name that differs only by case`() {
        val result = ImportExportHandlers.uniqueNameAgainst(
            setOf("notes.txt"), "Notes.txt", caseSensitive = true,
        )
        assertEquals("Notes.txt", result)
    }

    @Test
    fun `case-sensitive destination still renames an exact match`() {
        val result = ImportExportHandlers.uniqueNameAgainst(
            setOf("Notes.txt"), "Notes.txt", caseSensitive = true,
        )
        assertEquals("Notes (1).txt", result)
    }

    @Test
    fun `case-sensitive candidate search compares exact names`() {
        val existing = setOf("Notes.txt", "Notes (1).txt", "notes (2).txt")
        val result = ImportExportHandlers.uniqueNameAgainst(existing, "Notes.txt", caseSensitive = true)
        // "Notes (2).txt" is free: only "notes (2).txt" exists, which is a different name here.
        assertEquals("Notes (2).txt", result)
    }

    @Test
    fun `default stays case-insensitive`() {
        val result = ImportExportHandlers.uniqueNameAgainst(setOf("notes.txt"), "Notes.txt")
        assertEquals("Notes (1).txt", result)
    }

    // ── Export: siblings that differ only by case ──────────────────────────

    @Test
    fun `resolveCaseCollisions keeps the first name and renames the later one`() {
        val result = ImportExportHandlers.resolveCaseCollisions(listOf("Notes.txt", "a.txt", "notes.txt"))
        assertEquals(listOf("Notes.txt", "a.txt", "notes (1).txt"), result)
    }

    @Test
    fun `resolveCaseCollisions gives every extra spelling its own unique name`() {
        val result = ImportExportHandlers.resolveCaseCollisions(listOf("README", "readme", "ReadMe", "other"))
        assertEquals(listOf("README", "readme (1)", "ReadMe (2)", "other"), result)
    }

    @Test
    fun `resolveCaseCollisions never picks a name another entry already has`() {
        // "a (1)" is a real sibling, so the renamed "A" must skip to "(2)".
        val result = ImportExportHandlers.resolveCaseCollisions(listOf("a", "A", "a (1)"))
        assertEquals(listOf("a", "A (2)", "a (1)"), result)
    }

    @Test
    fun `resolveCaseCollisions leaves distinct names untouched`() {
        val names = listOf("a", "b", "c.txt")
        assertEquals(names, ImportExportHandlers.resolveCaseCollisions(names))
        assertEquals(emptyList<String>(), ImportExportHandlers.resolveCaseCollisions(emptyList()))
    }
}
