package com.aeidolon.vaultexplorer.saf

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.aeidolon.vaultexplorer.VeLog
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

class MirrorPushException(message: String, cause: Throwable? = null) : Exception(message, cause)

class MirrorSyncCoordinator(
    private val context: Context,
    sessionTag: String,
    val realOps: SafDocumentOps,
) {
    val mirrorRoot: File = File(File(context.filesDir, "vault_mirrors"), sessionTag)
    private val uriToMirror = ConcurrentHashMap<String, File>()
    private val listedFolders = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private val pulledContent = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    // Mirror-file absolute paths with a local write in flight that hasn't
    // been pushed back to the real SAF tree yet. See markPendingLocalWrite()
    // and its call sites (CryptomatorSession/GocryptfsSession
    // getOrCreatePhysicalFileForWrite) for the full story: pulledContent
    // means "mirror and real are in sync", and it gets set the moment ANY
    // push succeeds -- including the very first, empty-placeholder push a
    // brand-new file gets at creation time, before its real content has
    // even been written. If something forces a directory re-listing
    // (pullListingIfMissing, below) while a raw-I/O writer is still filling
    // in that content -- e.g. a batched import that deliberately defers its
    // content push until endBatchWrite, with an intervening
    // setLastModifiedTime call that resolves the parent directory -- the
    // stale pulledContent flag makes the reconciliation logic read "the
    // real file changed under us, re-pull it" from what is actually just
    // the real file not having the new content yet. That deletes and
    // recreates the mirror file empty, destroying the pending write with
    // no error raised anywhere (confirmed via production MirrorTrace logs:
    // a raw java.io.File(path).length() on the mirror path reads the
    // correct, just-written size right after the write, then reads back 0
    // once endBatchWrite finally pushes -- with nothing in between except
    // exactly this reconciliation path running). A path in this set always
    // overrides a stale pulledContent flag.
    private val pendingLocalWrites = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    fun markPendingLocalWrite(mirrored: File) {
        pendingLocalWrites.add(mirrored.absolutePath)
    }

    fun reset(realVaultRoot: DocumentFile) {
        if (mirrorRoot.exists()) mirrorRoot.deleteRecursively()
        mirrorRoot.mkdirs()
        uriToMirror.clear()
        listedFolders.clear()
        pulledContent.clear()
        pendingLocalWrites.clear()
        val rootMirror = File(mirrorRoot, "root")
        rootMirror.mkdirs()
        uriToMirror[realVaultRoot.uri.toString()] = rootMirror
    }

    fun teardown() {
        uriToMirror.clear()
        listedFolders.clear()
        pulledContent.clear()
        pendingLocalWrites.clear()
        try {
            mirrorRoot.deleteRecursively()
        } catch (e: Exception) {
            VeLog.e("MirrorSyncCoordinator", e) { "teardown failed to delete mirror at ${mirrorRoot.absolutePath}" }
        }
    }

    private fun sanitizedMirrorName(name: String?): String {
        val unsafe = name.isNullOrEmpty() ||
            name == "." || name == ".." ||
            name.contains(File.separatorChar) || name.contains('\u0000')
        if (!unsafe) return name!!
        VeLog.w("MirrorSyncCoordinator") { "Unsafe SAF display name for mirroring (len=${name?.length ?: 0}), falling back to a hashed name" }
        val digest = MessageDigest.getInstance("SHA-256").digest((name ?: "").toByteArray(Charsets.UTF_8))
        return "_" + digest.joinToString("") { "%02x".format(it) }
    }

    private fun mirrorChildFor(realDoc: DocumentFile, mirroredParent: File, isDirectory: Boolean): File {
        val key = realDoc.uri.toString()
        val existing = uriToMirror[key]
        val expectedName = sanitizedMirrorName(realDoc.name)
        if (existing != null) {
            if (existing.name == expectedName && existing.parentFile == mirroredParent) {
                return existing
            }
            pulledContent.remove(key)
            try { existing.deleteRecursively() } catch (_: Exception) {}
        }
        val mirrored = File(mirroredParent, expectedName)
        // Some SAF providers (Google Drive's in particular) can hand back a
        // provisional document URI from createDocument()/DocumentsContract
        // and then report a different, canonical URI for that same
        // document on a subsequent listing query. When that happens this
        // is really the same file getting a new key, not a new child --
        // but any old key(s) still pointing at this exact File would
        // otherwise survive into the stale-entry sweep in
        // pullListingIfMissing() below and have their target deleted,
        // since that sweep only knows to keep keys present in the fresh
        // listing. Migrate registration (and any already-pulled marker) to
        // the new key instead of leaving the old one behind to be treated
        // as stale.
        if (existing == null) {
            val aliasKeys = uriToMirror.entries.filter { it.value == mirrored }.map { it.key }
            for (aliasKey in aliasKeys) {
                uriToMirror.remove(aliasKey)
                if (pulledContent.remove(aliasKey)) pulledContent.add(key)
            }
        }
        uriToMirror[key] = mirrored
        return mirrored
    }

    fun registerExisting(realDoc: DocumentFile, mirrored: File) {
        uriToMirror[realDoc.uri.toString()] = mirrored
    }

    fun realUriFor(mirrored: File): Uri? =
        uriToMirror.entries.firstOrNull { it.value == mirrored }?.key?.let { Uri.parse(it) }

    fun hasContent(realDoc: DocumentFile): Boolean = pulledContent.contains(realDoc.uri.toString())

    fun pullFileIfMissing(realDoc: DocumentFile): File {
        val key = realDoc.uri.toString()
        val mirrored = uriToMirror[key]
            ?: throw SafIOException("pullFileIfMissing: no mirror mapping for ${realDoc.uri}")
        if (pulledContent.contains(key)) {
            VeLog.d("MirrorTrace") { "pullFileIfMissing: uri=$key already pulled, mirrorLength=${mirrored.length()}" }
            return mirrored
        }
        VeLog.d("MirrorTrace") { "pullFileIfMissing: uri=$key not yet pulled, fetching from real SAF" }
        mirrored.parentFile?.mkdirs()
        val tmp = File(mirrored.parentFile, mirrored.name + ".pulling")
        var bytesCopied = 0L
        context.contentResolver.openInputStream(realDoc.uri)?.use { input ->
            tmp.outputStream().use { out -> bytesCopied = input.copyTo(out) }
        } ?: throw SafIOException("pullFileIfMissing: could not open ${realDoc.uri} for reading")
        if (!tmp.renameTo(mirrored)) {
            tmp.delete()
            throw SafIOException("pullFileIfMissing: could not finalize pulled file for ${realDoc.uri}")
        }
        pulledContent.add(key)
        VeLog.d("MirrorTrace") { "pullFileIfMissing: uri=$key pulled bytesCopied=$bytesCopied mirrorLengthAfter=${mirrored.length()}" }
        return mirrored
    }

    fun pullListingIfMissing(realFolder: DocumentFile, mirroredParent: File): List<Pair<DocumentFile, File>> {
        val key = realFolder.uri.toString()
        mirroredParent.mkdirs()
        val realChildren = realOps.listChildren(realFolder)
        val realUris = realChildren.map { it.uri.toString() }.toSet()
        val children = realChildren.map { child ->
            val childKey = child.uri.toString()
            val mirrored = mirrorChildFor(child, mirroredParent, isDirectory = child.isDirectory)
            if (child.isDirectory) {
                if (!mirrored.exists()) mirrored.mkdirs()
            } else {
                if (!mirrored.exists()) {
                    mirrored.parentFile?.mkdirs()
                    mirrored.createNewFile()
                }
                if (pulledContent.contains(childKey) && mirrored.absolutePath !in pendingLocalWrites) {
                    val realLen = child.length()
                    val realMod = child.lastModified()
                    if (mirrored.length() != realLen || (realMod > 0 && mirrored.lastModified() != realMod)) {
                        pulledContent.remove(childKey)
                        mirrored.delete()
                        mirrored.createNewFile()
                    }
                }
            }
            child to mirrored
        }
        val staleKeys = uriToMirror.entries
            .filter { (uri, file) -> file.parentFile == mirroredParent && uri !in realUris }
            .map { it.key }
        for (staleKey in staleKeys) {
            val staleFile = uriToMirror.remove(staleKey) ?: continue
            pulledContent.remove(staleKey)
            listedFolders.remove(staleKey)
            VeLog.d("MirrorTrace") { "pullListingIfMissing: removing stale mirror entry uri=$staleKey path=${staleFile.absolutePath}" }
            try {
                staleFile.deleteRecursively()
            } catch (e: Exception) {
                VeLog.w("MirrorTrace", e) { "pullListingIfMissing: failed to delete stale mirror entry ${staleFile.absolutePath}" }
            }
        }
        listedFolders.add(key)
        return children
    }

    fun hasListed(realFolder: DocumentFile): Boolean = listedFolders.contains(realFolder.uri.toString())

    fun markListedEmpty(realFolder: DocumentFile) {
        listedFolders.add(realFolder.uri.toString())
    }

    fun invalidateListing(realFolder: DocumentFile) {
        val key = realFolder.uri.toString()
        listedFolders.remove(key)
        realOps.invalidate(realFolder)
    }

    fun invalidateAll() {
        listedFolders.clear()
        realOps.invalidateAll()
    }

    fun pushFileWrite(mirrored: File, realParent: DocumentFile?, existingRealDoc: DocumentFile?, displayName: String, mimeType: String) {
        // Defensive re-stat with a short retry -- but only when
        // existingRealDoc is non-null, i.e. this push is expected to carry
        // real content (a completed write being synced back to an already-
        // existing real file). For a brand-new file (existingRealDoc ==
        // null) this is the empty-placeholder push made at creation time,
        // before any content has been written -- 0 bytes is the correct,
        // expected value there, not a race to retry around. Retrying
        // anyway cost every single newly-created file up to ~300ms of pure
        // sleep for a result that could never change: confirmed against
        // production MirrorTrace logs, where every retry on a fresh
        // placeholder read back the same genuine 0.
        var observedLength = mirrored.length()
        if (existingRealDoc != null && observedLength == 0L && mirrored.exists()) {
            for (attempt in 1..5) {
                Thread.sleep(20L * attempt)
                val recheck = mirrored.length()
                VeLog.w("MirrorTrace") { "pushFileWrite: displayName=$displayName mirroredLength read 0 on first stat, retry $attempt -> $recheck" }
                if (recheck > 0L) {
                    observedLength = recheck
                    break
                }
            }
        }
        VeLog.d("MirrorTrace") { "pushFileWrite: displayName=$displayName mirroredPath=${mirrored.absolutePath} mirroredLength=$observedLength existingRealDoc=${existingRealDoc?.uri}" }
        try {
            val target = existingRealDoc ?: run {
                val parent = realParent ?: throw MirrorPushException("pushFileWrite: no real parent for new file $displayName")
                realOps.createFileSafe(parent, mimeType, displayName)
                    ?: throw MirrorPushException("pushFileWrite: could not create $displayName on real SAF tree")
            }
            var bytesCopied = 0L
            context.contentResolver.openOutputStream(target.uri, "wt")?.use { out ->
                mirrored.inputStream().use { input -> bytesCopied = input.copyTo(out) }
            } ?: throw MirrorPushException("pushFileWrite: could not open ${target.uri} for writing")
            registerExisting(target, mirrored)
            pulledContent.add(target.uri.toString())
            pendingLocalWrites.remove(mirrored.absolutePath)
            if (bytesCopied == 0L && observedLength > 0L) {
                // The retry above saw real content moments before the
                // actual copy, but the copy itself still moved 0 bytes --
                // this is now a genuinely inconsistent state worth failing
                // loudly on rather than silently leaving a 0-byte file on
                // real storage.
                throw MirrorPushException("pushFileWrite: copied 0 bytes for $displayName despite mirror showing ${observedLength} bytes moments earlier")
            }
        } catch (e: MirrorPushException) {
            VeLog.e("MirrorTrace", e) { "pushFileWrite: displayName=$displayName FAILED" }
            throw e
        } catch (e: Exception) {
            VeLog.e("MirrorTrace", e) { "pushFileWrite: displayName=$displayName FAILED" }
            throw MirrorPushException("pushFileWrite failed for $displayName", e)
        }
    }

    fun pushCreateDirectory(realParent: DocumentFile, name: String): DocumentFile {
        return realOps.createDirectorySafe(realParent, name)
            ?: throw MirrorPushException("pushCreateDirectory: could not create $name on real SAF tree")
    }

    fun pushRename(realDoc: DocumentFile, newName: String, realParent: DocumentFile?): DocumentFile {
        try {
            return realOps.renameDocumentAndGet(realDoc, newName, realParent)
        } catch (e: Exception) {
            throw MirrorPushException("pushRename failed for ${realDoc.uri} -> $newName", e)
        }
    }

    fun pushMove(realDoc: DocumentFile, realOldParent: DocumentFile, realNewParent: DocumentFile) {
        try {
            realOps.movePhysicalDocument(realDoc, realOldParent, realNewParent)
        } catch (e: Exception) {
            throw MirrorPushException("pushMove failed for ${realDoc.uri}", e)
        }
    }

    fun pushDelete(realDoc: DocumentFile) {
        try {
            realOps.deleteRecursively(realDoc)
        } catch (e: Exception) {
            throw MirrorPushException("pushDelete failed for ${realDoc.uri}", e)
        } finally {
            val key = realDoc.uri.toString()
            uriToMirror.remove(key)?.let { pendingLocalWrites.remove(it.absolutePath) }
            pulledContent.remove(key)
        }
    }
}