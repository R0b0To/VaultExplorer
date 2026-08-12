package com.aeidolon.vaultexplorer.pdf

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.FileNotFoundException

class VaultPdfContentProvider : ContentProvider() {

    override fun onCreate(): Boolean = true

    private fun tokenOf(uri: Uri): String =
        uri.lastPathSegment ?: throw FileNotFoundException("Missing PDF session token")

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") {
            throw SecurityException("VaultPdfContentProvider is read-only")
        }
        val context = context ?: throw FileNotFoundException("No context")
        return VaultPdfSessionRegistry.open(context, tokenOf(uri))
    }

    override fun getType(uri: Uri): String = "application/pdf"

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val cursor = MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE))
        val stat = VaultPdfSessionRegistry.stat(tokenOf(uri))
        stat?.let { (displayName, size) ->
            cursor.addRow(arrayOf<Any>(displayName, size))
        }
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}