package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import android.os.ParcelFileDescriptor
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.reader.BookByteSource
import com.aeidolon.vaultexplorer.reader.BookError
import com.aeidolon.vaultexplorer.reader.BookFormatException
import com.aeidolon.vaultexplorer.reader.BookSessions
import com.aeidolon.vaultexplorer.reader.EpubPackage
import com.aeidolon.vaultexplorer.reader.FileByteSource
import com.aeidolon.vaultexplorer.reader.VaultByteSource
import com.aeidolon.vaultexplorer.reader.ZipReader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService

/**
 * Backs the in-app comic (.cbz) and e-book (.epub) readers.
 *
 * Protocol: `bookOpen` parses the ZIP directory once and returns a session
 * token; `bookReadEntry` then returns one entry's bytes (a page image) per
 * call; `bookClose` releases the session. An EPUB's chapters are not sent over
 * the channel at all -- the reader's WebView pulls them through the same
 * session (see HtmlViewerPlugin).
 *
 * Nothing is staged on disk: entries are decompressed in memory from ranged
 * reads of the (decrypted) file, so it works identically for every vault
 * format and for Local Storage, and leaves no plaintext behind.
 */
class BookReaderHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    private companion object {
        const val TAG = "BookReaderHandlers"
    }

    fun handleBookOpen(call: MethodCall, result: MethodChannel.Result) {
        val volId = call.argument<Number>("volId")?.toInt()
        val vaultPath = call.argument<String>("vaultPath")
        val localPathOrUri = call.argument<String>("localPathOrUri")
        val wantEpub = call.argument<String>("kind") == "epub"

        val isLocal = !localPathOrUri.isNullOrEmpty()
        if (!isLocal && (volId == null || vaultPath.isNullOrEmpty())) {
            result.error("INVALID_ARGS", "volId+vaultPath or localPathOrUri required", null)
            return
        }

        ioExecutor.execute {
            var source: BookByteSource? = null
            var handedOver = false
            try {
                source = if (isLocal) {
                    openLocalSource(localPathOrUri!!)
                } else {
                    if (!ContainerSessionRegistry.isUnlocked(volId!!)) {
                        activity.runOnUiThread { result.error("NOT_MOUNTED", "Container not mounted", null) }
                        return@execute
                    }
                    VaultByteSource(volId, vaultPath!!)
                }
                if (source == null) {
                    activity.runOnUiThread { result.error("FILE_NOT_FOUND", "Could not open file", null) }
                    return@execute
                }

                val directory = ZipReader.readDirectory(source)
                val epub = if (wantEpub) EpubPackage.parse(source, directory) else null
                val session = BookSessions.open(source, directory, epub)
                handedOver = true

                val reply: Map<String, Any> = if (epub != null) {
                    mapOf("status" to "ok", "token" to session.token, "epub" to epub.toMap())
                } else {
                    val files = directory.entries.filter { !it.isDirectory && !it.name.startsWith("__MACOSX/") }
                    mapOf(
                        "status" to "ok",
                        "token" to session.token,
                        "entries" to files.map { mapOf("name" to it.name, "size" to it.size) },
                        "encrypted" to files.any { it.isEncrypted },
                    )
                }
                activity.runOnUiThread { result.success(reply) }
            } catch (e: BookFormatException) {
                VeLog.w(TAG) { "bookOpen rejected: ${e.error} (${e.message})" }
                activity.runOnUiThread { result.success(mapOf("status" to statusFor(e.error))) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                if (!handedOver) runCatching { source?.close() }
            }
        }
    }

    fun handleBookReadEntry(call: MethodCall, result: MethodChannel.Result) {
        val token = call.argument<String>("token")
        val name = call.argument<String>("name")
        if (token.isNullOrEmpty() || name.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "token and name required", null)
            return
        }

        ioExecutor.execute {
            try {
                val session = BookSessions.get(token)
                if (session == null) {
                    activity.runOnUiThread { result.error("NO_SESSION", "Book is not open", null) }
                    return@execute
                }
                val entry = session.directory.find(name)
                if (entry == null) {
                    activity.runOnUiThread { result.error("BOOK_NOT_FOUND", "No such entry", null) }
                    return@execute
                }
                val bytes = ZipReader.readEntry(session.source, entry)
                activity.runOnUiThread {
                    try {
                        result.success(bytes)
                    } catch (e: OutOfMemoryError) {
                        // The platform-channel codec copies the payload; a huge
                        // entry can exhaust the Java heap there.
                        result.error("OUT_OF_MEMORY", "Entry is too large to load into memory", null)
                    }
                }
            } catch (e: BookFormatException) {
                activity.runOnUiThread { result.error("BOOK_${e.error.name}", e.message, null) }
            } catch (e: OutOfMemoryError) {
                activity.runOnUiThread { result.error("OUT_OF_MEMORY", "Entry is too large to load into memory", null) }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleBookClose(call: MethodCall, result: MethodChannel.Result) {
        BookSessions.close(call.argument<String>("token"))
        result.success(null)
    }

    private fun statusFor(error: BookError): String = when (error) {
        BookError.NOT_ZIP -> "notZip"
        BookError.ENCRYPTED -> "encrypted"
        BookError.UNSUPPORTED -> "unsupported"
        BookError.TOO_LARGE -> "tooLarge"
        BookError.CORRUPT -> "corrupt"
        BookError.NOT_FOUND -> "invalid"
    }

    /** Same raw-path / SAF-document resolution the local archive handlers use. */
    private fun openLocalSource(pathOrUri: String): BookByteSource? {
        val pfd: ParcelFileDescriptor? = if (pathOrUri.startsWith("/")) {
            // Taken as a path as-is: Uri.parse would treat a '#' or '%' in a
            // file name as URI syntax.
            ParcelFileDescriptor.open(File(pathOrUri), ParcelFileDescriptor.MODE_READ_ONLY)
        } else {
            val uri = Uri.parse(pathOrUri)
            if (uri.scheme == null || uri.scheme == "file") {
                ParcelFileDescriptor.open(File(uri.path ?: pathOrUri), ParcelFileDescriptor.MODE_READ_ONLY)
            } else {
                val docUri = activity.safStorageManager.resolveDocumentUriFromTreePath(pathOrUri) ?: uri
                activity.contentResolver.openFileDescriptor(docUri, "r")
            }
        }
        if (pfd == null) return null
        return try {
            FileByteSource(pfd, pathOrUri)
        } catch (e: Exception) {
            runCatching { pfd.close() }
            throw e
        }
    }
}
