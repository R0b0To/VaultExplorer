package com.aeidolon.vaultexplorer.internalvault

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/**
 * Length of the document behind [uri], or -1 when the provider does not say.
 * `DocumentFile.length()` returns 0 for "unknown", which is indistinguishable
 * from a genuinely empty file, so ask the provider directly as well.
 */
internal fun queryDocumentLength(context: Context, uri: Uri): Long = try {
    context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1L
} catch (_: Exception) {
    -1L
}

/** One document (a container file) behind the Storage Access Framework. */
class SafFileNode(
    private val context: Context,
    private val uri: Uri,
    override val name: String,
) : VaultNode {
    override val isDirectory: Boolean get() = false
    override val length: Long get() = queryDocumentLength(context, uri)
    override fun children(): List<VaultNode> = emptyList()
    override fun openRead(): InputStream =
        context.contentResolver.openInputStream(uri) ?: throw IOException("Could not open $name for reading")
}

/**
 * A document or folder inside a SAF tree. Folder listings go through
 * [SafDocumentOps], which fetches a whole directory in one provider query
 * rather than one Binder round trip per child property. That matters for
 * folder vaults, which are tens of thousands of small block files.
 */
open class SafTreeNode(
    protected val context: Context,
    protected val ops: SafDocumentOps,
    protected val doc: DocumentFile,
) : VaultNode {
    override val name: String get() = doc.name ?: ""
    override val isDirectory: Boolean get() = doc.isDirectory

    override val length: Long
        get() {
            val reported = doc.length()
            return if (reported > 0) reported else queryDocumentLength(context, doc.uri)
        }

    override fun children(): List<VaultNode> =
        ops.listChildren(doc).map { SafTreeNode(context, ops, it) }

    override fun openRead(): InputStream =
        context.contentResolver.openInputStream(doc.uri) ?: throw IOException("Could not open $name for reading")
}

/** A SAF folder that new files and subfolders can be created in. */
class SafWritableDir(
    context: Context,
    ops: SafDocumentOps,
    doc: DocumentFile,
) : SafTreeNode(context, ops, doc), WritableDir {

    override fun makeDir(name: String): WritableDir {
        val created = ops.createDirectorySafe(doc, name)
            ?: throw IOException("Could not create folder \"$name\" in the destination")
        return SafWritableDir(context, ops, created)
    }

    override fun makeFile(name: String): OutputStream {
        val created = ops.createFileSafe(doc, "application/octet-stream", name)
            ?: throw IOException("Could not create file \"$name\" in the destination")
        // "wt": the provider may hand back a pre-existing zero-byte placeholder.
        return context.contentResolver.openOutputStream(created.uri, "wt")
            ?: throw IOException("Could not open \"$name\" for writing in the destination")
    }
}
