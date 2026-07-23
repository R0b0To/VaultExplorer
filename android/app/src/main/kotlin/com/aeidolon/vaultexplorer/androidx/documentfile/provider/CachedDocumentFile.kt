package androidx.documentfile.provider

import android.net.Uri

class CachedDocumentFile(
    private val delegate: DocumentFile,
    private val cachedName: String,
    private val cachedIsDirectory: Boolean? = null,
    private val cachedLength: Long? = null,
    private val cachedLastModified: Long? = null,
) : DocumentFile(delegate.parentFile) {
    override fun createFile(mimeType: String, displayName: String): DocumentFile? =
        delegate.createFile(mimeType, displayName)

    override fun createDirectory(displayName: String): DocumentFile? =
        delegate.createDirectory(displayName)

    override fun getName(): String = cachedName
    override fun getType(): String? = delegate.type
    override fun getUri(): Uri = delegate.uri
    override fun isDirectory(): Boolean = cachedIsDirectory ?: delegate.isDirectory
    override fun isFile(): Boolean = if (cachedIsDirectory != null) !cachedIsDirectory else delegate.isFile
    override fun isVirtual(): Boolean = delegate.isVirtual
    override fun lastModified(): Long = cachedLastModified ?: delegate.lastModified()
    override fun length(): Long = cachedLength ?: delegate.length()
    override fun canRead(): Boolean = delegate.canRead()
    override fun canWrite(): Boolean = delegate.canWrite()
    override fun delete(): Boolean = delegate.delete()
    override fun exists(): Boolean = delegate.exists()
    override fun listFiles(): Array<DocumentFile> = delegate.listFiles()
    override fun findFile(displayName: String): DocumentFile? = delegate.findFile(displayName)
    override fun renameTo(displayName: String): Boolean = delegate.renameTo(displayName)
}