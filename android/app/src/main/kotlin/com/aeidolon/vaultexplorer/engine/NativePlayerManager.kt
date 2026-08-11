package com.aeidolon.vaultexplorer.engine

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.Format
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener
import androidx.media3.ui.PlayerView
import com.aeidolon.vaultexplorer.DeviceCapabilityProfiler
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Manages the lifecycle of a single ExoPlayer instance that reads decrypted
 * media directly from [VaultMedia3DataSource].
 *
 * Coordinates with [ThumbnailHandlers] via [setPlaybackActiveMethod] to
 * arbitrate hardware codec access between video playback and thumbnail
 * extraction.
 *
 * All public methods must be called on the main (UI) thread.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class NativePlayerManager(private val context: Context) : Player.Listener {

    companion object {
        private const val TAG = "NativePlayerManager"
        private const val POSITION_UPDATE_INTERVAL_MS = 200L
    }

    private var player: ExoPlayer? = null
    private var currentVolId: Int = -1
    private var currentFilePath: String = ""
    private var attachedPlayerView: PlayerView? = null
    private var pendingPrepare: Boolean = false

    /** Method channel for sending one-shot replies (e.g., track list responses). */
    var methodChannel: MethodChannel? = null

    /** Event channel sink for streaming player state to Flutter. */
    var eventSink: EventChannel.EventSink? = null

    /**
     * Callback that notifies [ThumbnailHandlers] to pause/resume background
     * thumbnail extraction. Wired in [MainActivity.configureFlutterEngine].
     */
    var setPlaybackActiveCallback: ((Boolean) -> Unit)? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val positionUpdateRunnable = object : Runnable {
        override fun run() {
            val p = player ?: return
            if (!p.isPlaying) return
            emitPositionUpdate(p)
            mainHandler.postDelayed(this, POSITION_UPDATE_INTERVAL_MS)
        }
    }

    private var videoDecoderName: String = "Initializing..."
    private var audioDecoderName: String = "Initializing..."
    private var isVideoHw: Boolean = true
    private var isAudioHw: Boolean = false
    private var videoFrameRate: Float = 0f
    private var videoMimeType: String = ""
    private var audioMimeType: String = ""
    private var droppedVideoFrames: Int = 0
    private var videoDecoderInitTimeMs: Long = 0
    private var colorInfoString: String = "SDR"

    private val analyticsListener = object : AnalyticsListener {
        override fun onVideoDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializationDurationMs: Long
        ) {
            videoDecoderName = decoderName
            videoDecoderInitTimeMs = initializationDurationMs
            isVideoHw = !isSoftwareDecoder(decoderName)
            emitDiagnosticsUpdate()
        }

        override fun onAudioDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializationDurationMs: Long
        ) {
            audioDecoderName = decoderName
            isAudioHw = !isSoftwareDecoder(decoderName)
            emitDiagnosticsUpdate()
        }

        override fun onVideoInputFormatChanged(
            eventTime: AnalyticsListener.EventTime,
            format: androidx.media3.common.Format,
            decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?
        ) {
            videoFrameRate = if (format.frameRate > 0) format.frameRate else videoFrameRate
            videoMimeType = format.sampleMimeType ?: ""
            colorInfoString = when {
                format.colorInfo?.colorTransfer == C.COLOR_TRANSFER_ST2084 -> "HDR10"
                format.colorInfo?.colorTransfer == C.COLOR_TRANSFER_HLG -> "HLG"
                else -> "SDR"
            }
            emitDiagnosticsUpdate()
        }

        override fun onAudioInputFormatChanged(
            eventTime: AnalyticsListener.EventTime,
            format: androidx.media3.common.Format,
            decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?
        ) {
            audioMimeType = format.sampleMimeType ?: ""
            emitDiagnosticsUpdate()
        }

        override fun onDroppedVideoFrames(
            eventTime: AnalyticsListener.EventTime,
            droppedFrames: Int,
            elapsedMs: Long
        ) {
            droppedVideoFrames += droppedFrames
            emitDiagnosticsUpdate()
        }
    }

    private fun isSoftwareDecoder(decoderName: String): Boolean {
        val lower = decoderName.lowercase()
        return lower.startsWith("c2.android.") ||
               lower.startsWith("omx.google.") ||
               lower.contains(".sw.") ||
               lower.endsWith(".sw")
    }

    fun getDiagnosticsMap(): Map<String, Any?> {
        val p = player
        return mapOf(
            "videoDecoderName" to videoDecoderName,
            "isVideoHardwareAccelerated" to isVideoHw,
            "audioDecoderName" to audioDecoderName,
            "isAudioHardwareAccelerated" to isAudioHw,
            "frameRate" to videoFrameRate,
            "videoMimeType" to videoMimeType,
            "audioMimeType" to audioMimeType,
            "droppedFrames" to droppedVideoFrames,
            "decoderInitTimeMs" to videoDecoderInitTimeMs,
            "colorInfo" to colorInfoString,
            "bufferedMs" to (p?.bufferedPosition ?: 0L),
            "volId" to currentVolId,
            "filePath" to currentFilePath,
        )
    }

    private fun emitDiagnosticsUpdate() {
        emitEvent("diagnosticsUpdate", getDiagnosticsMap())
    }

    // ── Initialization ─────────────────────────────────────────────────────

    fun initialize(volId: Int, filePath: String) {
        release() // ensure no stale player

        currentVolId = volId
        currentFilePath = filePath
        videoDecoderName = "Initializing..."
        audioDecoderName = "Initializing..."
        isVideoHw = true
        isAudioHw = false
        videoFrameRate = 0f
        videoMimeType = ""
        audioMimeType = ""
        droppedVideoFrames = 0
        videoDecoderInitTimeMs = 0
        colorInfoString = "SDR"

        val tier = DeviceCapabilityProfiler.tierFor(context)
        val loadControl = buildLoadControl(tier)
        val renderersFactory = HighPerformanceRenderersFactory(context)

        val exoPlayer = ExoPlayer.Builder(context, renderersFactory)
            .setLoadControl(loadControl)
            .build()
        exoPlayer.addListener(this)
        exoPlayer.addAnalyticsListener(analyticsListener)

        val dataSourceFactory = VaultMedia3DataSourceFactory(volId, filePath)
        val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
            .createMediaSource(MediaItem.fromUri(Uri.parse("vault://$volId/$filePath")))

        exoPlayer.setMediaSource(mediaSource)

        player = exoPlayer

        // If a PlayerView is already attached (unlikely on first init, but
        // possible on re-init), wire it up and prepare immediately.
        // Otherwise, defer prepare() until attachPlayerView() is called so
        // the codec's SurfaceView exists before first frame decode.
        val existingView = attachedPlayerView
        if (existingView != null) {
            existingView.player = exoPlayer
            exoPlayer.prepare()
            pendingPrepare = false
        } else {
            // Start without a video surface — audio will still play once
            // prepared, and video frames will queue until the surface
            // arrives.
            exoPlayer.clearVideoSurface()
            exoPlayer.prepare()
            pendingPrepare = true
        }

        Log.d(TAG, "Player initialized for volId=$volId, path=$filePath, tier=$tier, viewAttached=${existingView != null}")
    }

    private fun buildLoadControl(tier: DeviceCapabilityProfiler.Tier): DefaultLoadControl {
        val (minBufferMs, maxBufferMs, bufferForPlaybackMs, bufferForPlaybackAfterRebufferMs) = when (tier) {
            DeviceCapabilityProfiler.Tier.LOW    -> Quadruple(5_000, 15_000, 1_500, 3_000)
            DeviceCapabilityProfiler.Tier.MEDIUM -> Quadruple(10_000, 30_000, 2_000, 4_000)
            DeviceCapabilityProfiler.Tier.HIGH   -> Quadruple(15_000, 50_000, 2_500, 5_000)
        }
        return DefaultLoadControl.Builder()
            .setBufferDurationsMs(minBufferMs, maxBufferMs, bufferForPlaybackMs, bufferForPlaybackAfterRebufferMs)
            .build()
    }

    private data class Quadruple(val a: Int, val b: Int, val c: Int, val d: Int)

    // ── Transport controls ──────────────────────────────────────────────────

    fun play() { player?.play() }
    fun pause() { player?.pause() }

    fun seekTo(positionMs: Long) {
        player?.seekTo(positionMs)
    }

    fun setSpeed(speed: Float) {
        player?.setPlaybackSpeed(speed)
    }

    fun setVolume(volume: Float) {
        player?.volume = volume.coerceIn(0f, 1f)
    }

    fun setLooping(loop: Boolean) {
        player?.repeatMode = if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
    }

    // ── Track selection ─────────────────────────────────────────────────────

    fun getAudioTracks(): List<Map<String, Any?>> {
        val p = player ?: return emptyList()
        return extractTracks(p, C.TRACK_TYPE_AUDIO)
    }

    fun getSubtitleTracks(): List<Map<String, Any?>> {
        val p = player ?: return emptyList()
        return extractTracks(p, C.TRACK_TYPE_TEXT)
    }

    private fun extractTracks(player: ExoPlayer, trackType: @C.TrackType Int): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        val tracks = player.currentTracks
        for (group in tracks.groups) {
            if (group.type != trackType) continue
            for (trackIdx in 0 until group.length) {
                val format = group.getTrackFormat(trackIdx)
                val isSelected = group.isTrackSelected(trackIdx)
                val info = mutableMapOf<String, Any?>(
                    "groupIndex" to tracks.groups.indexOf(group),
                    "trackIndex" to trackIdx,
                    "isSelected" to isSelected,
                    "language" to format.language,
                    "label" to format.label,
                    "mimeType" to format.sampleMimeType,
                    "id" to format.id,
                )
                if (trackType == C.TRACK_TYPE_AUDIO) {
                    info["channelCount"] = format.channelCount
                    info["sampleRate"] = format.sampleRate
                    info["bitrate"] = format.bitrate
                }
                result.add(info)
            }
        }
        return result
    }

    fun selectAudioTrack(groupIndex: Int, trackIndex: Int) {
        selectTrack(C.TRACK_TYPE_AUDIO, groupIndex, trackIndex)
    }

    fun selectSubtitleTrack(groupIndex: Int, trackIndex: Int) {
        selectTrack(C.TRACK_TYPE_TEXT, groupIndex, trackIndex)
    }

    fun disableSubtitleTrack() {
        val p = player ?: return
        p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            .build()
    }

    private fun selectTrack(trackType: @C.TrackType Int, groupIndex: Int, trackIndex: Int) {
        val p = player ?: return
        val tracks = p.currentTracks
        if (groupIndex < 0 || groupIndex >= tracks.groups.size) return
        val group = tracks.groups[groupIndex]
        if (group.type != trackType) return
        if (trackIndex < 0 || trackIndex >= group.length) return

        val override = TrackSelectionOverride(group.mediaTrackGroup, listOf(trackIndex))
        p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(trackType, false)
            .setOverrideForType(override)
            .build()
    }

    // ── PlayerView attach/detach ────────────────────────────────────────────

    /**
     * Called by [NativePlayerPlatformView] when the Flutter PlatformView is
     * created. Wires the ExoPlayer to the [PlayerView]'s SurfaceView so
     * decoded video frames render to the correct surface.
     */
    fun attachPlayerView(view: PlayerView) {
        attachedPlayerView = view
        val p = player ?: return
        view.player = p
        if (pendingPrepare) {
            // The player was already prepared (audio may be playing),
            // but it had no video surface. Now that the PlayerView is
            // available, set the surface. ExoPlayer will automatically
            // route new decoded frames to it.
            pendingPrepare = false
            Log.d(TAG, "PlayerView attached — video surface connected")
        }
    }

    /**
     * Called by [NativePlayerPlatformView] when the Flutter PlatformView is
     * disposed.
     */
    fun detachPlayerView(view: PlayerView) {
        if (attachedPlayerView === view) {
            view.player = null
            attachedPlayerView = null
        }
    }

    // ── Release ─────────────────────────────────────────────────────────────

    fun release() {
        mainHandler.removeCallbacks(positionUpdateRunnable)
        attachedPlayerView?.player = null
        // Don't null attachedPlayerView here — the PlatformView may still
        // exist and will call detachPlayerView on dispose.
        player?.let { p ->
            p.removeListener(this)
            p.release()
        }
        player = null
        pendingPrepare = false
        currentVolId = -1
        currentFilePath = ""
    }

    /** For [NativePlayerViewFactory] — returns the active [ExoPlayer] or null. */
    fun getPlayer(): ExoPlayer? = player

    // ── Player.Listener callbacks ───────────────────────────────────────────

    override fun onPlaybackStateChanged(playbackState: Int) {
        val state = when (playbackState) {
            Player.STATE_IDLE -> "idle"
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_READY -> "ready"
            Player.STATE_ENDED -> "ended"
            else -> "unknown"
        }
        emitEvent("playbackState", mapOf("state" to state))

        // When the player reaches STATE_READY for the first time, emit
        // the initial track list so Flutter can populate the track pickers.
        if (playbackState == Player.STATE_READY) {
            emitTracksChanged()
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        emitEvent("playingChanged", mapOf("isPlaying" to isPlaying))
        if (isPlaying) {
            mainHandler.post(positionUpdateRunnable)
        } else {
            mainHandler.removeCallbacks(positionUpdateRunnable)
            // Emit one final position update so Flutter has the exact
            // pause position.
            player?.let { emitPositionUpdate(it) }
        }
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        emitEvent("videoSize", mapOf(
            "width" to videoSize.width,
            "height" to videoSize.height,
        ))
    }

    override fun onTracksChanged(tracks: Tracks) {
        emitTracksChanged()
    }

    override fun onPlayerError(error: PlaybackException) {
        Log.e(TAG, "Player error: ${error.errorCodeName}: ${error.message}", error)
        emitEvent("error", mapOf(
            "code" to error.errorCode,
            "message" to (error.message ?: "Unknown playback error"),
        ))
    }

    // ── Event emission helpers ───────────────────────────────────────────────

    private fun emitPositionUpdate(player: ExoPlayer) {
        emitEvent("positionUpdate", mapOf(
            "positionMs" to player.currentPosition,
            "durationMs" to player.duration.let { if (it == C.TIME_UNSET) 0L else it },
            "bufferedMs" to player.bufferedPosition,
        ))
    }

    private fun emitTracksChanged() {
        emitEvent("tracksChanged", mapOf(
            "audioTracks" to getAudioTracks(),
            "subtitleTracks" to getSubtitleTracks(),
        ))
    }

    private fun emitEvent(type: String, data: Map<String, Any?>) {
        mainHandler.post {
            val payload = HashMap<String, Any?>(data)
            payload["event"] = type
            eventSink?.success(payload)
        }
    }
}

