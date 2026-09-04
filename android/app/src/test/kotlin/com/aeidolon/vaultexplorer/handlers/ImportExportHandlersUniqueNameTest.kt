package com.aeidolon.vaultexplorer.handlers

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * uniqueNameAgainst is the algorithm behind uniqueImportName -- the guard
 * added so import can no longer silently overwrite an existing file/folder
 * at the destination (see its own doc comment in ImportExportHandlers.kt).
 * It was extracted from a private method into an internal companion
 * function specifically so it's testable without a live container session
 * (which existingNamesLowercase, the caller supplying its `existing` set,
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
}
