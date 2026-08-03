package com.aeidolon.vaultexplorer.pdfviewer

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import com.aeidolon.vaultexplorer.ContainerFileSystem
import com.aeidolon.vaultexplorer.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.htmlviewer.VAULT_HOST
import com.aeidolon.vaultexplorer.htmlviewer.VaultAssetInputStream
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.FileNotFoundException

/** viewType used to register this platform view with Flutter. */
const val PDF_VIEWER_VIEW_TYPE = "com.aeidolon.vaultexplorer/pdf_viewer"

/** First path segment that signals "serve from Android assets/pdfjs/". */
private const val PDFJS_ASSET_PREFIX = "_pdfjs"

// ─────────────────────────────────────────────────────────────────────────────
// Factory
// ─────────────────────────────────────────────────────────────────────────────

class PdfViewerViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap<String, Any?>()
        val volId   = (params["volId"]   as? Number)?.toInt() ?: -1
        val pdfPath = params["pdfPath"]  as? String ?: ""
        return PdfViewerView(context, messenger, viewId, volId, pdfPath)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Platform view
// ─────────────────────────────────────────────────────────────────────────────

@SuppressLint("SetJavaScriptEnabled")
class PdfViewerView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val volId: Int,
    private val pdfPath: String,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val webView       = WebView(context)
    private val methodChannel = MethodChannel(messenger, "$PDF_VIEWER_VIEW_TYPE/$viewId")
    private val eventChannel  = EventChannel(messenger, "$PDF_VIEWER_VIEW_TYPE/events/$viewId")
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler   = Handler(Looper.getMainLooper())

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { eventSink = sink }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })

        with(webView.settings) {
            javaScriptEnabled                = true   // required by pdf.js
            domStorageEnabled                = true
            databaseEnabled                  = false
            allowFileAccess                  = false
            allowContentAccess               = false
            allowFileAccessFromFileURLs      = false
            allowUniversalAccessFromFileURLs = false
            blockNetworkLoads                = true   // hard OS backstop
            cacheMode                        = WebSettings.LOAD_NO_CACHE
            setGeolocationEnabled(false)
            setSupportZoom(true)
            builtInZoomControls              = true
            displayZoomControls              = false
            mixedContentMode                 = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
        }

        webView.addJavascriptInterface(JsBridge(), "VaultPdfViewer")
        webView.webViewClient  = PdfWebViewClient()
        webView.webChromeClient = WebChromeClient()

        loadViewer()
    }

    // ── URL helpers ──────────────────────────────────────────────────────────

    private fun buildVaultUri(fatPath: String): Uri {
        val builder = Uri.Builder().scheme("https").authority(VAULT_HOST)
            .appendPath(volId.toString())
        for (segment in fatPath.split("/")) {
            if (segment.isNotEmpty()) builder.appendPath(segment)
        }
        return builder.build()
    }

    private fun loadViewer() {
        if (pdfPath.isEmpty()) return
        val pdfUri    = buildVaultUri(pdfPath)
        val viewerUri = Uri.Builder()
            .scheme("https").authority(VAULT_HOST)
            .appendPath(PDFJS_ASSET_PREFIX)
            .appendPath("viewer.html")
            .appendQueryParameter("url", pdfUri.toString())
            .build()
        webView.loadUrl(viewerUri.toString())
    }

    // ── WebViewClient ────────────────────────────────────────────────────────

    private inner class PdfWebViewClient : WebViewClient() {

        override fun shouldInterceptRequest(
            view: WebView,
            request: WebResourceRequest,
        ): WebResourceResponse {
            val uri = request.url
            if (uri.scheme != "https" || uri.host != VAULT_HOST) return blockedResponse()

            val segments = uri.pathSegments
            if (segments.isEmpty()) return blockedResponse()

            // ── pdf.js assets (served from android assets/pdfjs/) ────────
            if (segments[0] == PDFJS_ASSET_PREFIX) {
                val assetPath = "pdfjs/" + segments.drop(1).joinToString("/")
                return try {
                    val stream = context.assets.open(assetPath)
                    val mime   = mimeForAsset(assetPath)
                    WebResourceResponse(mime, "utf-8", stream).also {
                        it.responseHeaders = mapOf(
                            "Cache-Control"                to "no-store",
                            "Access-Control-Allow-Origin"  to "*",
                        )
                    }
                } catch (_: Exception) { notFoundResponse() }
            }

            // ── vault file ───────────────────────────────────────────────
            val requestVolId = segments[0].toIntOrNull()
            if (requestVolId != volId || !ContainerSessionRegistry.isUnlocked(volId)) {
                return blockedResponse()
            }
            val fatPath = segments.drop(1).joinToString("/")
            if (fatPath.isEmpty() || fatPath.split("/").any { it == ".." || it.isEmpty() }) {
                return blockedResponse()
            }
            return try {
                val size   = ContainerFileSystem.getFileSize(volId, fatPath)
                val mime   = MimeTypeHelper.getMimeType(fatPath)
                val stream = VaultAssetInputStream(volId, fatPath, size)
                WebResourceResponse(mime, null, stream).also {
                    it.responseHeaders = mapOf("Cache-Control" to "no-store")
                }
            } catch (_: FileNotFoundException) { notFoundResponse()
            } catch (_: Exception)             { notFoundResponse() }
        }

        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: WebResourceRequest,
        ): Boolean {
            val uri = request.url
            return !(uri.scheme == "https" && uri.host == VAULT_HOST)
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError,
        ) {
            if (request.isForMainFrame) {
                mainHandler.post {
                    eventSink?.success(mapOf(
                        "event"   to "error",
                        "message" to (error.description?.toString()
                            ?: "Failed to load PDF viewer"),
                    ))
                }
            }
        }

        private fun blockedResponse() = WebResourceResponse(
            "text/plain", "utf-8", 403, "Blocked", emptyMap(),
            ByteArrayInputStream(ByteArray(0)),
        )
        private fun notFoundResponse() = WebResourceResponse(
            "text/plain", "utf-8", 404, "Not Found", emptyMap(),
            ByteArrayInputStream(ByteArray(0)),
        )
    }

    private fun mimeForAsset(path: String): String = when {
        path.endsWith(".html")                       -> "text/html"
        path.endsWith(".css")                        -> "text/css"
        path.endsWith(".js") || path.endsWith(".mjs") -> "text/javascript"
        else                                         -> "application/octet-stream"
    }

    // ── JavaScript → Native bridge ───────────────────────────────────────────

    @Suppress("unused")
    inner class JsBridge {
        @JavascriptInterface
        fun onDocumentLoaded(pageCount: Int) {
            mainHandler.post {
                eventSink?.success(mapOf(
                    "event"     to "documentLoaded",
                    "pageCount" to pageCount,
                ))
            }
        }

        @JavascriptInterface
        fun onPageChanged(page: Int) {
            mainHandler.post {
                eventSink?.success(mapOf(
                    "event" to "pageChanged",
                    "page"  to page,
                ))
            }
        }

        @JavascriptInterface
        fun onError(message: String) {
            mainHandler.post {
                eventSink?.success(mapOf(
                    "event"   to "error",
                    "message" to message,
                ))
            }
        }

        @JavascriptInterface
        fun onSearchResult(current: Int, total: Int) {
            mainHandler.post {
                eventSink?.success(mapOf(
                    "event"   to "searchResult",
                    "current" to current,
                    "total"   to total,
                ))
            }
        }
    }

    // ── Dart → WebView method calls ──────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "goToPage" -> {
                val page = call.argument<Int>("page") ?: 1
                webView.evaluateJavascript("goToPage($page)", null)
                result.success(null)
            }
            "search" -> {
                val query = call.argument<String>("query") ?: ""
                // JSONObject.quote produces a safely-escaped JS/JSON string
                // literal (handles quotes, backslashes, newlines in query).
                webView.evaluateJavascript(
                    "window.searchText(${JSONObject.quote(query)})", null,
                )
                result.success(null)
            }
            "findNext" -> {
                webView.evaluateJavascript("window.findNext()", null)
                result.success(null)
            }
            "findPrevious" -> {
                webView.evaluateJavascript("window.findPrevious()", null)
                result.success(null)
            }
            "clearSearch" -> {
                webView.evaluateJavascript("window.clearSearch()", null)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun getView(): View = webView

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        webView.removeJavascriptInterface("VaultPdfViewer")
        webView.webViewClient = object : WebViewClient() {}
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.destroy()
    }
}