/**
 * Custom [MediaCodecVideoRenderer] that caps operating rate requests sent to
 * vendor hardware decoders (e.g. Qualcomm CCodec `c2.qti.vp9.decoder`).
 *
 * When playback speed is increased (e.g. 2x–4x), standard ExoPlayer calculates
 * operatingRate = speed * frameRate (which for 4K@30fps becomes 90–120fps / 96000 mFPS).
 * Vendor hardware decoders fail operating-rate queries for high values and enter
 * continuous flush loops (`Discard frames from previous generation. flushed work; ignored`).
 *
 * Returning [CODEC_OPERATING_RATE_UNSET] (-1.0f) forces MediaCodec to operate at its
 * standard optimal clock while ExoPlayer handles speed scaling smoothly without flushing.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
private class HighSpeedMediaCodecVideoRenderer(
    context: Context,
    mediaCodecSelector: MediaCodecSelector,
    allowedJoiningTimeMs: Long,
    enableDecoderFallback: Boolean,
    eventHandler: Handler?,
    eventListener: VideoRendererEventListener?,
    maxDroppedFramesBeforeNotify: Int
) : MediaCodecVideoRenderer(
    context,
    mediaCodecSelector,
    allowedJoiningTimeMs,
    enableDecoderFallback,
    eventHandler,
    eventListener,
    maxDroppedFramesBeforeNotify
) {
    override fun getCodecOperatingRateV23(
        targetPlaybackSpeed: Float,
        format: Format,
        streamFormats: Array<out Format>
    ): Float {
        val defaultRate = super.getCodecOperatingRateV23(targetPlaybackSpeed, format, streamFormats)
        if (defaultRate > 60.0f || (format.height >= 2160 && targetPlaybackSpeed > 1.0f)) {
            return CODEC_OPERATING_RATE_UNSET
        }
        return defaultRate
    }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
private class HighPerformanceRenderersFactory(
    context: Context
) : DefaultRenderersFactory(context) {

    init {
        setEnableDecoderFallback(true)
        setExtensionRendererMode(EXTENSION_RENDERER_MODE_PREFER)
    }

    override fun buildVideoRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        eventHandler: Handler,
        eventListener: VideoRendererEventListener,
        allowedVideoJoiningTimeMs: Long,
        out: ArrayList<Renderer>
    ) {
        val videoRenderer = HighSpeedMediaCodecVideoRenderer(
            context,
            mediaCodecSelector,
            allowedVideoJoiningTimeMs,
            enableDecoderFallback,
            eventHandler,
            eventListener,
            50
        )
        out.add(videoRenderer)
    }
}
