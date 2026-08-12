@file:OptIn(androidx.pdf.ExperimentalPdfApi::class)

package com.aeidolon.vaultexplorer.pdf

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.ext.SdkExtensions
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.RequiresExtension
import androidx.fragment.app.FragmentActivity
import androidx.pdf.viewer.fragment.PdfViewerFragment
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** viewType every [JetpackPdfViewerViewFactory] instance is registered
 *  under; per-instance method/event channels are namespaced with the
 *  platform-view id. */
const val JETPACK_PDF_VIEWER_VIEW_TYPE = "com.aeidolon.vaultexplorer/jetpack_pdf_viewer"

private const val TAG = "JetpackPdfViewer"

/**
 * `PdfViewerFragment` throws [UnsupportedOperationException] on any device
 * that doesn't satisfy this exact gate -- API 31+ *and* SDK extension 13 on
 * the S track.
 */
fun isJetpackPdfViewerSupported(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
        Log.d(TAG, "Jetpack PDF viewer unsupported: SDK ${Build.VERSION.SDK_INT} < S")
        return false
    }
    return try {
        val ext = SdkExtensions.getExtensionVersion(Build.VERSION_CODES.S)
        val supported = ext >= 13
        if (!supported) Log.d(TAG, "Jetpack PDF viewer unsupported: S extension $ext < 13")
        supported
    } catch (e: Exception) {
        Log.d(TAG, "Jetpack PDF viewer unsupported: extension check threw", e)
        false
    }
}

class JetpackPdfViewerViewFactory(
    private val activity: FragmentActivity,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap<String, Any?>()
        val contentUri = params["contentUri"] as? String ?: ""
        return JetpackPdfViewerPlatformView(activity, messenger, viewId, contentUri)
    }
}

/**
 * Embeds [PdfViewerFragment] inside a Flutter `AndroidView`.
 */
@RequiresExtension(extension = Build.VERSION_CODES.S, version = 13)
class JetpackPdfViewerPlatformView(
    private val activity: FragmentActivity,
    messenger: BinaryMessenger,
    viewId: Int,
    private val contentUriString: String,
) : PlatformView, MethodChannel.MethodCallHandler {

    companion object {
        internal var activeInstance: JetpackPdfViewerPlatformView? = null
    }

    private val container = FrameLayout(activity)

    private val methodChannel = MethodChannel(messenger, "$JETPACK_PDF_VIEWER_VIEW_TYPE/$viewId")
    private val eventChannel = EventChannel(messenger, "$JETPACK_PDF_VIEWER_VIEW_TYPE/events/$viewId")
    private var eventSink: EventChannel.EventSink? = null

    private var pendingEvent: Map<String, Any?>? = null

    private val fragmentTag = "jetpack_pdf_viewer_$viewId"

    private var fragment: PdfViewerFragment? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
                pendingEvent?.let { sink.success(it) }
            }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })
        activeInstance = this
        attachFragment()
    }

    private fun attachFragment() {
        try {
            if (contentUriString.isEmpty()) {
                emitError("No content Uri provided")
                return
            }
            val uri = Uri.parse(contentUriString)

            val fm = activity.supportFragmentManager
            val existing = fm.findFragmentByTag(fragmentTag) as? PdfViewerFragment
            val f: PdfViewerFragment = existing ?: PdfViewerFragmentHost()
            
            (f as HostedFragment).host = this
            fragment = f

            if (existing == null) {
                fm.beginTransaction()
                    .add(f, fragmentTag)
                    .commitNowAllowingStateLoss()
            }
            attachFragmentView(f)
            f.documentUri = uri
            onDocumentLoaded()
        } catch (e: Throwable) {
            fragment = null
            Log.e(TAG, "Jetpack PDF viewer failed to attach -- falling back", e)
            emitError(e.message ?: e.javaClass.simpleName)
        }
    }

    private fun attachFragmentView(f: PdfViewerFragment) {
        f.view?.let { reparentIntoContainer(it); return }
        lateinit var observer: androidx.lifecycle.Observer<androidx.lifecycle.LifecycleOwner?>
        observer = androidx.lifecycle.Observer { owner ->
            if (owner == null) return@Observer
            f.view?.let { reparentIntoContainer(it) }
            f.viewLifecycleOwnerLiveData.removeObserver(observer)
        }
        f.viewLifecycleOwnerLiveData.observe(activity, observer)
    }

    private fun reparentIntoContainer(view: View) {
        (view.parent as? ViewGroup)?.let { if (it !== container) it.removeView(view) }
        if (view.parent !== container) container.addView(view)
        view.requestApplyInsets()
    }

    internal fun onDocumentLoaded() {
        sendEvent(mapOf("event" to "loaded"))
    }

    internal fun onDocumentError(error: Throwable) {
        emitError(error.message ?: error.javaClass.simpleName)
    }

    internal fun onNativeEditFabTapped() {
        eventSink?.success(mapOf("event" to "editRequested"))
    }

    private fun emitError(message: String) {
        sendEvent(mapOf("event" to "error", "message" to message))
    }

    private fun sendEvent(event: Map<String, Any?>) {
        pendingEvent = event
        eventSink?.success(event)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "toggleSearch" -> {
                val f = fragment
                if (f == null) {
                    result.success(false)
                    return
                }
                val active = !f.isTextSearchActive
                f.isTextSearchActive = active
                result.success(active)
            }
            else -> result.notImplemented()
        }
    }

    override fun getView(): View = container

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        if (activeInstance === this) activeInstance = null
        (fragment as? HostedFragment)?.host = null
        fragment?.let { f ->
            runCatching {
                activity.supportFragmentManager.beginTransaction()
                    .remove(f)
                    .commitNowAllowingStateLoss()
            }
        }
        fragment = null
    }
}

interface HostedFragment {
    var host: JetpackPdfViewerPlatformView?
}

@RequiresExtension(extension = Build.VERSION_CODES.S, version = 13)
class PdfViewerFragmentHost : PdfViewerFragment(), HostedFragment {
    override var host: JetpackPdfViewerPlatformView? = null

    override fun onLoadDocumentSuccess(document: androidx.pdf.PdfDocument) {
        host?.onDocumentLoaded()
        hideEditFab()
    }

    override fun onLoadDocumentError(error: Throwable) {
        host?.onDocumentError(error)
    }

    private fun hideEditFab() {
        view?.post {
            val fabId = view?.context?.resources?.getIdentifier("edit_fab", "id", view?.context?.packageName) ?: 0
            val fab = if (fabId != 0) view?.findViewById<View>(fabId) else view?.findViewById<View>(androidx.pdf.R.id.edit_fab)

            fab?.visibility = View.GONE
            fab?.addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
                if (v.visibility != View.GONE) {
                    v.visibility = View.GONE
                }
            }
        }
    }
}