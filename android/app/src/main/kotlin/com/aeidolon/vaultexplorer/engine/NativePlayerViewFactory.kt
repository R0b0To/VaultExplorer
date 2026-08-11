package com.aeidolon.vaultexplorer.engine

import android.content.Context
import android.view.View
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory that creates [NativePlayerPlatformView] instances for Flutter's
 * `AndroidView` widget. Registered in [MainActivity.configureFlutterEngine]
 * under view type `"com.aeidolon.vaultexplorer/native_player_view"`.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class NativePlayerViewFactory(
    private val playerManager: NativePlayerManager,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NativePlayerPlatformView(context, playerManager)
    }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
private class NativePlayerPlatformView(
    context: Context,
    private val playerManager: NativePlayerManager,
) : PlatformView {

    private val playerView: PlayerView = PlayerView(context).apply {
        useController = false // Flutter manages all controls
        setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
        keepScreenOn = true
    }

    init {
        playerManager.attachPlayerView(playerView)
    }

    override fun getView(): View = playerView

    override fun dispose() {
        playerManager.detachPlayerView(playerView)
        playerView.player = null
    }
}