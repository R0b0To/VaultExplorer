package com.aeidolon.vaultexplorer.vlcplayer

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import io.flutter.view.TextureRegistry
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.interfaces.IMedia
import org.videolan.libvlc.interfaces.IVLCVout

/**
 * Process-wide libVLC instance. libVLC itself is heavyweight to spin up
 * (it initializes its module bank, plugin cache, etc.) so we keep exactly
 * one for the app's lifetime and hand out [MediaPlayer]s from it — this
 * mirrors how VLC's own Android app manages `VLCInstance`.
 */
object VlcCore {
    @Volatile
    private var libVLC: LibVLC? = null

    /**
     * Kept intentionally minimal. `--no-sub-autodetect-file` stops libVLC
     * from scanning the (virtual, DocumentsProvider-backed) directory next
     * to the opened file for stray subtitle files to auto-load — we manage
     * subtitles ourselves on the Flutter side. Nothing here forces or
     * disables hardware decoding; that is controlled per-Media via
     * [Media.setHWDecoderEnabled] so a single bad file can fall back to
     * software decoding without taking every other player down with it.
     */
    private val options = arrayListOf(
        "--no-sub-autodetect-file",
        "-vv",
    )

    fun get(context: Context): LibVLC {
        return libVLC ?: synchronized(this) {
            libVLC ?: LibVLC(context.applicationContext, options).also { libVLC = it }
        }
    }

    /** Only call this once, when the whole Flutter engine is tearing down. */
    fun releaseIfIdle() {
        synchronized(this) {
            libVLC?.release()
            libVLC = null
        }
    }
}

/**
 * Wraps a single libVLC [MediaPlayer] plus the Flutter [TextureRegistry]
 * surface it renders into, and forwards playback events back to Dart as
 * plain maps via [onEvent].
 *
 * One [VlcPlayerEngine] == one native player == one Flutter `Texture`.
 */
