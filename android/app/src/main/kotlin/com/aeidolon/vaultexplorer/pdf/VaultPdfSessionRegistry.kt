package com.aeidolon.vaultexplorer.pdf

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.util.Log
import com.aeidolon.vaultexplorer.ContainerFileSystem
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap


object VaultPdfSessionRegistry {
    private const val TAG = "VaultPdfSessionRegistry"

    private data class Pending(val volId: Int, val fatPath: String)
    private class OpenSession(
        val pfd: ParcelFileDescriptor,
        val handlerThread: HandlerThread,
        val volId: Int,
    )

    private val pending = ConcurrentHashMap<String, Pending>()
    private val open = ConcurrentHashMap<String, MutableList<OpenSession>>()

    /** Called from [PdfViewerHandlers.handleRegisterJetpackPdfSession] right
     *  before the Dart side creates the AndroidView. */
    fun register(volId: Int, fatPath: String): String {
        val token = UUID.randomUUID().toString()
        pending[token] = Pending(volId, fatPath)
        return token
    }

    /** Cheap metadata for [VaultPdfContentProvider.query] -- doesn't open a
     *  stream, just stats the file the same way [VaultPdfProxyCallback]
     *  does at init. Returns null for an unknown/revoked token. */
    fun stat(token: String): Pair<String, Long>? {
        val info = pending[token] ?: return null
        val size = try {
            ContainerFileSystem.withReadLock(info.volId) {
                ContainerFileSystem.getFileSize(info.volId, info.fatPath)
            }
        } catch (e: Exception) {
            -1L
        }
        return info.fatPath.substringAfterLast('/') to size
    }

    /** Runs on whatever thread the framework/fragment calls
     *  `ContentProvider.openFile` from (typically a Binder thread) --
     *  [StorageManager.openProxyFileDescriptor] itself is cheap; the actual
     *  blocking reads happen later on the dedicated [handlerThread]. */
    fun open(context: Context, token: String): ParcelFileDescriptor {
        val info = pending[token]
            ?: throw java.io.FileNotFoundException("Unknown or expired PDF session token")
        val storageManager = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
            ?: throw java.io.IOException("Could not obtain StorageManager")

        val handlerThread = HandlerThread("vault_pdf_jetpack_${info.volId}_${System.nanoTime()}").apply { start() }
        val handler = Handler(handlerThread.looper)
        try {
            val callback = VaultPdfProxyCallback(info.volId, info.fatPath, handlerThread) {
                open[token]?.removeAll { it.handlerThread === handlerThread }
            }
            val pfd = storageManager.openProxyFileDescriptor(
                ParcelFileDescriptor.MODE_READ_ONLY, callback, handler,
            )
            open.getOrPut(token) { Collections.synchronizedList(mutableListOf()) }
                .add(OpenSession(pfd, handlerThread, info.volId))
            return pfd
        } catch (e: Exception) {
            Log.e(TAG, "open: failed for PDF session token (volId=${info.volId})", e)
            runCatching { handlerThread.quitSafely() }
            throw e
        }
    }

    /** Called when the Flutter-side widget disposes. Safe to call for a
     *  token that was never actually opened (e.g. the fragment failed
     *  before ever reading it) or is already gone. */
    fun revoke(token: String) {
        pending.remove(token)
        val sessions = open.remove(token) ?: return
        for (session in sessions) {
            runCatching { session.pfd.close() }
            // VaultPdfProxyCallback.onRelease(), triggered by the pfd
            // close above tearing down the FUSE proxy, is what quits
            // handlerThread and closes the underlying
            // ContainerFileSystem stream.
        }
    }

    /** Called when a container locks -- tears down every still-registered
     *  or still-open PDF session for that volume, mirroring
     *  [PdfRendererRegistry.closeAllForVolume]. */
    fun revokeAllForVolume(volId: Int) {
        val tokens = (pending.entries.filter { it.value.volId == volId }.map { it.key } +
            open.entries.filter { it.value.any { s -> s.volId == volId } }.map { it.key }).toSet()
        for (token in tokens) revoke(token)
    }

    /** Called from [MainActivity.onDestroy] as a final safety net. */
    fun revokeAll() {
        for (token in (pending.keys + open.keys).toSet()) revoke(token)
    }
}
