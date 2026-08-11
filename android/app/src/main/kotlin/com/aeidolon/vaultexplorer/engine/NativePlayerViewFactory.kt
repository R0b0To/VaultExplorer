package com.aeidolon.vaultexplorer.engine

import android.content.Context
import android.view.SurfaceView
import android.view.View
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory that creates [NativePlayerPlatformView] instances for Flutter's
 * `AndroidView` widget. Registered in [MainActivity.configureFlutterEngine]
 * under view type `"com.aeidolon.vaultexplorer/native_player_view"`.
 *
 * The created [PlayerView] is attached to the [ExoPlayer] instance managed
 * by [NativePlayerManager]. The player manager is notified when the
 * platform view is created so it can attach its player to the view's
 * SurfaceView, ensuring the video surface exists before frames are decoded.
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
    }

    init {
        // Attach the player after the view is created. This triggers
        // ExoPlayer to connect its video output to the PlayerView's
        // SurfaceView. If the player has already prepared, decoded frames
        // will route to this surface immediately.
        playerManager.attachPlayerView(playerView)
    }

    override fun getView(): View = playerView

    override fun dispose() {
        playerManager.detachPlayerView(playerView)
        playerView.player = null
    }
}
