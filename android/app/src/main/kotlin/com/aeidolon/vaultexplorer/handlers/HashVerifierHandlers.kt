package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import com.aeidolon.vaultexplorer.saf.ScopedStorageUtils
import com.aeidolon.vaultexplorer.saf.UriToPath
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.bridge.HashProgressBridge
import com.aeidolon.vaultexplorer.cancellation.HashCancellation
import com.aeidolon.vaultexplorer.cancellation.HashCancelledException
import com.aeidolon.vaultexplorer.cancellation.SplitJoinCancellation
import com.aeidolon.vaultexplorer.MainActivity

/**
 * Tools tab -> File Checksum & Hash Verifier ([HashVerifierSheet] on the
 * Dart side), plus [DuplicateFinderService]'s content hashing.
 *
 * An *external* (on-device) file's `content://` Uri can't be read
 * directly from Dart at all, so [handleComputeExternalFileHash] streams
 * it here in one native read pass. [openForRead] reuses the same
 * raw-file-fast-path / ContentResolver-fallback shape as
 * [SplitJoinHandlers.openSourceForRead].
 *
 * A *vault*-resident file's bytes, by contrast, already have to cross
 * the platform channel to Dart via [readFileChunk] regardless (that's
 * how the app reads vault contents at all), so there's no read to save
 * by doing it here instead. What still moves to this class is the
 * *digest computation* over those chunks: [handleBeginHashSession] /
 * [handleUpdateHashSession] / [handleFinishHashSession] let the Dart
 * side keep owning the read loop while each chunk's digest update runs
 * through `java.security.MessageDigest` here rather than a Dart hashing
 * package -- the same primitive [handleComputeExternalFileHash] and
 * [handleHashBytesSha256] already use. Still no new native (C++/JNI)
 * surface: this stays a JVM built-in, not cipher_shim.cpp's
 * mbedtls-backed layer, which is reserved for password-based key
 * derivation (a different, salted/iterated primitive -- see
 * `hashPasswordSha256` in DerivedKeyHandlers.kt) and would produce the
 * wrong digest for plain content hashing.
 */
class HashVerifierHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    private val readBufferSize = 256 * 1024
    private val maxManifestBytes = 32L * 1024 * 1024

    /**
     * In-flight incremental hash sessions keyed by opId -- see
     * [handleBeginHashSession]. A session holds one [MessageDigest] per
     * requested algorithm so several algorithms can be computed over the
     * same read pass, matching how [handleComputeExternalFileHash]
     * already handles multiple algorithms natively. Entries are removed
     * by [handleFinishHashSession] (success) or [handleDiscardHashSession]
     * (the Dart-side loop stopped early -- cancelled, or a read failed --
     * and just needs the half-finished digests freed).
     */
    private val hashSessions = ConcurrentHashMap<Int, Map<String, MessageDigest>>()

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

    companion object {
        /**
         * Validates that [wireName] is one of the four algorithms this
         * handler supports, returning it unchanged (java.security.MessageDigest
         * already accepts these names directly) or throwing for anything
         * else. Moved into the companion object as a pure function --
         * same motivation as ImportExportHandlers.isMissingContainerUri --
         * so it's testable without a MainActivity instance.
         */
        internal fun messageDigestNameFor(wireName: String): String = when (wireName) {
            "MD5", "SHA-1", "SHA-256", "SHA-512" -> wireName
            else -> throw IllegalArgumentException("Unsupported hash algorithm: $wireName")
        }

        internal fun ByteArray.toHex(): String {
            val sb = StringBuilder(size * 2)
            for (b in this) sb.append(String.format("%02x", b))
            return sb.toString()
        }
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

    /**
     * Computes a plain SHA-256 digest of an in-memory byte buffer --
     * used by the Keyfile & Passphrase Generator to fingerprint a
     * freshly generated keyfile that's already fully in memory, so
     * there's no Uri/file to stream through [handleComputeExternalFileHash].
     * Runs on [ioExecutor] for consistency with this class's other
     * handlers, even though a single-buffer digest is cheap.
     */
    fun handleHashBytesSha256(call: MethodCall, result: MethodChannel.Result) {
        handleHashBytesOneShot(call, result, "SHA-256")
    }

    /**
     * One-shot MD5 of an in-memory buffer -- used by
     * `ThumbnailCacheService._encodeKey` to derive cache filenames/directory
     * names from a URI or path string. MD5 here is purely a cache-key
     * derivation, not a security boundary (collision resistance isn't a
     * property this needs), so it stays MD5 rather than switching to
     * SHA-256 -- changing the algorithm would change every existing cache
     * key and orphan the on-disk/in-container thumbnail cache on upgrade.
     */
    fun handleHashBytesMd5(call: MethodCall, result: MethodChannel.Result) {
        handleHashBytesOneShot(call, result, "MD5")
    }

    private fun handleHashBytesOneShot(call: MethodCall, result: MethodChannel.Result, algorithm: String) {
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null) {
            result.error("INVALID_ARGS", "bytes is required", null)
            return
        }

        ioExecutor.execute {
            try {
                val digest = MessageDigest.getInstance(algorithm).digest(bytes)
                val hex = digest.toHex()
                activity.runOnUiThread { result.success(hex) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("HASH_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }

    /**
     * Opens an incremental hash session under [opId]: one [MessageDigest]
     * per entry in [algorithms]. Pairs with [handleUpdateHashSession] fed
     * in a loop by the Dart-side caller (which owns the actual file read,
     * e.g. [readFileChunk]) and [handleFinishHashSession] to collect the
     * result -- lets a caller that already has to read a file chunk-by-
     * chunk on the Dart side (vault-resident files) still compute the
     * digest natively instead of via a Dart hashing package, without this
     * class needing to know how to read a vault file itself.
     */
    fun handleBeginHashSession(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        val algorithms = call.argument<List<String>>("algorithms")
        if (opId == null || algorithms.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "opId and a non-empty algorithms list are required", null)
            return
        }
        try {
            val digests = algorithms.associateWith { MessageDigest.getInstance(messageDigestNameFor(it)) }
            hashSessions[opId] = digests
            result.success(null)
        } catch (e: Exception) {
            result.error("HASH_ERROR", e.message ?: e.toString(), null)
        }
    }

    /** Feeds one chunk into every digest in the [opId] session opened by [handleBeginHashSession]. */
    fun handleUpdateHashSession(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        val bytes = call.argument<ByteArray>("bytes")
        if (opId == null || bytes == null) {
            result.error("INVALID_ARGS", "opId and bytes are required", null)
            return
        }
        val digests = hashSessions[opId]
        if (digests == null) {
            result.error("NO_SESSION", "No hash session for opId $opId", null)
            return
        }
        ioExecutor.execute {
            for (digest in digests.values) digest.update(bytes)
            activity.runOnUiThread { result.success(null) }
        }
    }

    /**
     * Finalizes and removes the [opId] session, returning a
     * `{algorithm wireName: lowercase hex digest}` map -- same shape
     * [handleComputeExternalFileHash] returns.
     */
    fun handleFinishHashSession(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        if (opId == null) {
            result.error("INVALID_ARGS", "opId is required", null)
            return
        }
        val digests = hashSessions.remove(opId)
        if (digests == null) {
            result.error("NO_SESSION", "No hash session for opId $opId", null)
            return
        }
        val out = HashMap<String, String>()
        for ((algo, digest) in digests) out[algo] = digest.digest().toHex()
        result.success(out)
    }

    /**
     * Drops the [opId] session without finalizing it -- for when the
     * Dart-side read loop stops early (cancelled, or a chunk read
     * failed) and just needs the half-finished [MessageDigest]s freed
     * rather than a result. Silently a no-op if the session is already
     * gone (e.g. already finished), so callers can call this
     * unconditionally on every non-success exit path.
     */
    fun handleDiscardHashSession(call: MethodCall, result: MethodChannel.Result) {
        val opId = call.argument<Number>("opId")?.toInt()
        if (opId != null) hashSessions.remove(opId)
        result.success(null)
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

    /**
     * Writes a small byte payload to an external file, creating it (and any
     * intermediate directories) if needed.
     *
     * Accepts the same (destinationPath, destinationTreeUri) pair used by
     * [SplitJoinHandlers] and [SingleFileCryptoHandlers]:
     *  - If [destinationPath] is a real filesystem path AND the app has raw
     *    write access (checked via [ScopedStorageUtils.canWriteRawPath]),
     *    writes via plain [java.io.File].
     *  - Otherwise (cloud storage, SD card without "All Files Access", or
     *    [destinationPath] itself is a `content://` SAF URI fallback),
     *    resolves the parent folder via [destinationTreeUri] and writes
     *    through [androidx.documentfile.provider.DocumentFile].
     *
     * Used by the checksum-manifest export in [HashVerifierSheet] and
     * the keyfile export in [KeyfilePassphraseGeneratorScreen].
     */
    fun handleWriteExternalFileBytes(call: MethodCall, result: MethodChannel.Result) {
        val destinationPath = call.argument<String>("destinationPath")
        val destinationTreeUri = call.argument<String>("destinationTreeUri")
        val fileName = call.argument<String>("fileName")
        val bytes = call.argument<ByteArray>("bytes")

        if (fileName.isNullOrEmpty() || bytes == null) {
            result.error("INVALID_ARGS", "fileName and bytes are required", null)
            return
        }

        ioExecutor.execute {
            try {
                val isSafPath = !destinationPath.isNullOrEmpty() &&
                    ScopedStorageUtils.isSafUri(destinationPath)

                val wroteRaw = if (!destinationPath.isNullOrEmpty() && !isSafPath &&
                    ScopedStorageUtils.canWriteRawPath(activity, destinationPath)
                ) {
                    val dir = File(destinationPath)
                    if (dir.exists() || dir.mkdirs()) {
                        try {
                            File(dir, fileName).writeBytes(bytes)
                            true
                        } catch (_: Exception) { false }
                    } else false
                } else false

                if (!wroteRaw) {
                    val treeDoc = ScopedStorageUtils.resolveTreeDoc(
                        activity, destinationTreeUri, destinationPath
                    ) ?: throw Exception(
                        "Could not write to the destination folder. " +
                            "Please pick a different folder or grant \"All files access\"."
                    )
                    treeDoc.findFile(fileName)?.delete()
                    val doc = treeDoc.createFile("application/octet-stream", fileName)
                        ?: throw Exception("Could not create \"$fileName\" in the destination folder")
                    activity.contentResolver.openOutputStream(doc.uri)?.use { it.write(bytes) }
                        ?: throw Exception("Could not open \"$fileName\" for writing")
                }

                activity.runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }
}