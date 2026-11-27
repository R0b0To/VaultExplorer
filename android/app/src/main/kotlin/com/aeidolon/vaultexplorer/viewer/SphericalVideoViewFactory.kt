package com.aeidolon.vaultexplorer.viewer

import android.content.Context
import android.util.Log
import android.view.GestureDetector
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import androidx.media3.exoplayer.video.spherical.SphericalGLSurfaceView
import androidx.media3.ui.PlayerView
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.engine.NativePlayerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

const val SPHERICAL_VIDEO_VIEW_TYPE = "com.aeidolon.vaultexplorer/spherical_video"

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class SphericalVideoViewFactory(
    private val manager: NativePlayerManager,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        SphericalVideoView(context, viewId, manager, messenger)
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
private class SphericalVideoView(
    context: Context,
    viewId: Int,
    private val manager: NativePlayerManager,
    messenger: BinaryMessenger,
) : PlatformView {
    private val playerView = LayoutInflater.from(context)
        .inflate(R.layout.viewer_spherical_video, null) as PlayerView
    private val sphere = playerView.videoSurfaceView as SphericalGLSurfaceView
    private val channel = MethodChannel(messenger, "com.aeidolon.vaultexplorer/spherical_video/$viewId")
    private val orientationController = runCatching { SphericalOrientationController(sphere) }
        .onFailure { Log.w("SphericalVideoView", "Could not enable full-range touch controls", it) }
        .getOrNull()
    private val root = SphericalTapFrameLayout(context) {
        channel.invokeMethod("tap", null)
    }.apply {
        addView(
            playerView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    init {
        sphere.setUseSensorRotation(false)
        orientationController?.let { sphere.setOnTouchListener(it) }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setSensorEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (orientationController != null) {
                        orientationController.setSensorEnabled(enabled)
                    } else {
                        sphere.setUseSensorRotation(enabled)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        manager.attachSphericalView(playerView)
    }

    override fun getView(): View = root

    override fun dispose() {
        channel.setMethodCallHandler(null)
        orientationController?.dispose()
        manager.detachSphericalView(playerView)
    }
}

/** Observes taps before the spherical surface consumes touch events for panning. */
private class SphericalTapFrameLayout(context: Context, onTap: () -> Unit) : FrameLayout(context) {
    private val tapDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent): Boolean = true

        override fun onSingleTapUp(e: MotionEvent): Boolean {
            onTap()
            return true
        }
    })

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        tapDetector.onTouchEvent(event)
        return super.dispatchTouchEvent(event)
    }
}
