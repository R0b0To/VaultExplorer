package com.aeidolon.vaultexplorer.engine

import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import java.lang.reflect.InvocationHandler
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Proxy

/**
 * The [Player] a `MediaSession` exposes to the system (lock screen controls,
 * the media notification, Bluetooth/AVRCP, ...) on top of the real ExoPlayer
 * owned by [NativePlayerManager]. It exists for three reasons:
 *
 * 1. **Nothing from inside the vault leaks through session metadata.**
 *    ExoPlayer's own `mediaMetadata` is merged from tags embedded in the
 *    decrypted media (ID3 title/artist, cover art, ...), and the session
 *    republishes whatever the player reports -- including the value carried
 *    by `onMediaMetadataChanged` events. Both paths are replaced here with
 *    [setMetadata]'s values. The title is generic unless the user enables
 *    file-name publication, and the artist field carries only playlist
 *    position. Nothing else is published.
 * 2. **Previous / Next.** The ExoPlayer only ever holds one item; the
 *    playlist lives in the Dart media viewer. [setNavigation] advertises the
 *    skip commands, and the seekTo{Next,Previous}* calls are forwarded to the
 *    viewer through [Host] instead of acting on the single-item player.
 * 3. **Play goes through [NativePlayerManager.play]**, so the "restart from
 *    the beginning if it already ended" rule applies to lock screen / media
 *    button presses exactly as it does to the in-app button.
 *
 * Main thread only, like the player it wraps.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class VaultSessionPlayer(
    player: Player,
    private val host: Host,
) : ForwardingPlayer(player) {

    interface Host {
        fun onSessionPlay()
        fun onSessionStop()
        fun onSessionSkipToNext()
        fun onSessionSkipToPrevious()
    }

    private companion object {
        /** Same convention as ExoPlayer: "previous" past this point restarts the item. */
        const val RESTART_INSTEAD_OF_PREVIOUS_MS = 3_000L
    }

    private var navigationHasPrevious = false
    private var navigationHasNext = false
    private var sessionMetadata: MediaMetadata = MediaMetadata.EMPTY

    // Original listener -> the sanitizing proxy actually registered on the
    // wrapped player. Needed so removeListener() removes the same instance.
    private val registeredListeners = LinkedHashMap<Player.Listener, Player.Listener>()

    fun setNavigation(hasPrevious: Boolean, hasNext: Boolean) {
        if (navigationHasPrevious == hasPrevious && navigationHasNext == hasNext) return
        navigationHasPrevious = hasPrevious
        navigationHasNext = hasNext
        val commands = getAvailableCommands()
        for (listener in registeredListeners.keys.toList()) {
            listener.onAvailableCommandsChanged(commands)
        }
    }

    fun setMetadata(title: CharSequence?, playlistPosition: String?) {
        val updated = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(playlistPosition)
            .build()
        if (updated == sessionMetadata) return
        sessionMetadata = updated
        for (listener in registeredListeners.keys.toList()) {
            listener.onMediaMetadataChanged(updated)
        }
    }

    // --- Listener plumbing: strip embedded-tag metadata from events ---

    override fun addListener(listener: Player.Listener) {
        val proxy = registeredListeners.getOrPut(listener) { sanitizingProxy(listener) }
        super.addListener(proxy)
    }

    override fun removeListener(listener: Player.Listener) {
        val proxy = registeredListeners.remove(listener) ?: listener
        super.removeListener(proxy)
    }

    /**
     * Wraps [target] so every callback reaches it unchanged except
     * `onMediaMetadataChanged`, whose argument (the wrapped player's merged
     * metadata) is replaced by [sessionMetadata]. A dynamic proxy rather than
     * a hand-written delegate so the ~40 other [Player.Listener] callbacks --
     * including ones added in future Media3 versions -- keep flowing through
     * without having to be listed here.
     */
    private fun sanitizingProxy(target: Player.Listener): Player.Listener {
        val handler = InvocationHandler { proxy, method, args ->
            when {
                method.declaringClass == Any::class.java -> when (method.name) {
                    "equals" -> proxy === args?.firstOrNull()
                    "hashCode" -> System.identityHashCode(proxy)
                    else -> "SanitizingListener($target)"
                }
                method.name == "onMediaMetadataChanged" && args?.size == 1 -> {
                    target.onMediaMetadataChanged(sessionMetadata)
                    null
                }
                else -> try {
                    method.invoke(target, *(args ?: emptyArray()))
                } catch (e: InvocationTargetException) {
                    throw e.targetException ?: e
                }
            }
        }
        return Proxy.newProxyInstance(
            Player.Listener::class.java.classLoader,
            arrayOf<Class<*>>(Player.Listener::class.java),
            handler,
        ) as Player.Listener
    }

    // --- Published state ---

    override fun getMediaMetadata(): MediaMetadata = sessionMetadata

    override fun getAvailableCommands(): Player.Commands =
        super.getAvailableCommands().buildUpon()
            .addIf(Player.COMMAND_SEEK_TO_NEXT, navigationHasNext)
            .addIf(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM, navigationHasNext)
            .removeIf(Player.COMMAND_SEEK_TO_NEXT, !navigationHasNext)
            .removeIf(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM, !navigationHasNext)
            .addIf(Player.COMMAND_SEEK_TO_PREVIOUS, navigationHasPrevious)
            .addIf(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM, navigationHasPrevious)
            .removeIf(Player.COMMAND_SEEK_TO_PREVIOUS, !navigationHasPrevious)
            .removeIf(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM, !navigationHasPrevious)
            // A controller must not be able to swap in arbitrary media or
            // change repeat/shuffle behind the viewer's back.
            .removeAll(
                Player.COMMAND_SET_MEDIA_ITEM,
                Player.COMMAND_CHANGE_MEDIA_ITEMS,
                Player.COMMAND_PREPARE,
                Player.COMMAND_SET_REPEAT_MODE,
                Player.COMMAND_SET_SHUFFLE_MODE,
            )
            .build()

    override fun isCommandAvailable(command: Int): Boolean =
        getAvailableCommands().contains(command)

    override fun hasNextMediaItem(): Boolean = navigationHasNext

    override fun hasPreviousMediaItem(): Boolean = navigationHasPrevious

    // --- Commands from the system ---

    override fun play() {
        host.onSessionPlay()
    }

    override fun setPlayWhenReady(playWhenReady: Boolean) {
        if (playWhenReady) host.onSessionPlay() else super.setPlayWhenReady(false)
    }

    override fun stop() {
        host.onSessionStop()
    }

    override fun seekToNext() {
        if (navigationHasNext) host.onSessionSkipToNext()
    }

    override fun seekToNextMediaItem() {
        if (navigationHasNext) host.onSessionSkipToNext()
    }

    override fun seekToPrevious() {
        if (!navigationHasPrevious || getCurrentPosition() > RESTART_INSTEAD_OF_PREVIOUS_MS) {
            seekTo(0L)
        } else {
            host.onSessionSkipToPrevious()
        }
    }

    override fun seekToPreviousMediaItem() {
        if (navigationHasPrevious) host.onSessionSkipToPrevious()
    }
}
