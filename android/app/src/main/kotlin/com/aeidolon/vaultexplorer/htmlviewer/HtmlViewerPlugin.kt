package com.aeidolon.vaultexplorer.htmlviewer

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.animation.DecelerateInterpolator
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
import kotlin.math.roundToInt

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
private const val EPUB_FIXED_CSS =
    "img,svg,video{max-width:100%;max-height:100%}"

private class ReaderWebView(context: Context) : WebView(context) {
    var pagedMode: Boolean = false
    var rightToLeft: Boolean = false
    var twoPageLandscape: Boolean = false
    var onPageTurn: ((Int) -> Unit)? = null
    var onPageLayoutChanged: (() -> Unit)? = null

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var downPage = 0
    private var pagingGesture = false
    private var horizontalPageGesture = false
    private var wasHorizontalSpread = false
    private var pageAnimator: ValueAnimator? = null
    private var pageAnimatorTargetOffset: Int? = null

    fun horizontalScrollRange(): Int = computeHorizontalScrollRange()

    fun isHorizontalPaging(): Boolean = pagedMode

    private fun pageViewport(): Int = if (isHorizontalPaging()) width else height

    private fun pageContentRange(): Int = if (isHorizontalPaging()) {
        horizontalScrollRange()
    } else {
        (contentHeight * resources.displayMetrics.density).toInt()
    }

    fun cancelPageAnimation(settleToTarget: Boolean = false) {
        val targetOffset = pageAnimatorTargetOffset
        pageAnimator?.cancel()
        pageAnimator = null
        pageAnimatorTargetOffset = null
        if (settleToTarget && targetOffset != null) scrollTo(targetOffset, 0)
    }

    fun turnPage(direction: Int, rightToLeft: Boolean) {
        val viewport = pageViewport().coerceAtLeast(1)
        val offset = if (isHorizontalPaging()) {
            pageAnimatorTargetOffset ?: scrollX
        } else {
            pageAnimatorTargetOffset ?: scrollY
        }
        val currentPage = (offset.toFloat() / viewport).roundToInt()
        val progression = if (rightToLeft) -1 else 1
        scrollToPage(currentPage + direction * progression, animate = true)
    }

    private fun scrollToPage(page: Int, animate: Boolean = false) {
        val horizontal = isHorizontalPaging()
        val viewport = pageViewport()
        if (viewport <= 0) return
        val maxOffset = (pageContentRange() - viewport).coerceAtLeast(0)
        val offset = (page * viewport).coerceIn(0, maxOffset)
        val current = if (horizontal) scrollX else scrollY
        cancelPageAnimation()
        if (!animate || current == offset) {
            scrollTo(if (horizontal) offset else 0, if (horizontal) 0 else offset)
            return
        }
        pageAnimator = ValueAnimator.ofInt(current, offset).apply {
            duration = 240
            interpolator = DecelerateInterpolator(1.4f)
            pageAnimatorTargetOffset = offset
            addUpdateListener { animation ->
                val value = animation.animatedValue as Int
                scrollTo(if (horizontal) value else 0, if (horizontal) 0 else value)
            }
            start()
        }
    }

