package com.aeidolon.vaultexplorer

import android.net.Uri
import com.aeidolon.vaultexplorer.saf.UriToPath
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.ExecutorService

/**
 * Tools tab -> File Checksum & Hash Verifier ([HashVerifierSheet] on the
 * Dart side). Hashing a *vault*-resident file never reaches this class --
 * that stays entirely on the Dart side via [readFileChunk] +
 * `package:crypto`'s streaming digest, the same shape
 * `DuplicateFinderService._computeFullHash` already uses, since it's just
 * a local read with no SAF/ContentResolver involved.
 *
 * This class exists only for the other half: an *external* (on-device)
 * file, where a `content://` Uri can't be read directly from Dart at all.
 * [openForRead] reuses the same raw-file-fast-path / ContentResolver-
 * fallback shape as [SplitJoinHandlers.openSourceForRead]. Digests are
 * computed with `java.security.MessageDigest` -- a JVM built-in covering
 * MD5/SHA-1/SHA-256/SHA-512 with no new native (C++/JNI) surface needed,
 * matching how [DuplicateFinderService] already hashes vault files without
 * touching cipher_shim.cpp's mbedtls-backed layer.
 */
class HashVerifierHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    private val readBufferSize = 256 * 1024
    private val maxManifestBytes = 32L * 1024 * 1024

    private fun openForRead(uri: Uri): Pair<InputStream, Long> {
        val rawFile = UriToPath.getRawFile(activity, uri)
        if (rawFile != null && rawFile.canRead()) {
            return FileInputStream(rawFile) to rawFile.length()
        }
        val size = try {
            activity.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1L
        } catch (e: Exception) {
            -1L
        }
        val stream = activity.contentResolver.openInputStream(uri)
            ?: throw Exception("Could not open document: $uri")
        return stream to size
    }

    private fun messageDigestNameFor(wireName: String): String = when (wireName) {
        "MD5", "SHA-1", "SHA-256", "SHA-512" -> wireName
        else -> throw IllegalArgumentException("Unsupported hash algorithm: $wireName")
    }

    private fun ByteArray.toHex(): String {
        val sb = StringBuilder(size * 2)
        for (b in this) sb.append(String.format("%02x", b))
        return sb.toString()
    }

    /**
     * Streams [uri]'s bytes through one [MessageDigest] per requested
     * algorithm in a single read pass, reporting byte progress via
     * [HashProgressBridge] and honoring [HashCancellation] the same way
     * [SplitJoinHandlers]'s copy loops honor [SplitJoinCancellation].
     * Resolves with a `{algorithm wireName: lowercase hex digest}` map.
     */
    fun handleComputeExternalFileHash(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        val algorithms = call.argument<List<String>>("algorithms")
        val opId = call.argument<Number>("opId")?.toInt() ?: 0

        if (uriStr.isNullOrEmpty() || algorithms.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "uri and a non-empty algorithms list are required", null)
            return
        }

        ioExecutor.execute {
            var streamToClose: InputStream? = null
            try {
                val digests = algorithms.map { MessageDigest.getInstance(messageDigestNameFor(it)) }
                val uri = Uri.parse(uriStr)
                val (stream, size) = openForRead(uri)
                streamToClose = stream

                val buffer = ByteArray(readBufferSize)
                var bytesDone = 0L
                while (true) {
                    if (HashCancellation.isCancelled(opId)) {
                        throw HashCancelledException("Hash computation cancelled")
                    }
                    val n = stream.read(buffer)
                    if (n < 0) break
                    for (digest in digests) digest.update(buffer, 0, n)
                    bytesDone += n
                    HashProgressBridge.reportProgress(opId, bytesDone, size)
                }

                val out = HashMap<String, String>()
                for (i in algorithms.indices) {
                    out[algorithms[i]] = digests[i].digest().toHex()
                }
                activity.runOnUiThread { result.success(out) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    if (e is HashCancelledException) {
                        result.error("CANCELLED", e.message, null)
                    } else {
                        result.error("IO_ERROR", e.message ?: e.toString(), null)
                    }
                }
            } finally {
                try { streamToClose?.close() } catch (_: Exception) {}
                HashCancellation.clear(opId)
            }
        }
    }

    fun handleCancelHashCompute(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")
        if (opId == null) {
            result.error("INVALID_ARGS", "opId required", null)
            return
        }
        HashCancellation.cancel(opId.toInt())
        result.success(null)
    }

    /**
     * Reads an external document's full contents into memory -- used only
     * for small checksum manifest files (.sha256sum/.md5/...), never for
     * the large media files [handleComputeExternalFileHash] streams
     * without ever buffering them whole. Capped well above any real-world
     * manifest size so a mis-picked large file fails fast with a clear
     * error instead of silently pressuring memory.
     */
    fun handleReadExternalFileBytes(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        if (uriStr.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "uri is required", null)
            return
        }

        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriStr)
                val (stream, _) = openForRead(uri)
                stream.use { s ->
                    val buffer = ByteArray(64 * 1024)
                    val out = ByteArrayOutputStream()
                    var total = 0L
                    while (true) {
                        val n = s.read(buffer)
                        if (n < 0) break
                        total += n
                        if (total > maxManifestBytes) {
                            throw Exception("File is too large to read as a manifest")
                        }
                        out.write(buffer, 0, n)
                    }
                    activity.runOnUiThread { result.success(out.toByteArray()) }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }
}
