package com.aeidolon.vaultexplorer.ffmpegplayer

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors

class FFmpegPlayerEngine(
    private val context: Context,
    textureRegistry: TextureRegistry,
    val playerId: Long,
    private val onEvent: (Map<String, Any?>) -> Unit,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val textureEntry = textureRegistry.createSurfaceTexture()
    private val surfaceTexture = textureEntry.surfaceTexture()
    private val surface = Surface(surfaceTexture)
    
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var openParcelFd: ParcelFileDescriptor? = null

    private var nativePlayerHandle: Long = 0
    private var disposed = false

    // Tracked separately from openParcelFd because diagnostics needs a fresh
    // MediaExtractor/MediaMetadataRetriever pass over the container -- reusing
    // the native player's already-open fd here would race with playback.
    private var currentContentUri: String? = null

    val textureId: Long get() = textureEntry.id()

    init {
        nativePlayerHandle = nativeCreate(surface)
    }

    // Called directly from native C++ JNI thread
    fun onEventFromNative(event: Map<String, Any?>) {
        mainHandler.post { 
            if (!disposed) {
                val width = (event["width"] as? Number)?.toInt() ?: 0
                val height = (event["height"] as? Number)?.toInt() ?: 0
                if (width > 0 && height > 0) {
                    surfaceTexture.setDefaultBufferSize(width, height)
                }
                onEvent(event)
            } 
        }
    }

    fun setDataSource(contentUri: String, autoPlay: Boolean) {
        currentContentUri = contentUri
        ioExecutor.execute {
            if (disposed) return@execute
            val pfd = context.contentResolver.openFileDescriptor(Uri.parse(contentUri), "r") ?: return@execute
            mainHandler.post {
                if (disposed) { pfd.close(); return@post }
                openParcelFd?.close()
                openParcelFd = pfd
                nativeSetDataSource(nativePlayerHandle, pfd.fd, autoPlay)
            }
        }
    }

    fun play() = nativePlay(nativePlayerHandle)
    fun pause() = nativePause(nativePlayerHandle)
    fun stop() = nativeStop(nativePlayerHandle)
    fun seekTo(positionMs: Long) = nativeSeekTo(nativePlayerHandle, positionMs)
    fun setVolume(volume: Int) = nativeSetVolume(nativePlayerHandle, volume)
    fun setRate(rate: Float) = nativeSetRate(nativePlayerHandle, rate)
    fun setLooping(looping: Boolean) = nativeSetLooping(nativePlayerHandle, looping)

    fun dispose() {
        if (disposed) return
        disposed = true
        nativeDispose(nativePlayerHandle)
        openParcelFd?.close()
        surface.release()
        textureEntry.release()
        ioExecutor.shutdown()
    }

    // Combines two independent diagnostics sources:
    //
    // 1. nativeGetDiagnostics(): measured FPS, live frame counts, and real
    //    codec/container info read straight out of FFmpeg's own decode
    //    pipeline (AVFormatContext/AVCodecContext) via a new synchronous JNI
    //    call. This is authoritative for anything it reports -- it's what's
    //    actually playing -- and cheap enough (atomic reads + a short
    //    native-side mutex, no blocking I/O; see getDiagnosticsSnapshot()'s
    //    comment in ffmpeg_player.h) to call directly on the calling thread
    //    rather than hopping to ioExecutor first.
    // 2. collectDiagnostics(): the pre-existing MediaExtractor/
    //    MediaMetadataRetriever pass. Kept as a fallback for fields the
    //    native side doesn't surface at all (rotation) and for files where
    //    playback hasn't reached avformat_find_stream_info yet, so the
    //    sheet isn't left completely empty during that window.
    //
    // Native values win wherever both sources report the same key, since
    // they reflect the file actually being decoded rather than a second,
    // independent parse of it.
    fun getDiagnostics(callback: (Map<String, Any?>) -> Unit) {
        val nativeDiagnostics: Map<String, Any?> = try {
            if (disposed) emptyMap() else (nativeGetDiagnostics(nativePlayerHandle) ?: emptyMap())
        } catch (e: Exception) {
            emptyMap()
        }

        val uriString = currentContentUri
        if (uriString == null || disposed) {
            mainHandler.post { callback(nativeDiagnostics) }
            return
        }
        ioExecutor.execute {
            val merged = if (disposed) {
                emptyMap()
            } else {
                LinkedHashMap<String, Any?>(collectDiagnostics(uriString)).apply { putAll(nativeDiagnostics) }
            }
            mainHandler.post { if (!disposed) callback(merged) }
        }
    }

    private fun collectDiagnostics(uriString: String): Map<String, Any?> {
        val result = LinkedHashMap<String, Any?>()
        val uri = Uri.parse(uriString)

        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            result["containerMimeType"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull()?.let { result["rotationDegrees"] = it }
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
                ?.toLongOrNull()?.let { result["containerBitrate"] = it }
        } catch (e: Exception) {
            // Best-effort: some containers the native FFmpeg engine can play
            // aren't recognized by the platform retriever. Diagnostics are
            // informational only, so just leave these fields out.
        } finally {
            try { retriever.release() } catch (e: Exception) {}
        }

        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri, null)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                when {
                    // Only the first video/audio track is reported -- enough
                    // for a debug overlay, and matches what's actually played.
                    mime.startsWith("video/") && !result.containsKey("videoCodec") -> {
                        result["videoCodec"] = mime
                        if (format.containsKey(MediaFormat.KEY_WIDTH)) result["videoWidth"] = format.getInteger(MediaFormat.KEY_WIDTH)
                        if (format.containsKey(MediaFormat.KEY_HEIGHT)) result["videoHeight"] = format.getInteger(MediaFormat.KEY_HEIGHT)
                        if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) result["frameRate"] = format.getInteger(MediaFormat.KEY_FRAME_RATE)
                        if (format.containsKey(MediaFormat.KEY_BIT_RATE)) result["videoBitrate"] = format.getInteger(MediaFormat.KEY_BIT_RATE)
                    }
                    mime.startsWith("audio/") && !result.containsKey("audioCodec") -> {
                        result["audioCodec"] = mime
                        if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) result["audioSampleRate"] = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) result["audioChannels"] = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        if (format.containsKey(MediaFormat.KEY_BIT_RATE)) result["audioBitrate"] = format.getInteger(MediaFormat.KEY_BIT_RATE)
                    }
                }
            }
        } catch (e: Exception) {
            // Same rationale as above -- leave video/audio track fields out.
        } finally {
            extractor.release()
        }

        return result
    }

    private external fun nativeCreate(surface: Surface?): Long
    private external fun nativeSetDataSource(handle: Long, fd: Int, autoPlay: Boolean)
    private external fun nativePlay(handle: Long)
    private external fun nativePause(handle: Long)
    private external fun nativeStop(handle: Long)
    private external fun nativeSeekTo(handle: Long, positionMs: Long)
    private external fun nativeSetVolume(handle: Long, volume: Int)
    private external fun nativeSetRate(handle: Long, rate: Float)
    private external fun nativeSetLooping(handle: Long, looping: Boolean)
    private external fun nativeDispose(handle: Long)
    private external fun nativeGetDiagnostics(handle: Long): Map<String, Any?>?
}