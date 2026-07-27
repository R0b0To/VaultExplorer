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
import com.aeidolon.vaultexplorer.ContainerFileSystem
import com.aeidolon.vaultexplorer.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.MimeTypeHelper
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

class HtmlViewerViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap<String, Any?>()
        val volId = (params["volId"] as? Number)?.toInt() ?: -1
        val htmlPath = params["htmlPath"] as? String ?: ""
        val jsEnabled = params["javaScriptEnabled"] as? Boolean ?: false
        return HtmlViewerView(context, messenger, viewId, volId, htmlPath, jsEnabled)
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
        if (initialPath.isEmpty()) return
        webView.loadUrl(buildVaultUri(initialPath).toString())
    }

    private inner class VaultWebViewClient : WebViewClient() {

        override fun shouldInterceptRequest(
            view: WebView,
            request: WebResourceRequest,
        ): WebResourceResponse {
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
            return !(uri.scheme == "https" && uri.host == VAULT_HOST)
        }

        override fun onPageFinished(view: WebView, url: String?) {
            eventSink?.success(
                mapOf(
                    "event" to "pageFinished",
                    "title" to view.title,
                    "canGoBack" to view.canGoBack(),
                    "canGoForward" to view.canGoForward(),
                )
            )
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

        private fun blockedResponse(): WebResourceResponse = WebResourceResponse(
            "text/plain", "utf-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(ByteArray(0))
        )

        private fun notFoundResponse(): WebResourceResponse = WebResourceResponse(
            "text/plain", "utf-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0))
        )
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
