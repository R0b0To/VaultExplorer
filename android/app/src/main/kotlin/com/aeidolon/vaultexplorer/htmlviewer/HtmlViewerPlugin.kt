package com.aeidolon.vaultexplorer.htmlviewer

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import com.aeidolon.vaultexplorer.container.ContainerFileSystem
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.MimeTypeHelper
import com.aeidolon.vaultexplorer.reader.BookSessions
import com.aeidolon.vaultexplorer.reader.ZipReader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream
import java.io.FileNotFoundException

/** viewType every [HtmlViewerViewFactory] instance is registered under; the
 *  per-instance method/event channels below are namespaced with the
 *  platform-view id Flutter hands back from `AndroidView.onPlatformViewCreated`. */
const val HTML_VIEWER_VIEW_TYPE = "com.aeidolon.vaultexplorer/html_viewer"

/** Fixed virtual origin every in-vault request is confined to. It is never
 *  resolved over a real network connection — WebSettings.blockNetworkLoads
 *  plus the allowlist in [VaultWebViewClient.shouldInterceptRequest] make
 *  sure of that — it only exists so relative href/src/url() references in
 *  vault HTML resolve the way a browser expects. */
internal const val VAULT_HOST = "vault-local.internal"

/** Virtual origin for an open EPUB. Paths under it are `/<bookToken>/<zip entry>`
 *  and are answered from the book's [BookSessions] entry, never from a network
 *  or the file system. */
internal const val EPUB_HOST = "epub-local.internal"

/** Always injected into EPUB markup: keeps pictures and tables inside the screen
 *  and gives long words/URLs somewhere to break. Theme CSS from Dart follows it. */
private const val EPUB_BASE_CSS =
    "img,svg,video{max-width:100%!important;height:auto!important}" +
        "body{overflow-wrap:break-word}table{max-width:100%}pre{white-space:pre-wrap}"

class HtmlViewerViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap<String, Any?>()
        val volId = (params["volId"] as? Number)?.toInt() ?: -1
        val htmlPath = params["htmlPath"] as? String ?: ""
        val jsEnabled = params["javaScriptEnabled"] as? Boolean ?: false
        val bookToken = params["bookToken"] as? String
        val bookEntry = params["bookEntry"] as? String ?: ""
        val bookCss = params["bookCss"] as? String ?: ""
        val textZoom = (params["textZoom"] as? Number)?.toInt() ?: 100
        val backgroundColor = (params["backgroundColor"] as? Number)?.toInt()
        return HtmlViewerView(
            context, messenger, viewId, volId, htmlPath, jsEnabled,
            bookToken, bookEntry, bookCss, textZoom, backgroundColor,
        )
    }
}

