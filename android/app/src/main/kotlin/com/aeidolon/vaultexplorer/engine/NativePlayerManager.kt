package com.aeidolon.vaultexplorer.engine

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener
import com.aeidolon.vaultexplorer.DeviceCapabilityProfiler
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class NativePlayerManager(private val context: Context) : Player.Listener {
    companion object {
        private const val TAG = "NativePlayerManager"
        private const val POSITION_UPDATE_INTERVAL_MS = 200L
        private const val DIAGNOSTICS_EMIT_INTERVAL_MS = 1000L
    }

    private var textureRegistry: TextureRegistry? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var textureId: Long = -1L

    private var player: ExoPlayer? = null
    private var currentVolId: Int = -1
    private var currentFilePath: String = ""

    var methodChannel: MethodChannel? = null
    var eventSink: EventChannel.EventSink? = null
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
    private var lastDiagnosticsEmitTimeMs: Long = 0L

    fun setTextureRegistry(registry: TextureRegistry) {
        this.textureRegistry = registry
    }

    private val analyticsListener = object : AnalyticsListener {
        override fun onRenderedFirstFrame(
            eventTime: AnalyticsListener.EventTime,
            output: Any,
            renderTimeMs: Long
        ) {
            emitEvent("renderedFirstFrame", emptyMap())
        }

        override fun onVideoDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializationDurationMs: Long
        ) {
            videoDecoderName = decoderName
            videoDecoderInitTimeMs = initializationDurationMs
            isVideoHw = !isSoftwareDecoder(decoderName)
            emitDiagnosticsUpdateThrottled()
        }

        override fun onAudioDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializationDurationMs: Long
        ) {
            audioDecoderName = decoderName
            isAudioHw = !isSoftwareDecoder(decoderName)
            emitDiagnosticsUpdateThrottled()
        }

        override fun onVideoInputFormatChanged(
            eventTime: AnalyticsListener.EventTime,
            format: Format,
            decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?
        ) {
            videoFrameRate = if (format.frameRate > 0) format.frameRate else videoFrameRate
            videoMimeType = format.sampleMimeType ?: ""
            colorInfoString = when {
                format.colorInfo?.colorTransfer == C.COLOR_TRANSFER_ST2084 -> "HDR10"
                format.colorInfo?.colorTransfer == C.COLOR_TRANSFER_HLG -> "HLG"
                format.colorInfo?.colorSpace == C.COLOR_SPACE_BT2020 -> "Rec.2020 (HDR/WCG)"
                else -> "SDR (BT.709)"
            }
            emitDiagnosticsUpdateThrottled()
        }

        override fun onAudioInputFormatChanged(
            eventTime: AnalyticsListener.EventTime,
            format: Format,
            decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?
        ) {
            audioMimeType = format.sampleMimeType ?: ""
            emitDiagnosticsUpdateThrottled()
        }

        override fun onDroppedVideoFrames(
            eventTime: AnalyticsListener.EventTime,
            droppedFrames: Int,
            elapsedMs: Long
        ) {
            droppedVideoFrames += droppedFrames
            emitDiagnosticsUpdateThrottled()
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
            "textureId" to textureId,
        )
    }

    private fun emitDiagnosticsUpdateThrottled() {
        val now = System.currentTimeMillis()
        if (now - lastDiagnosticsEmitTimeMs >= DIAGNOSTICS_EMIT_INTERVAL_MS) {
            lastDiagnosticsEmitTimeMs = now
            emitDiagnosticsUpdate()
        }
    }

    private fun emitDiagnosticsUpdate() {
        emitEvent("diagnosticsUpdate", getDiagnosticsMap())
    }

    fun initialize(volId: Int, filePath: String): Long {
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
        lastDiagnosticsEmitTimeMs = 0L

        // Release old surface & texture entry to ensure fresh GPU texture per video
        surface?.release()
        surface = null
        textureEntry?.release()
        textureEntry = null

        // Create a FRESH SurfaceTextureEntry for this new video stream
        val registry = textureRegistry ?: throw IllegalStateException("TextureRegistry not set")
        val entry = registry.createSurfaceTexture()
        textureEntry = entry
        textureId = entry.id()
        val st = entry.surfaceTexture()
        val newSurface = Surface(st)
        surface = newSurface

        var exoPlayer = player
        if (exoPlayer == null) {
            val tier = DeviceCapabilityProfiler.tierFor(context)
            val loadControl = buildLoadControl(tier)
            val renderersFactory = HighPerformanceRenderersFactory(context)
            exoPlayer = ExoPlayer.Builder(context, renderersFactory)
                .setLoadControl(loadControl)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                        .setUsage(C.USAGE_MEDIA)
                        .build(),
                    true
                )
                .build()
            exoPlayer.addListener(this)
            exoPlayer.addAnalyticsListener(analyticsListener)
            player = exoPlayer
        } else {
            exoPlayer.stop()
            exoPlayer.clearMediaItems()
        }

        exoPlayer.setVideoSurface(newSurface)

        val dataSourceFactory = VaultMedia3DataSourceFactory(volId, filePath)
        val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
            .createMediaSource(MediaItem.fromUri(Uri.parse("vault://$volId/$filePath")))
        exoPlayer.setMediaSource(mediaSource)
        exoPlayer.prepare()

        Log.d(TAG, "Player initialized for volId=$volId, path=$filePath, fresh textureId=$textureId")
        return textureId
    }

    private fun buildLoadControl(tier: DeviceCapabilityProfiler.Tier): DefaultLoadControl {
        val (minBufferMs, maxBufferMs, bufferForPlaybackMs, bufferForPlaybackAfterRebufferMs) = when (tier) {
            DeviceCapabilityProfiler.Tier.LOW    -> Quadruple(8_000, 20_000, 2_000, 4_000)
            DeviceCapabilityProfiler.Tier.MEDIUM -> Quadruple(12_000, 30_000, 2_500, 5_000)
            DeviceCapabilityProfiler.Tier.HIGH   -> Quadruple(15_000, 40_000, 3_000, 6_000)
        }
        val maxBufferBytes = when (tier) {
            DeviceCapabilityProfiler.Tier.LOW    -> 32 * 1024 * 1024
            DeviceCapabilityProfiler.Tier.MEDIUM -> 48 * 1024 * 1024
            DeviceCapabilityProfiler.Tier.HIGH   -> 64 * 1024 * 1024
        }
        return DefaultLoadControl.Builder()
            .setBufferDurationsMs(minBufferMs, maxBufferMs, bufferForPlaybackMs, bufferForPlaybackAfterRebufferMs)
            .setTargetBufferBytes(maxBufferBytes)
            .setPrioritizeTimeOverSizeThresholds(false)
            .setBackBuffer(0,  false)
            .build()
    }

    private data class Quadruple(val a: Int, val b: Int, val c: Int, val d: Int)

    fun play() {
        val p = player ?: return
        if (p.playbackState == Player.STATE_ENDED || (p.duration > 0 && p.currentPosition >= p.duration)) {
            p.seekTo(0L)
        }
        p.play()
    }

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

    fun release() {
        mainHandler.removeCallbacks(positionUpdateRunnable)
        player?.let { p ->
            p.clearVideoSurface()
            p.removeListener(this)
            p.release()
        }
        player = null
        surface?.release()
        surface = null
        textureEntry?.release()
        textureEntry = null
        textureId = -1L
        currentVolId = -1
        currentFilePath = ""
    }

    fun getPlayer(): ExoPlayer? = player

    override fun onRenderedFirstFrame() {
        emitEvent("renderedFirstFrame", emptyMap())
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        val state = when (playbackState) {
            Player.STATE_IDLE -> "idle"
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_READY -> "ready"
            Player.STATE_ENDED -> "ended"
            else -> "unknown"
        }
        emitEvent("playbackState", mapOf("state" to state))
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
            player?.let { emitPositionUpdate(it) }
        }
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        // Do NOT call setDefaultBufferSize to avoid EGL buffer queue reallocations
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
        if (defaultRate != CODEC_OPERATING_RATE_UNSET) {
            return defaultRate.coerceAtMost(120f)
        }
        val streamFps = if (format.frameRate > 0f) format.frameRate else 30f
        return (streamFps * targetPlaybackSpeed).coerceAtMost(120f)
    }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
private class HighPerformanceRenderersFactory(
    context: Context
) : DefaultRenderersFactory(context) {
    init {
        setEnableDecoderFallback(true)
        setExtensionRendererMode(EXTENSION_RENDERER_MODE_ON)
        forceEnableMediaCodecAsynchronousQueueing()
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