    fun configurePagedMode(enabled: Boolean, twoPageLandscape: Boolean) {
        cancelPageAnimation()
        pagedMode = enabled
        this.twoPageLandscape = twoPageLandscape
        isHorizontalScrollBarEnabled = false
        isVerticalScrollBarEnabled = !enabled
        overScrollMode = if (enabled) View.OVER_SCROLL_NEVER else View.OVER_SCROLL_IF_CONTENT_SCROLLS
        wasHorizontalSpread = isHorizontalPaging()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val isSpread = isHorizontalPaging()
        if (isSpread != wasHorizontalSpread) {
            wasHorizontalSpread = isSpread
            post { onPageLayoutChanged?.invoke() }
        }
    }

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        if (pagedMode && t != 0) {
            // Some EPUB CSS and WebView's own touch slop can still move the
            // document vertically by a few pixels. Paged reading has no
            // vertical scroll position, so keep it pinned to the page row.
            post { if (pagedMode && scrollY != 0) scrollTo(scrollX, 0) }
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!pagedMode) return super.onTouchEvent(event)

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                // A fast second swipe starts from the page already being
                // turned to, so repeated turns do not get trapped midway.
                cancelPageAnimation(settleToTarget = true)
                downX = event.x
                downY = event.y
                val viewport = pageViewport().coerceAtLeast(1)
                val offset = if (isHorizontalPaging()) scrollX else scrollY
                downPage = (offset.toFloat() / viewport).roundToInt()
                scrollToPage(downPage)
                pagingGesture = false
                horizontalPageGesture = false
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.x - downX
                val dy = event.y - downY
                if (
                    event.pointerCount == 1 &&
                    !pagingGesture &&
                    maxOf(kotlin.math.abs(dx), kotlin.math.abs(dy)) > touchSlop
                ) {
                    pagingGesture = true
                    horizontalPageGesture = kotlin.math.abs(dx) > kotlin.math.abs(dy)
                    // Horizontal drags reveal the neighboring page; on
                    // release the WebView settles to a full page. Vertical
                    // drags are consumed and snap back.
                    val cancel = MotionEvent.obtain(event)
                    cancel.action = MotionEvent.ACTION_CANCEL
                    super.onTouchEvent(cancel)
                    cancel.recycle()
                    return true
                }
                if (pagingGesture) {
                    if (horizontalPageGesture && event.pointerCount == 1) {
                        val viewport = pageViewport().coerceAtLeast(1)
                        val maxOffset = (pageContentRange() - viewport).coerceAtLeast(0)
                        val startOffset = (downPage * viewport).coerceIn(0, maxOffset)
                        val offset = (startOffset - dx.roundToInt()).coerceIn(0, maxOffset)
                        scrollTo(offset, 0)
                    }
                    return true
                }
            }
            MotionEvent.ACTION_UP -> {
                if (pagingGesture) {
                    val dx = event.x - downX
                    val turnThreshold = maxOf(touchSlop * 2, (width * 0.18f).toInt())
                    if (horizontalPageGesture && kotlin.math.abs(dx) >= turnThreshold) {
                        val direction = if (dx < 0) 1 else -1
                        val progression = if (rightToLeft) -1 else 1
                        scrollToPage(downPage + direction, animate = true)
                        onPageTurn?.invoke(direction * progression)
                    } else {
                        scrollToPage(downPage, animate = true)
                    }
                    pagingGesture = false
                    horizontalPageGesture = false
                    return true
                }
                val moved = kotlin.math.abs(event.x - downX) > 2f ||
                    kotlin.math.abs(event.y - downY) > 2f
                val handled = super.onTouchEvent(event)
                if (moved) {
                    // WebView starts native scrolling before touchSlop. Snap
                    // sub-threshold drags back to the page they began on so a
                    // paged chapter can never be left between pages or nudged
                    // vertically by a short gesture.
                    post { scrollToPage(downPage, animate = true) }
                }
                return handled
            }
            MotionEvent.ACTION_CANCEL -> {
                if (pagingGesture) {
                    scrollToPage(downPage)
                    pagingGesture = false
                    horizontalPageGesture = false
                    return true
                }
            }
        }
        return super.onTouchEvent(event)
    }
}

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
        val bookPagedMode = params["bookPagedMode"] as? Boolean ?: true
        val bookFixedLayout = params["bookFixedLayout"] as? Boolean ?: false
        val bookRtl = params["bookRtl"] as? Boolean ?: false
        val bookTwoPageLandscape = params["bookTwoPageLandscape"] as? Boolean ?: false
        return HtmlViewerView(
            context, messenger, viewId, volId, htmlPath, jsEnabled,
            bookToken, bookEntry, bookCss, textZoom, backgroundColor,
            bookPagedMode, bookFixedLayout, bookRtl, bookTwoPageLandscape,
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
    private var bookPagedMode: Boolean = true,
    private val bookFixedLayout: Boolean = false,
    private var bookRtl: Boolean = false,
    private var bookTwoPageLandscape: Boolean = false,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val webView = ReaderWebView(context)
    private val methodChannel = MethodChannel(messenger, "$HTML_VIEWER_VIEW_TYPE/$viewId")
    private val eventChannel = EventChannel(messenger, "$HTML_VIEWER_VIEW_TYPE/events/$viewId")
    private var eventSink: EventChannel.EventSink? = null

    init {
        webView.configurePagedMode(
            enabled = bookToken != null && bookPagedMode,
            twoPageLandscape = bookToken != null && bookTwoPageLandscape,
        )
        webView.rightToLeft = bookRtl
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
            if (bookToken != null) useWideViewPort = true
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
            webView.onPageTurn = { direction ->
                pendingPageTurn = true
                pendingPageTurnDirection = direction
                scheduleScrollEvent()
            }
            webView.onPageLayoutChanged = { scheduleScrollEvent() }
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
    private var suppressNextScrollEvent = false
    private var pendingPageTurn = false
    private var pendingPageTurnDirection = 0

    private fun scheduleScrollEvent() {
        if (scrollEventPending) return
        scrollEventPending = true
        webView.postDelayed({
            scrollEventPending = false
            val initial = suppressNextScrollEvent
            suppressNextScrollEvent = false
            val pageTurn = pendingPageTurn
            val pageTurnDirection = pendingPageTurnDirection
            pendingPageTurn = false
            pendingPageTurnDirection = 0
            emitScrollEvent(
                initial = initial,
                pageTurn = pageTurn,
                pageTurnDirection = pageTurnDirection,
            )
        }, 120)
    }

    private fun emitScrollEvent(
        initial: Boolean = false,
        pageTurn: Boolean = false,
        pageTurnDirection: Int = 0,
    ) {
        val horizontalPages = webView.isHorizontalPaging()
        val verticalContent = (webView.contentHeight * webView.resources.displayMetrics.density).toInt()
        val contentPx = if (bookPagedMode && horizontalPages) {
            webView.horizontalScrollRange()
        } else {
            verticalContent
        }
        val viewportPx = if (bookPagedMode && horizontalPages) webView.width else webView.height
        val travel = (contentPx - viewportPx).coerceAtLeast(1)
        val offset = if (bookPagedMode && horizontalPages) webView.scrollX else webView.scrollY
        val fraction = if (bookPagedMode && horizontalPages && bookRtl) {
            ((travel - offset).toFloat() / travel).coerceIn(0f, 1f)
        } else {
            (offset.toFloat() / travel).coerceIn(0f, 1f)
        }
        val pageCount = if (bookPagedMode && viewportPx > 0) {
            ((contentPx + viewportPx - 1) / viewportPx).coerceAtLeast(1)
        } else {
            1
        }
        val page = if (bookPagedMode) {
            (fraction * (pageCount - 1)).roundToInt() + 1
        } else {
            1
        }
        val atStart = if (bookPagedMode && horizontalPages) {
            if (bookRtl) !webView.canScrollHorizontally(1) else !webView.canScrollHorizontally(-1)
        } else !webView.canScrollVertically(-1)
        val atEnd = if (bookPagedMode && horizontalPages) {
            if (bookRtl) !webView.canScrollHorizontally(-1) else !webView.canScrollHorizontally(1)
        } else !webView.canScrollVertically(1)
        eventSink?.success(
            mapOf(
                "event" to "scroll",
                "fraction" to fraction.toDouble(),
                "page" to page,
                "pageCount" to pageCount,
                "pageTurn" to pageTurn,
                "pageTurnDirection" to pageTurnDirection,
                "atStart" to atStart,
                "atEnd" to atEnd,
                "initial" to initial,
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
        var text = String(bytes, Charsets.UTF_8)
        if (bookPagedMode && !bookFixedLayout) {
            val viewportPattern = Regex(
                """<meta\b(?=[^>]*\bname\s*=\s*["']viewport["'])[^>]*>""",
                RegexOption.IGNORE_CASE,
            )
            val viewportTag = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />"
            if (viewportPattern.containsMatchIn(text)) {
                text = viewportPattern.replaceFirst(text, viewportTag)
            } else {
                val headEnd = text.indexOf("</head>", ignoreCase = true)
                val bodyStart = if (headEnd < 0) text.indexOf("<body", ignoreCase = true) else -1
                val insertAt = if (headEnd >= 0) headEnd else bodyStart
                if (insertAt >= 0) text = text.substring(0, insertAt) + viewportTag + text.substring(insertAt)
            }
        }
        val baseCss = when {
            bookFixedLayout -> EPUB_FIXED_CSS
            bookPagedMode -> "img,svg,video{max-width:100%!important;height:auto!important}table{max-width:100%}pre{white-space:pre-wrap}"
            else -> EPUB_BASE_CSS
        }
        val tag = "<style type=\"text/css\">" + baseCss + bookCss + "</style>"
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
            session.epub?.fontObfuscation?.get(entry.name)?.let { obfuscation ->
                val count = minOf(bytes.size, obfuscation.prefixLength)
                for (i in 0 until count) {
                    bytes[i] = (bytes[i].toInt() xor obfuscation.key[i % obfuscation.key.size].toInt()).toByte()
                }
            }
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
            if (bookToken != null) {
                webView.post {
                    if (bookPagedMode && bookRtl && webView.isHorizontalPaging()) {
                        val maxOffset =
                            (webView.horizontalScrollRange() - webView.width).coerceAtLeast(0)
                        webView.scrollTo(maxOffset, 0)
                    }
                    emitScrollEvent(initial = true)
                }
            }
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
                    webView.cancelPageAnimation()
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
                bookPagedMode = call.argument<Boolean>("paged") ?: bookPagedMode
                bookRtl = call.argument<Boolean>("rtl") ?: bookRtl
                bookTwoPageLandscape = call.argument<Boolean>("twoPageLandscape") ?: bookTwoPageLandscape
                webView.configurePagedMode(bookPagedMode, bookTwoPageLandscape)
                webView.rightToLeft = bookRtl
                call.argument<Number>("backgroundColor")?.toInt()?.let { webView.setBackgroundColor(it) }
                webView.reload()
                result.success(null)
            }
            "setScrollFraction" -> {
                val fraction = (call.argument<Number>("fraction")?.toFloat() ?: 0f).coerceIn(0f, 1f)
                webView.post {
                    webView.cancelPageAnimation()
                    val horizontalPages = webView.isHorizontalPaging()
                    val verticalContent =
                        (webView.contentHeight * webView.resources.displayMetrics.density).toInt()
                    val contentPx = if (bookPagedMode && horizontalPages) {
                        webView.horizontalScrollRange()
                    } else {
                        verticalContent
                    }
                    val viewportPx = if (bookPagedMode && horizontalPages) webView.width else webView.height
                    val maxOffset = (contentPx - viewportPx).coerceAtLeast(0)
                    val logicalFraction = if (bookPagedMode && horizontalPages && bookRtl) 1f - fraction else fraction
                    val offset = if (bookPagedMode && viewportPx > 0) {
                        val pageCount = ((contentPx + viewportPx - 1) / viewportPx).coerceAtLeast(1)
                        val page = ((pageCount - 1) * logicalFraction).roundToInt()
                        (page * viewportPx).coerceIn(0, maxOffset)
                    } else {
                        (maxOffset * logicalFraction).toInt()
                    }
                    suppressNextScrollEvent = true
                    webView.scrollTo(
                        if (bookPagedMode && horizontalPages) offset else 0,
                        if (bookPagedMode && !horizontalPages || !bookPagedMode) offset else 0,
                    )
                    scheduleScrollEvent()
                }
                result.success(null)
            }
            "turnPage" -> {
                val direction = call.argument<Number>("direction")?.toInt() ?: 1
                if (bookPagedMode) {
                    webView.turnPage(direction, bookRtl)
                    scheduleScrollEvent()
                    webView.postDelayed({ emitScrollEvent() }, 180)
                } else {
                    webView.scrollBy(0, if (direction > 0) webView.height else -webView.height)
                    webView.postDelayed({ emitScrollEvent() }, 180)
                }
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
