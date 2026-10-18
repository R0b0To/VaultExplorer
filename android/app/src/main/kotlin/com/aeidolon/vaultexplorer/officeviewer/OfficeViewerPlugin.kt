package com.aeidolon.vaultexplorer.officeviewer

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import com.aeidolon.vaultexplorer.VeLog
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** viewType of the Office / OpenDocument preview; per-instance channels are namespaced with the view id. */
const val OFFICE_VIEWER_VIEW_TYPE = "com.aeidolon.vaultexplorer/office_viewer"

/** Virtual origin the converted page is served from. It never resolves over a network. */
private const val DOC_HOST = "office-local.internal"
private const val INDEX_URL = "https://$DOC_HOST/__doc__/index.html"
private const val RES_PREFIX = "/__doc__/"
private const val TAG = "OfficeViewer"

private const val CSP = "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'"

class OfficeViewerViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        OfficeViewerView(context, messenger, viewId)
}

/**
 * Renders a converted Office document. By construction this view can reach
 * nothing but the in-memory page and its images:
 *  - JavaScript, DOM storage, file and content access are all off;
 *  - the WebView is not allowed to open network sockets;
 *  - [shouldInterceptRequest] serves only the page and its images (under the
 *    virtual /__doc__/r/ folder) from memory and answers 403 to everything else;
 *  - link navigation is swallowed, and the page itself carries a strict CSP.
 * The decrypted document bytes are handed in over the method channel, converted
 * on a background thread, and never written to disk.
 */
@SuppressLint("SetJavaScriptEnabled")
class OfficeViewerView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val webView = WebView(context)
    private val methodChannel = MethodChannel(messenger, "$OFFICE_VIEWER_VIEW_TYPE/$viewId")
    private val eventChannel = EventChannel(messenger, "$OFFICE_VIEWER_VIEW_TYPE/events/$viewId")
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "office-convert").apply { isDaemon = true }
    }

    @Volatile private var disposed = false
    private var pageBytes: ByteArray? = null
    private var resources: Map<String, DocResource> = emptyMap()

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { eventSink = sink }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })
        with(webView.settings) {
            javaScriptEnabled = false
            domStorageEnabled = false
            databaseEnabled = false
            allowFileAccess = false
            allowContentAccess = false
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            blockNetworkLoads = true
            cacheMode = WebSettings.LOAD_NO_CACHE
            setGeolocationEnabled(false)
            setSupportZoom(true)
            builtInZoomControls = true
            displayZoomControls = false
            setSupportMultipleWindows(false)
            useWideViewPort = true
            loadWithOverviewMode = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
        }
        webView.webViewClient = DocWebViewClient()
        webView.webChromeClient = WebChromeClient()
    }

    private inner class DocWebViewClient : WebViewClient() {
        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
            val uri = request.url
            if (uri.scheme != "https" || uri.host != DOC_HOST || request.method != "GET") return blocked()
            val path = uri.path ?: return blocked()
            if (path == "/__doc__/index.html") {
                val bytes = pageBytes ?: return notFound()
                return WebResourceResponse("text/html", "utf-8", 200, "OK", headers(), ByteArrayInputStream(bytes))
            }
            if (path.startsWith(RES_PREFIX)) {
                val res = resources[path.removePrefix(RES_PREFIX)] ?: return notFound()
                return WebResourceResponse(res.mime, null, 200, "OK", headers(), ByteArrayInputStream(res.bytes))
            }
            return blocked()
        }

        // The converted page contains no real links; swallow every navigation attempt.
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true

        override fun onPageFinished(view: WebView, url: String?) {
            if (url == INDEX_URL) eventSink?.success(mapOf("event" to "pageFinished"))
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (request.isForMainFrame) {
                eventSink?.success(mapOf("event" to "error", "message" to error.description?.toString()))
            }
        }

        private fun headers() = mapOf(
            "Cache-Control" to "no-store",
            "Content-Security-Policy" to CSP,
            "X-Content-Type-Options" to "nosniff",
        )

        private fun blocked() = WebResourceResponse(
            "text/plain", "utf-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(ByteArray(0)),
        )

        private fun notFound() = WebResourceResponse(
            "text/plain", "utf-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0)),
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadDocument" -> loadDocument(call, result)
            else -> result.notImplemented()
        }
    }

    private fun loadDocument(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val extension = call.argument<String>("extension") ?: ""
        if (bytes == null || bytes.isEmpty()) {
            result.error(OfficeError.UNSUPPORTED.name, "no document bytes", null)
            return
        }
        val opts = ViewOptions(
            dark = call.argument<Boolean>("dark") ?: false,
            background = call.argument<String>("background"),
            foreground = call.argument<String>("foreground"),
            muted = call.argument<String>("muted"),
            accent = call.argument<String>("accent"),
            notesLabel = call.argument<String>("notesLabel") ?: "Notes",
        )
        runCatching { webView.setBackgroundColor(Color.parseColor(opts.background)) }
        executor.execute {
            try {
                val doc = OfficeDocumentConverter.convert(bytes, extension, opts)
                val html = doc.html.toByteArray(Charsets.UTF_8)
                mainHandler.post {
                    if (disposed) return@post
                    pageBytes = html
                    resources = doc.resources
                    webView.loadUrl(INDEX_URL)
                    result.success(mapOf("title" to doc.title))
                }
            } catch (e: OfficeException) {
                VeLog.w(TAG, e) { "conversion rejected (${e.error})" }
                mainHandler.post { if (!disposed) result.error(e.error.name, e.message, null) }
            } catch (t: Throwable) {
                VeLog.e(TAG, t) { "conversion failed" }
                mainHandler.post { if (!disposed) result.error(OfficeError.UNSUPPORTED.name, t.javaClass.simpleName, null) }
            }
        }
    }

    override fun getView(): View = webView

    override fun dispose() {
        disposed = true
        executor.shutdownNow()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        pageBytes = null
        resources = emptyMap()
        webView.webViewClient = object : WebViewClient() {}
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.destroy()
    }
}
