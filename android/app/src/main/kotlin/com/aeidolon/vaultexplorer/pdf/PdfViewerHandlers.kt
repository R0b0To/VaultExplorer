package com.aeidolon.vaultexplorer.pdf

import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import android.content.Context
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import java.io.FileInputStream
import java.io.FileOutputStream

class PdfViewerHandlers(
    private val activity: MainActivity,
    private val pdfExecutor: ExecutorService,
) {
    fun handleOpenPdf(call: MethodCall, result: MethodChannel.Result) {
        val localUri = call.argument<String>("localUri")
        if (localUri != null) {
            pdfExecutor.execute {
                try {
                    val opened = PdfRendererRegistry.openLocal(activity, localUri)
                    activity.runOnUiThread {
                        result.success(mapOf("handle" to opened.handle, "pageCount" to opened.pageCount))
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread { result.error("PDF_OPEN_FAILED", e.message, null) }
                }
            }
            return
        }

        val uriString = call.argument<String>("filePath")
        val fileName = call.argument<String>("fileName")
        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName (or localUri) required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container not mounted", null)
            return
        }
        pdfExecutor.execute {
            try {
                val opened = PdfRendererRegistry.open(activity, volId, fileName)
                activity.runOnUiThread {
                    result.success(mapOf("handle" to opened.handle, "pageCount" to opened.pageCount))
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("PDF_OPEN_FAILED", e.message, null) }
            }
        }
    }

    fun handleGetPdfPageSize(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<Int>("handle")
        val pageIndex = call.argument<Int>("pageIndex")
        if (handle == null || pageIndex == null) {
            result.error("INVALID_ARGS", "handle and pageIndex required", null)
            return
        }
        pdfExecutor.execute {
            try {
                val size = PdfRendererRegistry.getPageSize(handle, pageIndex)
                activity.runOnUiThread {
                    result.success(mapOf("width" to size.widthPts, "height" to size.heightPts))
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("PDF_PAGE_SIZE_FAILED", e.message, null) }
            }
        }
    }

    fun handleRenderPdfPage(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<Int>("handle")
        val pageIndex = call.argument<Int>("pageIndex")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        if (handle == null || pageIndex == null || width == null || height == null) {
            result.error("INVALID_ARGS", "handle, pageIndex, width and height required", null)
            return
        }
        pdfExecutor.execute {
            try {
                val png = PdfRendererRegistry.renderPage(handle, pageIndex, width, height)
                activity.runOnUiThread { result.success(png) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("PDF_RENDER_FAILED", e.message, null) }
            }
        }
    }

    fun handleClosePdf(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<Int>("handle")
        if (handle == null) {
            result.error("INVALID_ARGS", "handle required", null)
            return
        }
        pdfExecutor.execute {
            PdfRendererRegistry.close(handle)
            activity.runOnUiThread { result.success(null) }
        }
    }

    fun handleIsJetpackPdfViewerSupported(result: MethodChannel.Result) {
        result.success(isJetpackPdfViewerSupported())
    }

    fun handleRegisterJetpackPdfSession(call: MethodCall, result: MethodChannel.Result) {
        val localUri = call.argument<String>("localUri")
        if (localUri != null) {
            result.success(mapOf("contentUri" to localUri))
            return
        }

        val uriString = call.argument<String>("filePath")
        val fileName = call.argument<String>("fileName")
        if (uriString == null || fileName == null) {
            result.error("INVALID_ARGS", "filePath and fileName (or localUri) required", null)
            return
        }
        val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString)
        if (volId == null) {
            result.error("NOT_MOUNTED", "Container not mounted", null)
            return
        }
        val token = VaultPdfSessionRegistry.register(volId, fileName)
        val contentUri = "content://${activity.packageName}.pdfprovider/$token"
        result.success(mapOf("contentUri" to contentUri, "token" to token))
    }

    fun handlePrintPdf(call: MethodCall, result: MethodChannel.Result) {
    val uriString = call.argument<String>("filePath")
    val fileName = call.argument<String>("fileName") ?: "Document.pdf"
    val localUri = call.argument<String>("localUri")

    val printManager = activity.getSystemService(Context.PRINT_SERVICE) as? PrintManager
    if (printManager == null) {
        result.error("PRINT_FAILED", "PrintManager unavailable", null)
        return
    }

    try {
        val jobName = "${activity.getString(com.aeidolon.vaultexplorer.R.string.app_name)} - $fileName"

        printManager.print(jobName, object : PrintDocumentAdapter() {
            override fun onLayout(
                oldAttributes: PrintAttributes?,
                newAttributes: PrintAttributes,
                cancellationSignal: CancellationSignal?,
                callback: LayoutResultCallback,
                extras: Bundle?
            ) {
                if (cancellationSignal?.isCanceled == true) {
                    callback.onLayoutCancelled()
                    return
                }
                val info = PrintDocumentInfo.Builder(fileName)
                    .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                    .build()
                callback.onLayoutFinished(info, true)
            }

            override fun onWrite(
                pages: Array<out PageRange>?,
                destination: ParcelFileDescriptor,
                cancellationSignal: CancellationSignal?,
                callback: WriteResultCallback
            ) {
                pdfExecutor.execute {
                    var inputPfd: ParcelFileDescriptor? = null
                    try {
                        // Open decrypted stream straight from session registry or local URI
                        inputPfd = if (localUri != null) {
                            activity.contentResolver.openFileDescriptor(android.net.Uri.parse(localUri), "r")
                        } else {
                            val volId = ContainerSessionRegistry.getVolumeIdByUri(uriString!!)
                                ?: throw IllegalStateException("Container not mounted")
                            val token = VaultPdfSessionRegistry.register(volId, fileName)
                            VaultPdfSessionRegistry.open(activity, token)
                        }

                        if (inputPfd == null) throw IllegalStateException("Could not open source PDF stream")

                        FileInputStream(inputPfd.fileDescriptor).use { input ->
                            FileOutputStream(destination.fileDescriptor).use { output ->
                                val buffer = ByteArray(64 * 1024)
                                var bytesRead: Int
                                while (input.read(buffer).also { bytesRead = it } != -1) {
                                    if (cancellationSignal?.isCanceled == true) {
                                        activity.runOnUiThread { callback.onWriteCancelled() }
                                        return@execute
                                    }
                                    output.write(buffer, 0, bytesRead)
                                }
                            }
                        }

                        activity.runOnUiThread {
                            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                        }
                    } catch (e: Exception) {
                        activity.runOnUiThread { callback.onWriteFailed(e.message) }
                    } finally {
                        try { inputPfd?.close() } catch (_: Exception) {}
                    }
                }
            }
        }, null)

        result.success(true)
    } catch (e: Exception) {
        result.error("PRINT_FAILED", e.message, null)
    }
}

    fun handleRevokeJetpackPdfSession(call: MethodCall, result: MethodChannel.Result) {
        call.argument<String>("token")?.let { VaultPdfSessionRegistry.revoke(it) }
        result.success(null)
    }

    
}