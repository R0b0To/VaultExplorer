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
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

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
     *
     * Deliberately does NOT include `-vv` (verbose level 2) — that turns on
     * full trace logging for every module load / demux step / frame, which
     * is genuine overhead on every open and every decode, not just log
     * spam. Bump this back to `-vv` only when you're actively diagnosing a
     * libVLC issue, never in a build you're measuring performance on.
     */
    private val options = arrayListOf(
        "--no-sub-autodetect-file",
    )

    fun get(context: Context): LibVLC {
        return libVLC ?: synchronized(this) {
            libVLC ?: LibVLC(context.applicationContext, options).also { libVLC = it }
        }
    }

    /**
     * Forces the LibVLC singleton to be created now instead of lazily on
     * the first video a user opens. Constructing [LibVLC] is the one
     * genuinely fixed ~100-300ms cost in this whole pipeline (module bank +
     * plugin cache init) — it's a one-time cost either way, but paying it
     * during app startup means the *first* video someone taps doesn't feel
     * slower than every video after it. Safe to call from a background
     * thread and safe to call more than once; call it once, early, e.g.
     * from `MainActivity.configureFlutterEngine()` on a background thread.
     */
    fun warmUp(context: Context) {
        get(context)
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

    // setDataSource() used to open the content:// fd inline, on whatever
    // thread called it — which is Flutter's platform/UI thread, since
    // VlcPlayerPlugin's MethodChannel has no TaskQueue. openFileDescriptor()
    // for a container-backed Uri isn't cheap: ContainerDocumentsProvider
    // spins up a fresh HandlerThread and does a StorageManager
    // openProxyFileDescriptor() IPC round trip per call. Running that on the
    // calling thread stalled the whole app's rendering for however long the
    // open took, on every single video. This executor moves that blocking
    // work off the platform thread — mirroring how VLC's own app wraps
    // media open/prepare in `withContext(Dispatchers.IO)` — while every
    // call that actually touches mediaPlayer/vout still runs via
    // mainHandler, unchanged from before.
    //
    // Priority is bumped to THREAD_PRIORITY_URGENT_AUDIO on purpose. A
    // plain background thread gets default JVM/Android scheduling — the
    // same class as whatever's driving the loading-spinner animation on
    // the UI/render threads. Under real contention that's enough to
    // genuinely starve it: the open itself finishes in a few ms once it
    // actually gets a CPU slot, but can otherwise sit waiting far longer,
    // which shows up as "stuck spinner until I touch the screen" — a
    // touch briefly triggers Android's input-boost scheduling on most
    // devices, which is exactly what unblocks it. This is the same
    // priority class ExoPlayer/MediaCodec-adjacent loading threads use for
    // the same reason.
    private val ioExecutor = Executors.newSingleThreadExecutor { r ->
        Thread({
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)
            r.run()
        }, "vlc-engine-io-$playerId")
    }

    // Bumped on every setDataSource() call. A background open only applies
    // its result if it's still the most recent one requested, so a fast
    // second setDataSource() (user swipes past this item again before the
    // first open finished) discards the stale in-flight open instead of
    // racing it onto the player.
    private val openGeneration = AtomicInteger(0)

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

    // True once mediaPlayer.setMedia() has actually run for the current
    // open. setDataSource() now returns to Dart (and initialize()'s Future
    // resolves) before this is true — the fd-open + setMedia() happen
    // later, on ioExecutor + a mainHandler hop. mediaPlayer.play() called
    // with no Media attached is a silent no-op in libVLC, NOT a "play once
    // ready" queue, and MediaPlayerWidget calls controller.play() the
    // moment initialize() resolves — so without this flag, that first
    // play() call would race the still-in-flight open, do nothing, and
    // nothing would ever call play() again. play() checks this and defers
    // via pendingAutoPlay instead of calling into libVLC too early.
    private var mediaReady = false

    // Sticky "play once mediaReady flips true" intent — set from the
    // autoPlay param at the start of every setDataSource() call, and
    // upgraded to true by an explicit play() that arrives before the open
    // it applies to has finished. Consumed (and cleared) exactly once, by
    // the same mainHandler completion that flips mediaReady.
    private var pendingAutoPlay = false

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
     * Kicks off opening [contentUri] and returns immediately — it does not
     * wait for the fd to open or for libVLC to be ready to play. Progress
     * comes back later over the event channel (`opening`, `playing`,
     * `error`, ...), same as before.
     *
     * The actual open runs on [ioExecutor], off Flutter's platform thread:
     * opening a container-backed content:// Uri is a blocking call
     * (ContainerDocumentsProvider spins up a proxy thread + does a
     * StorageManager IPC round trip), and running that inline here used to
     * stall the whole app's UI for the duration on every video. Everything
     * that actually touches mediaPlayer/vout still happens on mainHandler,
     * exactly as before — only the fd-open itself moved.
     *
     * Also deliberately does NOT probe the file for its video track before
     * calling setMedia() the way the previous version did. That probe
     * (`media.trackCount` / `media.getTrack()`) forces libVLC to
     * synchronously demux the file just to read dimensions early, and nets
     * nothing: the Dart side only ever renders once `isInitialized` is
     * true, which is driven by the `playing`/`timeChanged` events (which
     * already carry width/height) — never by the eager probe. Skipping it
     * removes a full extra blocking parse per video for zero behavior
     * change. Sizing still comes from two places, both already handled:
     * `onNewVideoLayout` (via [applyVideoSize]) as soon as libVLC's vout
     * negotiates a size, and the `Playing` event handler below.
     */
    fun setDataSource(contentUri: String, autoPlay: Boolean) {
        if (disposed) return
        val generation = openGeneration.incrementAndGet()
        lastContentUri = contentUri
        reachedEnd = false
        mediaReady = false
        pendingAutoPlay = autoPlay
        // A new item may be a different resolution, so force the next
        // onNewVideoLayout call to actually re-apply a size instead of
        // being skipped as a no-op against the old video's dimensions.
        currentVideoWidth = 0
        currentVideoHeight = 0

        ioExecutor.execute {
            if (disposed || generation != openGeneration.get()) return@execute

            val pfd = try {
                context.contentResolver.openFileDescriptor(Uri.parse(contentUri), "r")
            } catch (e: Exception) {
                post(
                    mapOf(
                        "event" to "error",
                        "message" to "Could not open $contentUri (${e.message}).",
                    )
                )
                return@execute
            }

            if (pfd == null) {
                post(
                    mapOf(
                        "event" to "error",
                        "message" to "Could not open $contentUri (no file descriptor returned).",
                    )
                )
                return@execute
            }

            mainHandler.post {
                // Superseded by a newer setDataSource() (or disposed)
                // while the open above was in flight — discard this fd
                // rather than race it onto the player.
                if (disposed || generation != openGeneration.get()) {
                    try {
                        pfd.close()
                    } catch (_: Exception) {
                    }
                    return@post
                }

                try {
                    mediaPlayer.stop()
                } catch (_: Exception) {
                }
                closeOpenFd()
                openParcelFd = pfd

                val media = Media(libVLC, pfd.fileDescriptor)
                try {
                    mediaPlayer.setMedia(media)
                } finally {
                    // Always release our reference, even if setMedia()
                    // throws — otherwise this Media is only reclaimed by
                    // the finalizer, which logs "finalized but not
                    // natively released" and leaks native libVLC
                    // resources until GC gets to it.
                    media.release()
                }

                mediaReady = true
                // Not "if (autoPlay)" — pendingAutoPlay also captures a
                // play() that arrived from Dart after this setDataSource()
                // call but before this completion ran (the common case:
                // MediaPlayerWidget calls controller.play() the instant
                // initialize() resolves, which is now well before the open
                // above finishes). See play() below.
                if (pendingAutoPlay && !disposed) {
                    mediaPlayer.play()
                }
                pendingAutoPlay = false
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
        if (!mediaReady) {
            // A setDataSource() open is still in flight — there's no
            // Media attached to this mediaPlayer yet, and calling play()
            // against nothing is a silent no-op in libVLC, not something
            // that queues itself for later. Record the intent instead;
            // setDataSource()'s completion on mainHandler calls play() for
            // us as soon as mediaReady flips true.
            pendingAutoPlay = true
            return
        }
        mediaPlayer.play()
    }

    fun pause() {
        if (disposed) return
        pendingAutoPlay = false
        if (mediaPlayer.isPlaying) mediaPlayer.pause()
    }

    fun stop() {
        if (disposed) return
        pendingAutoPlay = false
        mediaPlayer.stop()
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
        // Invalidate any open() in flight on ioExecutor so its mainHandler
        // completion (if it hasn't run yet) closes the fd and bails instead
        // of touching a mediaPlayer we're about to release.
        openGeneration.incrementAndGet()
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
        ioExecutor.shutdown()
    }
}