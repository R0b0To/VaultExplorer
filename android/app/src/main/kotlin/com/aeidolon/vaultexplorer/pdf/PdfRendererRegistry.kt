package com.aeidolon.vaultexplorer.pdf

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.util.Log
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger


object PdfRendererRegistry {
    private const val TAG = "PdfRendererRegistry"

    private class OpenDoc(
        val renderer: PdfRenderer,
        val pfd: ParcelFileDescriptor,
        val handlerThread: HandlerThread?,
        val executor: ExecutorService,
        val volId: Int?,
    )

    private val nextHandle = AtomicInteger(1)
    private val openDocs = ConcurrentHashMap<Int, OpenDoc>()

    data class OpenResult(val handle: Int, val pageCount: Int)
    data class PageSize(val widthPts: Int, val heightPts: Int)

    /** Runs on the calling (background) thread -- opening the proxy fd and
     *  constructing PdfRenderer both do blocking I/O/JNI work. */
    fun open(context: Context, volId: Int, fatPath: String): OpenResult {
        val storageManager = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
            ?: throw java.io.IOException("Could not obtain StorageManager")

        val handlerThread = HandlerThread("vault_pdf_${volId}_${System.nanoTime()}").apply { start() }
        val handler = Handler(handlerThread.looper)

        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        var releasedByCallback = false
        try {
            val callback = VaultPdfProxyCallback(volId, fatPath, handlerThread) {
                releasedByCallback = true
            }
            pfd = storageManager.openProxyFileDescriptor(
                ParcelFileDescriptor.MODE_READ_ONLY, callback, handler,
            )
            renderer = PdfRenderer(pfd)

            val handle = nextHandle.getAndIncrement()
            val executor = Executors.newSingleThreadExecutor()
            openDocs[handle] = OpenDoc(renderer, pfd, handlerThread, executor, volId)
            return OpenResult(handle, renderer.pageCount)
        } catch (e: Exception) {
            Log.e(TAG, "open: failed for $fatPath (volId=$volId)", e)
            runCatching { renderer?.close() }
            // If the proxy callback already released itself (e.g. init
            // failure inside VaultPdfProxyCallback), closing pfd again
            // would double-release the handler thread.
            if (!releasedByCallback) runCatching { pfd?.close() }
            else runCatching { handlerThread.quitSafely() }
            throw e
        }
    }

    /** Opens a PDF that isn't inside a vault -- a plain local `file://` path
     *  or a SAF `content://` Uri the app already has a grant for. No
     *  [VaultPdfProxyCallback] involved: the fd comes straight from the
     *  filesystem or [android.content.ContentResolver]. Kept in the same
     *  registry as [open] so the Dart-side render/close calls don't need to
     *  know which path a handle came from. */
    fun openLocal(context: Context, uriString: String): OpenResult {
        val uri = android.net.Uri.parse(uriString)
        val pfd: ParcelFileDescriptor = if (uri.scheme == null || uri.scheme == "file") {
            val path = uri.path ?: uriString
            ParcelFileDescriptor.open(java.io.File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        } else {
            context.contentResolver.openFileDescriptor(uri, "r")
                ?: throw java.io.IOException("Could not open $uriString")
        }

        var renderer: PdfRenderer? = null
        try {
            renderer = PdfRenderer(pfd)
            val handle = nextHandle.getAndIncrement()
            val executor = Executors.newSingleThreadExecutor()
            openDocs[handle] = OpenDoc(renderer, pfd, handlerThread = null, executor, volId = null)
            return OpenResult(handle, renderer.pageCount)
        } catch (e: Exception) {
            Log.e(TAG, "openLocal: failed for $uriString", e)
            runCatching { renderer?.close() }
            runCatching { pfd.close() }
            throw e
        }
    }

    /** Every call below is dispatched onto the handle's own single-thread
     *  executor and blocks the caller until it completes, since PdfRenderer
     *  requires all access -- including from different Dart-triggered
     *  calls -- to be serialized and single-page-at-a-time. */
    private fun <T> runOnDocExecutor(handle: Int, block: (OpenDoc) -> T): T {
        val doc = openDocs[handle] ?: throw java.io.IOException("Unknown PDF handle $handle")
        return doc.executor.submit<T> { block(doc) }.get()
    }

    fun getPageCount(handle: Int): Int = runOnDocExecutor(handle) { it.renderer.pageCount }

    fun getPageSize(handle: Int, pageIndex: Int): PageSize = runOnDocExecutor(handle) { doc ->
        doc.renderer.openPage(pageIndex).use { page ->
            PageSize(page.width, page.height)
        }
    }

    /** Renders [pageIndex] at [widthPx] x [heightPx] and returns PNG bytes. */
    fun renderPage(handle: Int, pageIndex: Int, widthPx: Int, heightPx: Int): ByteArray =
        runOnDocExecutor(handle) { doc ->
            val w = widthPx.coerceAtLeast(1)
            val h = heightPx.coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE)
            doc.renderer.openPage(pageIndex).use { page ->
                val matrix = Matrix().apply {
                    setScale(w.toFloat() / page.width, h.toFloat() / page.height)
                }
                page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            }
            val out = ByteArrayOutputStream(w * h / 2)
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        }

    fun close(handle: Int) {
        val doc = openDocs.remove(handle) ?: return
        doc.executor.execute {
            runCatching { doc.renderer.close() }
            runCatching { doc.pfd.close() }
            // For vault-backed docs, VaultPdfProxyCallback.onRelease() is
            // what actually quits the handler thread (triggered by
            // pfd.close() above tearing down the proxy fd); nothing to do
            // here for those. openLocal() never created one.
        }
        doc.executor.shutdown()
    }

    /** Called when a container locks -- tears down every PDF handle still
     *  open against that volume so nothing keeps calling into
     *  [com.aeidolon.vaultexplorer.ContainerFileSystem] once the session
     *  underneath it is gone. */
    fun closeAllForVolume(volId: Int) {
        val handles = openDocs.entries.filter { it.value.volId != null && it.value.volId == volId }.map { it.key }
        for (handle in handles) close(handle)
    }

    /** Called from [MainActivity.onDestroy] as a final safety net. */
    fun closeAll() {
        for (handle in openDocs.keys.toList()) close(handle)
    }
}
