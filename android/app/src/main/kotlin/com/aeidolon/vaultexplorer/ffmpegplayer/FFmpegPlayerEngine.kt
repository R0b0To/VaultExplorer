package com.aeidolon.vaultexplorer.ffmpegplayer

import android.content.Context
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
}