class VlcPlayerEngine(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    val playerId: Long,
    private val onEvent: (Map<String, Any?>) -> Unit,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val libVLC: LibVLC = VlcCore.get(context)
    private val mediaPlayer: MediaPlayer = MediaPlayer(libVLC)
    private val textureEntry: TextureRegistry.SurfaceTextureEntry =
        textureRegistry.createSurfaceTexture()
    private val surfaceTexture = textureEntry.surfaceTexture()

    // Kept open for the lifetime of the current Media so libVLC's fd stays
    // valid; closed explicitly on every media change and on dispose so we
    // don't leak the proxy-fd thread ContainerDocumentsProvider spins up
    // per open() call.
    private var openParcelFd: ParcelFileDescriptor? = null

    // The Uri last passed to setDataSource(), kept so play() can reopen a
    // fresh fd + Media for it after EOF — see `reachedEnd` below.
    private var lastContentUri: String? = null

    // Set once EndReached fires, cleared once we've reopened for a replay.
    // libVLC's fd-access module closes the raw fd our Media was built
    // around once it finishes reading it at EOF (that's ownership
    // semantics of handing it a bare fd, not something we control from
    // here), so the *same* Media/fd can never be resumed after the end —
    // trying produces "VLC is unable to open the MRL 'fd://N'" because
    // that fd number is already closed. play() checks this flag and, if
    // set, reopens a brand new fd/Media for the same content instead of
    // calling mediaPlayer.play() directly.
    private var reachedEnd = false

    // Size we last pushed onto the SurfaceTexture's buffer, so repeated
    // onNewVideoLayout callbacks with the same size are cheap no-ops.
    private var currentVideoWidth = 0
    private var currentVideoHeight = 0

    private var disposed = false

    val textureId: Long get() = textureEntry.id()

    init {
        // IMPORTANT: a SurfaceTexture handed out by Flutter's
        // TextureRegistry starts with a default 1x1 pixel buffer, and
        // Android never resizes it to match whatever libVLC decodes into
        // it — that has to be driven from here explicitly, once libVLC
        // reports the real video dimensions via onNewVideoLayout below.
        // Skipping this is exactly what causes the "video is one
        // flashing/zoomed pixel" symptom: libVLC decodes full frames into
        // a 1x1 buffer and the GPU stretches that single pixel across the
        // whole Texture widget.
        val vout = mediaPlayer.vlcVout
        vout.setVideoSurface(surfaceTexture)
        vout.setWindowSize(1, 1) // placeholder until onNewVideoLayout fires
        vout.addCallback(object : IVLCVout.Callback {
            override fun onSurfacesCreated(vlcVout: IVLCVout) {}
            override fun onSurfacesDestroyed(vlcVout: IVLCVout) {}
        })
        if (!vout.areViewsAttached()) {
            // The OnNewVideoLayoutListener is passed here, not via a
            // separate setter — this attachViews(listener) overload is
            // what actually registers it.
            vout.attachViews(object : IVLCVout.OnNewVideoLayoutListener {
                override fun onNewVideoLayout(
                    vlcVout: IVLCVout,
                    width: Int,
                    height: Int,
                    visibleWidth: Int,
                    visibleHeight: Int,
                    sarNum: Int,
                    sarDen: Int,
                ) {
                    applyVideoSize(width, height)
                }
            })
        }

        mediaPlayer.setEventListener { event ->
            handleVlcEvent(event)
        }
    }

    /**
     * Pushes [width]x[height] onto the SurfaceTexture's buffer and tells
     * libVLC's vout the same size, so the two agree on how big a frame is.
     * Safe to call repeatedly; no-ops once the size is already applied.
     * Must run on the main thread since it touches the SurfaceTexture/vout.
     */
private fun applyVideoSize(width: Int, height: Int) {
    Log.d("VlcPlayerEngine", "onNewVideoLayout: ${width}x$height (current: ${currentVideoWidth}x$currentVideoHeight)")
    if (width <= 0 || height <= 0) return
    if (width == currentVideoWidth && height == currentVideoHeight) return
    currentVideoWidth = width
    currentVideoHeight = height

    mainHandler.post {
        if (disposed) return@post
        Log.d("VlcPlayerEngine", "applying size ${width}x$height to surfaceTexture + vout")
        surfaceTexture.setDefaultBufferSize(width, height)
        mediaPlayer.vlcVout.setWindowSize(width, height)
    }
}

    private fun post(map: Map<String, Any?>) {
        mainHandler.post { if (!disposed) onEvent(map) }
    }

    private fun handleVlcEvent(event: MediaPlayer.Event) {
        when (event.type) {
            MediaPlayer.Event.Opening -> post(mapOf("event" to "opening"))

MediaPlayer.Event.Playing -> {
    val track = mediaPlayer.getCurrentVideoTrack()
    if (track != null && track.width > 0 && track.height > 0) {
        applyVideoSize(track.width, track.height)
    }
    post(
        mapOf(
            "event" to "playing",
            "width" to (track?.let { displayWidth(it) } ?: 0),
            "height" to (track?.height ?: 0),
            "durationMs" to mediaPlayer.getLength(),
        )
    )
}

            MediaPlayer.Event.Paused -> post(mapOf("event" to "paused"))
            MediaPlayer.Event.Stopped -> post(mapOf("event" to "stopped"))

            MediaPlayer.Event.Buffering -> post(
                mapOf("event" to "buffering", "percent" to event.getBuffering())
            )

            MediaPlayer.Event.TimeChanged -> post(
                mapOf(
                    "event" to "timeChanged",
                    "positionMs" to mediaPlayer.getTime(),
                    "durationMs" to mediaPlayer.getLength(),
                )
            )

            MediaPlayer.Event.LengthChanged -> post(
                mapOf("event" to "lengthChanged", "durationMs" to event.getLengthChanged())
            )

            MediaPlayer.Event.EndReached -> {
                // Reaching EOF tears the input + decoders down (this is
                // the "killing decoder" / "removing module" / "Program
                // doesn't contain anymore ES" sequence visible in logcat)
                // and closes the fd our Media was opened with. From here,
                // resuming the same Media is not possible — play() must
                // reopen a fresh fd/Media instead, which the reachedEnd
                // flag tells it to do.
                reachedEnd = true
                mediaPlayer.stop()
                post(mapOf("event" to "endReached"))
            }

            MediaPlayer.Event.EncounteredError -> post(
                mapOf(
                    "event" to "error",
                    "message" to "libVLC could not play this file " +
                        "(unsupported codec/container or corrupt data).",
                )
            )

            else -> { /* ESAdded / ESSelected / etc. — not surfaced to Dart */ }
        }
    }

    /**
     * Opens [contentUri] (expected to be a `content://` Uri served by
     * [com.aeidolon.vaultexplorer.ContainerDocumentsProvider]) by resolving
     * it to a raw seekable [android.os.ParcelFileDescriptor] ourselves and
     * handing libVLC that descriptor directly, instead of the Uri.
     *
     * This is the fix for the hang you hit with flutter_vlc_player: libVLC
     * only understands MRLs it can parse itself (file paths, http://,
     * rtsp://, ...). It never resolves `content://` through Android's
     * ContentResolver on its own — so `Media(libVLC, Uri.parse(contentUri))`
     * fails to open and the player sits in "opening" forever. Opening the
     * fd ourselves sidesteps that entirely: libVLC just sees a POSIX file
     * descriptor and reads from it like any other local file, which is
     * exactly what `ContainerDocumentsProvider.openDocument()`'s
     * proxy-fd (backed by the vault's chunked decrypt engine) supports.
     */
    fun setDataSource(contentUri: String, autoPlay: Boolean) {
        if (disposed) return
        lastContentUri = contentUri
        reachedEnd = false
        try {
            mediaPlayer.stop()
        } catch (_: Exception) {
        }
        closeOpenFd()
        // A new item may be a different resolution, so force the next
        // onNewVideoLayout call to actually re-apply a size instead of
        // being skipped as a no-op against the old video's dimensions.
        currentVideoWidth = 0
        currentVideoHeight = 0

        val pfd = context.contentResolver.openFileDescriptor(Uri.parse(contentUri), "r")
        if (pfd == null) {
            post(
                mapOf(
                    "event" to "error",
                    "message" to "Could not open $contentUri (no file descriptor returned).",
                )
            )
            return
        }
        openParcelFd = pfd

        val media = Media(libVLC, pfd.fileDescriptor)
        try {
            // Hardware decode is disabled unconditionally here. What
            // looked at first like a VP9-specific bug turned out not to
            // be: an H.264 stream hit the exact same failure signature —
            //   libvlc decoder: output: 2130708361 unknown, ...
            //   libvlc window: request 3 not implemented
            // 2130708361 is COLOR_FormatSurface (opaque); "request 3" is
            // the vout asking for something the android-display module on
            // this device doesn't implement. Since this reproduces across
            // codecs, it's a device/vout-level MediaCodec-surface
            // integration issue (seen on this Qualcomm CCodec stack), not
            // something we can route around per-codec. Forcing libVLC's
            // own software (FFmpeg/avcodec) decoder sidesteps the broken
            // surface path entirely, at the cost of higher CPU usage than
            // hardware decode would use if it worked.
            media.setHWDecoderEnabled(true, false)
            media.parse(IMedia.Parse.ParseLocal)
findVideoTrack(media)?.let { track ->
    applyVideoSize(track.width, track.height)
    post(mapOf("event" to "sized", "width" to displayWidth(track), "height" to track.height))
}
            mediaPlayer.setMedia(media)
        } finally {
            // Always release our reference, even if setMedia() throws —
            // otherwise this Media is only reclaimed by the finalizer,
            // which logs "finalized but not natively released" and leaks
            // native libVLC resources until GC gets to it.
            media.release()
        }

        if (autoPlay) {
            // Posted through the same mainHandler as the buffer resize
            // queued by applyVideoSize() above, instead of calling
            // mediaPlayer.play() here directly — a single Handler runs its
            // queued runnables in order, so this guarantees the
            // SurfaceTexture is actually resized before the decoder is
            // allowed to start pushing frames into it. Calling play()
            // synchronously here raced that resize: the first frame or
            // two could get pushed into the surface at its old (or
            // default 1x1) size before the resize runnable got its turn,
            // producing a brief flash. That race was always there but
            // invisible on a normal cold open (hidden behind the loading
            // spinner); it becomes visible on replay, where the video
            // widget is already on screen with nothing hiding it.
            mainHandler.post {
                if (!disposed) mediaPlayer.play()
            }
        }
    }

    private fun closeOpenFd() {
        try {
            openParcelFd?.close()
        } catch (e: Exception) {
            Log.w("VlcPlayerEngine", "Error closing previous fd", e)
        }
        openParcelFd = null
    }

    private fun findVideoTrack(media: Media): IMedia.VideoTrack? {
    for (i in 0 until media.trackCount) {
        val track = media.getTrack(i)
        if (track is IMedia.VideoTrack) return track
    }
    return null
}

/** Display width corrected for non-square pixels (e.g. an anamorphic
 *  `pasp` box) — the decode buffer stays at the raw coded size; only the
 *  aspect ratio we report to Dart needs the correction. */
private fun displayWidth(track: IMedia.VideoTrack): Int {
    if (track.sarNum <= 0 || track.sarDen <= 0 || track.sarNum == track.sarDen) return track.width
    return (track.width.toLong() * track.sarNum / track.sarDen).toInt()
}

    fun play() {
        if (disposed) return
        if (reachedEnd) {
            // The Media we had is spent (its fd is closed) — rebuild it
            // from scratch against the same content, same as the very
            // first setDataSource() call, then start playing. This is
            // what makes both the Play button and the app's manual-loop
            // (pause + seekTo(0) + play) work again after EOF.
            val uri = lastContentUri ?: return
            setDataSource(uri, autoPlay = true)
            return
        }
        mediaPlayer.play()
    }

    fun pause() {
        if (!disposed && mediaPlayer.isPlaying) mediaPlayer.pause()
    }

    fun stop() {
        if (!disposed) mediaPlayer.stop()
    }

    fun seekTo(positionMs: Long) {
        if (!disposed) mediaPlayer.setTime(positionMs)
    }

    fun setVolume(volume: Int) {
        if (!disposed) mediaPlayer.setVolume(volume.coerceIn(0, 100))
    }

    fun setRate(rate: Float) {
        if (!disposed) mediaPlayer.setRate(rate)
    }

    fun setLooping(looping: Boolean) {
        if (disposed) return
        mediaPlayer.media?.let {
            it.addOption(if (looping) ":input-repeat=65535" else ":input-repeat=0")
        }
    }

    fun getSpuTracks(): Map<Int, String> {
        if (disposed) return emptyMap()
        val tracks = mediaPlayer.spuTracks ?: return emptyMap()
        return tracks.filter { it.id >= 0 }.associate { it.id to it.name }
    }

    fun setSpuTrack(trackId: Int) {
        if (!disposed) mediaPlayer.setSpuTrack(trackId)
    }

    fun getAudioTracks(): Map<Int, String> {
        if (disposed) return emptyMap()
        val tracks = mediaPlayer.audioTracks ?: return emptyMap()
        return tracks.filter { it.id >= 0 }.associate { it.id to it.name }
    }

    fun setAudioTrack(trackId: Int) {
        if (!disposed) mediaPlayer.setAudioTrack(trackId)
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        try {
            mediaPlayer.stop()
        } catch (_: Exception) {
        }
        mediaPlayer.setEventListener(null)
        try {
            mediaPlayer.vlcVout.detachViews()
        } catch (_: Exception) {
        }
        mediaPlayer.release()
        closeOpenFd()
        textureEntry.release()
    }
}