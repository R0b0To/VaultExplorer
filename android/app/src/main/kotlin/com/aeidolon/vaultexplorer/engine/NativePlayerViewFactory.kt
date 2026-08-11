package com.aeidolon.vaultexplorer.engine

import android.content.Context
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

// Obsolete PlatformView factory — video playback now uses Flutter's TextureRegistry directly
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class NativePlayerViewFactory(
    private val playerManager: NativePlayerManager,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NativePlayerPlatformView(context)
    }
}

private class NativePlayerPlatformView(
    context: Context,
) : PlatformView {
    private val dummyView: View = View(context)
    override fun getView(): View = dummyView
    override fun dispose() {}
}