@SuppressLint("SetJavaScriptEnabled")
class HtmlViewerView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val volId: Int,
    private val initialPath: String,
    jsEnabled: Boolean,
    /** Non-null puts the view in e-book mode: requests are served from this book session. */
    private val bookToken: String? = null,
    private val initialBookEntry: String = "",
    private var bookCss: String = "",
    initialTextZoom: Int = 100,
    initialBackgroundColor: Int? = null,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val webView = WebView(context)
    private val methodChannel = MethodChannel(messenger, "$HTML_VIEWER_VIEW_TYPE/$viewId")
    private val eventChannel = EventChannel(messenger, "$HTML_VIEWER_VIEW_TYPE/events/$viewId")
    private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { eventSink = sink }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })

        with(webView.settings) {
            javaScriptEnabled = jsEnabled
            domStorageEnabled = true
            databaseEnabled = false
            allowFileAccess = false
            allowContentAccess = false
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            // Hard OS-level backstop: even if shouldInterceptRequest below
            // ever failed to catch something, the WebView itself refuses to
            // open a real network socket.
            blockNetworkLoads = true
            cacheMode = WebSettings.LOAD_NO_CACHE
            setGeolocationEnabled(false)
            setSupportZoom(true)
            builtInZoomControls = true
            displayZoomControls = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
        }
        webView.settings.textZoom = initialTextZoom.coerceIn(50, 300)
        if (initialBackgroundColor != null) webView.setBackgroundColor(initialBackgroundColor)
        if (bookToken != null) {
            webView.setOnScrollChangeListener { _, _, _, _, _ -> scheduleScrollEvent() }
        }
        webView.webViewClient = VaultWebViewClient()
        webView.webChromeClient = WebChromeClient()
        loadInitialPage()
    }

    private fun buildVaultUri(fatPath: String): Uri {
        val builder = Uri.Builder()
            .scheme("https")
            .authority(VAULT_HOST)
            .appendPath(volId.toString())
        for (segment in fatPath.split("/")) {
            if (segment.isNotEmpty()) builder.appendPath(segment)
        }
        return builder.build()
    }

    private fun loadInitialPage() {
        if (bookToken != null) {
            if (initialBookEntry.isNotEmpty()) webView.loadUrl(buildBookUri(initialBookEntry, "").toString())
            return
        }
        if (initialPath.isEmpty()) return
        webView.loadUrl(buildVaultUri(initialPath).toString())
    }

    private fun buildBookUri(entryPath: String, fragment: String): Uri {
        val builder = Uri.Builder()
            .scheme("https")
            .authority(EPUB_HOST)
            .appendPath(bookToken ?: "")
        for (segment in entryPath.split("/")) {
            if (segment.isNotEmpty()) builder.appendPath(segment)
        }
        if (fragment.isNotEmpty()) builder.fragment(fragment)
        return builder.build()
    }

    // -- e-book scroll progress (the reader shows it and offers the next chapter at the end) --

    private var scrollEventPending = false

    private fun scheduleScrollEvent() {
        if (scrollEventPending) return
        scrollEventPending = true
        webView.postDelayed({
            scrollEventPending = false
            emitScrollEvent()
        }, 120)
    }

    private fun emitScrollEvent() {
        val contentPx = (webView.contentHeight * webView.resources.displayMetrics.density).toInt()
        val travel = (contentPx - webView.height).coerceAtLeast(1)
        val fraction = (webView.scrollY.toFloat() / travel).coerceIn(0f, 1f)
        eventSink?.success(
            mapOf(
                "event" to "scroll",
                "fraction" to fraction.toDouble(),
                "atStart" to !webView.canScrollVertically(-1),
                "atEnd" to !webView.canScrollVertically(1),
            )
        )
    }

    private fun bookMime(path: String): String {
        val lower = path.lowercase()
        return when {
            lower.endsWith(".xhtml") || lower.endsWith(".xht") -> "application/xhtml+xml"
            lower.endsWith(".html") || lower.endsWith(".htm") -> "text/html"
            else -> MimeTypeHelper.getMimeType(path)
        }
    }

    private fun injectBookStyle(bytes: ByteArray): ByteArray {
        val text = String(bytes, Charsets.UTF_8)
        val tag = "<style type=\"text/css\">" + EPUB_BASE_CSS + bookCss + "</style>"
        val head = text.indexOf("</head>", ignoreCase = true)
        val at = if (head >= 0) head else {
            val body = text.indexOf("<body", ignoreCase = true)
            if (body >= 0) body else return bytes
        }
        return (text.substring(0, at) + tag + text.substring(at)).toByteArray(Charsets.UTF_8)
    }

    private fun interceptBookRequest(request: WebResourceRequest): WebResourceResponse {
        val uri = request.url
        if (uri.scheme != "https" || uri.host != EPUB_HOST) return blockedResponse()
        val segments = uri.pathSegments.filter { it.isNotEmpty() }
        if (segments.size < 2 || segments[0] != bookToken) return blockedResponse()
        val entryParts = segments.drop(1)
        if (entryParts.any { it == ".." || it == "." }) return blockedResponse()
        val session = BookSessions.get(bookToken) ?: return notFoundResponse()
        val entry = session.directory.find(entryParts.joinToString("/")) ?: return notFoundResponse()
        return try {
            var bytes = ZipReader.readEntry(session.source, entry)
            val mime = bookMime(entry.name)
            val markup = mime == "application/xhtml+xml" || mime == "text/html"
            if (markup) bytes = injectBookStyle(bytes)
            val textual = markup || mime.startsWith("text/") || mime == "image/svg+xml" || mime.endsWith("xml")
            WebResourceResponse(mime, if (textual) "utf-8" else null, ByteArrayInputStream(bytes)).also {
                it.responseHeaders = mapOf("Cache-Control" to "no-store")
            }
        } catch (e: Exception) {
            notFoundResponse()
        }
    }

    private fun blockedResponse(): WebResourceResponse = WebResourceResponse(
        "text/plain", "utf-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(ByteArray(0))
    )

    private fun notFoundResponse(): WebResourceResponse = WebResourceResponse(
        "text/plain", "utf-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0))
    )

    private inner class VaultWebViewClient : WebViewClient() {

        override fun shouldInterceptRequest(
            view: WebView,
            request: WebResourceRequest,
        ): WebResourceResponse {
            if (bookToken != null) return interceptBookRequest(request)
            val uri = request.url
            if (uri.scheme != "https" || uri.host != VAULT_HOST) {
                return blockedResponse()
            }
            val segments = uri.pathSegments
            if (segments.isEmpty()) return blockedResponse()
            val requestVolId = segments[0].toIntOrNull()
            if (requestVolId != volId || !ContainerSessionRegistry.isUnlocked(volId)) {
                return blockedResponse()
            }
            val fatPath = segments.drop(1).joinToString("/")
            val parts = fatPath.split("/")
            if (fatPath.isEmpty() || parts.any { it == ".." || it.isEmpty() }) {
                return blockedResponse()
            }
            return try {
                val size = ContainerFileSystem.getFileSize(volId, fatPath)
                val mime = MimeTypeHelper.getMimeType(fatPath)
                val stream = VaultAssetInputStream(volId, fatPath, size)
                WebResourceResponse(mime, null, stream).also {
                    it.responseHeaders = mapOf("Cache-Control" to "no-store")
                }
            } catch (e: FileNotFoundException) {
                notFoundResponse()
            } catch (e: Exception) {
                notFoundResponse()
            }
        }

        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: WebResourceRequest,
        ): Boolean {
            val uri = request.url
            // Only navigation within our own virtual origin is ever allowed
            // to proceed; anything else (real http/https, mailto:, intent:,
            // market:, etc.) is swallowed right here so it can never leave
            // the app or reach the network.
            if (bookToken != null) {
                return !(uri.scheme == "https" && uri.host == EPUB_HOST &&
                    uri.pathSegments.firstOrNull() == bookToken)
            }
            return !(uri.scheme == "https" && uri.host == VAULT_HOST)
        }

        override fun onPageFinished(view: WebView, url: String?) {
            eventSink?.success(
                mapOf(
                    "event" to "pageFinished",
                    "title" to view.title,
                    "canGoBack" to view.canGoBack(),
                    "canGoForward" to view.canGoForward(),
                    "url" to (url ?: ""),
                    "entry" to bookEntryOf(url),
                )
            )
            if (bookToken != null) emitScrollEvent()
        }

        private fun bookEntryOf(url: String?): String {
            if (bookToken == null || url == null) return ""
            return Uri.parse(url).pathSegments.filter { it.isNotEmpty() }.drop(1).joinToString("/")
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError,
        ) {
            if (request.isForMainFrame) {
                eventSink?.success(
                    mapOf(
                        "event" to "error",
                        "message" to error.description?.toString(),
                    )
                )
            }
        }

    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "goBack" -> {
                if (webView.canGoBack()) webView.goBack()
                result.success(null)
            }
            "goForward" -> {
                if (webView.canGoForward()) webView.goForward()
                result.success(null)
            }
            "reload" -> {
                webView.reload()
                result.success(null)
            }
            "stopLoading" -> {
                webView.stopLoading()
                result.success(null)
            }
            "loadEntry" -> {
                val entry = call.argument<String>("entry") ?: ""
                val fragment = call.argument<String>("fragment") ?: ""
                if (bookToken != null && entry.isNotEmpty()) {
                    webView.loadUrl(buildBookUri(entry, fragment).toString())
                }
                result.success(null)
            }
            "setTextZoom" -> {
                webView.settings.textZoom = (call.argument<Number>("percent")?.toInt() ?: 100).coerceIn(50, 300)
                result.success(null)
            }
            "setBookStyle" -> {
                bookCss = call.argument<String>("css") ?: ""
                call.argument<Number>("backgroundColor")?.toInt()?.let { webView.setBackgroundColor(it) }
                webView.reload()
                result.success(null)
            }
            "pageScroll" -> {
                // One screenful, for the reader's page buttons; false when already at the end.
                val down = call.argument<Boolean>("down") ?: true
                val moved = if (down) webView.pageDown(false) else webView.pageUp(false)
                result.success(moved)
            }
            "setJavaScriptEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                webView.settings.javaScriptEnabled = enabled
                webView.reload()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun getView(): View = webView

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        webView.webViewClient = object : WebViewClient() {}
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.destroy()
    }
}
