package com.aeidolon.vaultexplorer.engine

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.media3.common.Player
import androidx.media3.session.MediaSession
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.VeLog
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers
import com.aeidolon.vaultexplorer.service.VaultMediaPlaybackService
import com.aeidolon.vaultexplorer.util.NotificationLocale

/**
 * Owns the system-facing side of playing media from an unlocked vault: the
 * `MediaSession` (lock screen controls, Bluetooth/headset buttons, the media
 * notification's token) and the hand-off to [VaultMediaPlaybackService],
 * which keeps playback alive in the background and posts the notification.
 *
 * The ExoPlayer itself stays owned by [NativePlayerManager]; this object only
 * ever *wraps* it ([VaultSessionPlayer]) while it is playing.
 *
 * ## Lifecycle
 * - A session is created the first time the player reports `isPlaying`
 *   ([onPlaying]) for a vault item opened from the media viewer, never merely
 *   because a file was opened -- so browsing/previewing doesn't spawn a
 *   notification.
 * - The Dart viewer releases and recreates the native player on every item
 *   change. [onPlayerReleasing] leaves the MediaSession and notification in
 *   place during the handoff; the next [onPlaying] rebinds the same session
 *   token to the new player. If the viewer closes, [RELEASE_GRACE_MS] bounds
 *   how long the playback window stays open. This also keeps background
 *   auto-advance working when Android 12+ refuses a new background service.
 * - [end] closes everything: the viewer is gone (grace expired), the user
 *   pressed Stop / dismissed the notification, playback finished with
 *   nothing to advance to, or the vault was locked.
 *
 * ## Vault lock
 * Playback is bound to a volume. [ContainerSessionRegistry] reports every
 * session removal (manual lock, auto-lock, "lock all", panic, USB detach),
 * and a removal of the playing volume stops the player and tears the
 * notification down -- nothing from a locked vault stays on the lock screen.
 *
 * Main thread only, except [onVolumeRemoved] which hops to it.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal object VaultPlaybackSession {
    private const val TAG = "VaultPlaybackSession"
    private const val SESSION_ID = "vault_media_session"

    /** How long the playback window survives with no player (item change, viewer closing). */
    private const val RELEASE_GRACE_MS = 5_000L

    /** How long a finished item with nothing after it keeps its notification. */
    private const val ENDED_LINGER_MS = 8_000L

    /**
     * Whether the decrypted file name is published to the media notification,
     * the lock screen and connected devices (Bluetooth displays, watches,
     * cars). Off on purpose: those surfaces are outside the app's control and
     * are not covered by the "nothing decrypted leaves the app" guarantee --
     * a generic label is shown instead (the decoy identity when Mask Mode is
     * active). Tags embedded in the media are never published either way.
     */
    @Volatile
    private var showFileNames = false

    /** What [NativePlayerManager] lets the session do to the real player. */
    interface Host {
        fun play()
        fun pause()
        fun skipToNext()
        fun skipToPrevious()

        /** The vault backing the current item was locked: stop reading from it. */
        fun stopForLock()
    }

    /** Point-in-time view of the session for [VaultMediaPlaybackService]. */
    class Snapshot(
        val session: MediaSession,
        /** Actively playing (or buffering with play intended): worth being a foreground service. */
        val playing: Boolean,
        /** Whether the toggle button should currently offer "pause". */
        val showsPause: Boolean,
        val hasPrevious: Boolean,
        val hasNext: Boolean,
        val title: CharSequence,
        val playlistPosition: String?,
    )

    private val mainHandler = Handler(Looper.getMainLooper())

    private var appContext: Context? = null
    private var host: Host? = null
    private var rawPlayer: Player? = null
    private var sessionPlayer: VaultSessionPlayer? = null
    private var mediaSession: MediaSession? = null

    private var volId = -1
    private var fileName: String? = null
    private var navigationHasPrevious = false
    private var navigationHasNext = false
    private var currentPosition = 0
    private var totalItems = 0

    private var windowOpen = false
    private var lockListenerRegistered = false
    private var graceRunnable: Runnable? = null
    private var endedRunnable: Runnable? = null

    private val sessionHost = object : VaultSessionPlayer.Host {
        override fun onSessionPlay() {
            host?.play()
        }

        override fun onSessionStop() {
            stopByUser()
        }

        override fun onSessionSkipToNext() {
            host?.skipToNext()
        }

        override fun onSessionSkipToPrevious() {
            host?.skipToPrevious()
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            refreshService()
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            refreshService()
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            updateEndedTimer(playbackState)
            refreshService()
        }
    }

    // --- Called by NativePlayerManager ---

    /** The player started playing a vault item opened from the media viewer. */
    fun onPlaying(context: Context, player: Player, host: Host, volId: Int, filePath: String) {
        appContext = context.applicationContext
        this.host = host
        this.volId = volId
        this.fileName = filePath.substringAfterLast('/')
        registerLockListener()
        cancelGraceTimer()

        if (mediaSession != null && rawPlayer === player) {
            sessionPlayer?.setMetadata(displayTitle(), playlistPosition())
            refreshService()
            return
        }
        if (mediaSession != null && windowOpen && attachPlayer(player)) {
            refreshService()
            return
        }
        // Adoption can fail only if Media3 rejects the new player. Recover
        // with a new session so playback continues to receive controls.
        if (mediaSession != null) releaseSession()
        if (!createSession(player)) {
            // The window may still be open from the previous item; with no
            // session to adopt it, don't leave a service lingering.
            if (windowOpen) end()
            return
        }
        windowOpen = true
        VaultMediaPlaybackService.show(context.applicationContext)
    }

    /** A new item was loaded into the player. */
    fun onMediaChanged(volId: Int, filePath: String) {
        this.volId = volId
        this.fileName = filePath.substringAfterLast('/')
        sessionPlayer?.setMetadata(displayTitle(), playlistPosition())
        refreshService()
    }

    /**
     * [player] is about to be released. Must run *before* `player.release()`
     * so its listener can be removed while the object is still live. The
     * MediaSession stays alive with the old wrapper until the next item binds.
     */
    fun onPlayerReleasing(player: Player) {
        if (rawPlayer !== player) return
        runCatching { player.removeListener(playerListener) }
        rawPlayer = null
        if (windowOpen) scheduleGraceTimer()
    }

    /** Previous/next availability, as decided by the Dart playlist. */
    fun setNavigation(
        hasPrevious: Boolean,
        hasNext: Boolean,
        currentPosition: Int,
        totalItems: Int,
    ) {
        navigationHasPrevious = hasPrevious
        navigationHasNext = hasNext
        this.currentPosition = currentPosition
        this.totalItems = totalItems
        sessionPlayer?.setNavigation(hasPrevious, hasNext)
        sessionPlayer?.setMetadata(displayTitle(), playlistPosition())
        refreshService()
    }

    /** Updates the opt-in that controls publication of decrypted file names. */
    fun setShowFileNames(show: Boolean) {
        if (showFileNames == show) return
        showFileNames = show
        sessionPlayer?.setMetadata(displayTitle(), playlistPosition())
        refreshService()
    }

    // --- Called by VaultMediaPlaybackService (notification actions) ---

    fun togglePlayPause() {
        val player = rawPlayer ?: return
        val h = host ?: return
        val state = player.playbackState
        val isPlayingIntent = player.playWhenReady &&
            state != Player.STATE_ENDED && state != Player.STATE_IDLE
        if (isPlayingIntent) h.pause() else h.play()
    }

    fun skipToNext() {
        if (navigationHasNext) host?.skipToNext()
    }

    fun skipToPrevious() {
        if (navigationHasPrevious) host?.skipToPrevious()
    }

    /** The user pressed Stop or swiped the notification away. */
    fun stopByUser() {
        host?.pause()
        // Posted, not run inline: this can be reached from inside a session
        // command callback, and a session must not be released while it is
        // still dispatching one.
        mainHandler.post { end() }
    }

    fun snapshot(): Snapshot? {
        val session = mediaSession ?: return null
        val context = appContext ?: return null
        val player = rawPlayer
        if (player == null) {
            // Keep the media-style notification attached to the same session
            // token while the viewer swaps per-item players.
            return Snapshot(
                session = session,
                playing = false,
                showsPause = false,
                hasPrevious = navigationHasPrevious,
                hasNext = navigationHasNext,
                title = displayTitle(context),
                playlistPosition = playlistPosition(),
            )
        }
        val state = player.playbackState
        val playWhenReady = player.playWhenReady
        return Snapshot(
            session = session,
            playing = player.isPlaying || (playWhenReady && state == Player.STATE_BUFFERING),
            showsPause = playWhenReady && state != Player.STATE_ENDED && state != Player.STATE_IDLE,
            hasPrevious = navigationHasPrevious,
            hasNext = navigationHasNext,
            title = displayTitle(context),
            playlistPosition = playlistPosition(),
        )
    }

    /** Closes the playback window: session, foreground service and notification. */
    fun end() {
        cancelGraceTimer()
        cancelEndedTimer()
        releaseSession()
        windowOpen = false
        VaultMediaPlaybackService.stop()
    }

    // --- Vault lock ---

    private fun registerLockListener() {
        if (lockListenerRegistered) return
        lockListenerRegistered = true
        ContainerSessionRegistry.addSessionRemovedListener { removedVolId -> onVolumeRemoved(removedVolId) }
    }

    /** Any thread: [ContainerSessionRegistry.removeSession] runs on I/O threads. */
    private fun onVolumeRemoved(removedVolId: Int) {
        mainHandler.post {
            if (windowOpen && removedVolId == volId) {
                VeLog.i(TAG) { "Vault $removedVolId locked during playback -> ending media session" }
                host?.stopForLock()
                end()
            }
        }
    }

    // --- Internals ---

    private fun createSession(player: Player): Boolean {
        val context = appContext ?: return false
        return try {
            val wrapper = VaultSessionPlayer(player, sessionHost)
            wrapper.setNavigation(navigationHasPrevious, navigationHasNext)
            wrapper.setMetadata(displayTitle(context), playlistPosition())
            val contentIntent = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val session = MediaSession.Builder(context, wrapper)
                .setId(SESSION_ID)
                .setSessionActivity(contentIntent)
                .build()
            player.addListener(playerListener)
            rawPlayer = player
            sessionPlayer = wrapper
            mediaSession = session
            true
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "Could not create media session; playback continues without one" }
            false
        }
    }

    /** Rebinds the existing session token to a new per-item player. */
    private fun attachPlayer(player: Player): Boolean {
        val context = appContext ?: return false
        val session = mediaSession ?: return false
        return try {
            val wrapper = VaultSessionPlayer(player, sessionHost)
            wrapper.setNavigation(navigationHasPrevious, navigationHasNext)
            wrapper.setMetadata(displayTitle(context), playlistPosition())
            session.setPlayer(wrapper)
            player.addListener(playerListener)
            rawPlayer = player
            sessionPlayer = wrapper
            true
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "Could not rebind media session to the next item" }
            false
        }
    }

    private fun releaseSession() {
        cancelEndedTimer()
        rawPlayer?.let { runCatching { it.removeListener(playerListener) } }
        mediaSession?.let { runCatching { it.release() } }
        mediaSession = null
        sessionPlayer = null
        rawPlayer = null
    }

    private fun displayTitle(context: Context): CharSequence {
        if (showFileNames) {
            fileName?.takeIf { it.isNotBlank() }?.let { return it }
        }
        return genericTitle(context)
    }

    private fun displayTitle(): CharSequence {
        val context = appContext ?: return ""
        return displayTitle(context)
    }

    private fun playlistPosition(): String? =
        if (totalItems > 0 && currentPosition in 1..totalItems) {
            "$currentPosition/$totalItems"
        } else {
            null
        }

    /** The label shown instead of a file name: the decoy identity in Mask Mode. */
    fun genericTitle(context: Context): String {
        val localized = NotificationLocale.wrap(context)
        return if (DisguiseModeHandlers.isDecoyActive(context)) {
            localized.getString(R.string.decoy_app_name)
        } else {
            localized.getString(R.string.vault_media_notification_title)
        }
    }

    private fun refreshService() {
        if (windowOpen && rawPlayer != null) VaultMediaPlaybackService.refresh()
    }

    /** Whether decrypted names are currently allowed on external media surfaces. */
    fun areFileNamesVisible(): Boolean = showFileNames

    private fun scheduleGraceTimer() {
        cancelGraceTimer()
        val runnable = Runnable {
            graceRunnable = null
            if (mediaSession == null) {
                VeLog.d(TAG) { "No player came back within the grace period -> ending media session" }
                end()
            }
        }
        graceRunnable = runnable
        mainHandler.postDelayed(runnable, RELEASE_GRACE_MS)
    }

    private fun cancelGraceTimer() {
        graceRunnable?.let { mainHandler.removeCallbacks(it) }
        graceRunnable = null
    }

    /** Finished with nothing queued after it: don't leave a dead notification behind. */
    private fun updateEndedTimer(playbackState: Int) {
        cancelEndedTimer()
        if (playbackState != Player.STATE_ENDED || navigationHasNext) return
        val runnable = Runnable {
            endedRunnable = null
            if (rawPlayer?.playbackState == Player.STATE_ENDED && !navigationHasNext) end()
        }
        endedRunnable = runnable
        mainHandler.postDelayed(runnable, ENDED_LINGER_MS)
    }

    private fun cancelEndedTimer() {
        endedRunnable?.let { mainHandler.removeCallbacks(it) }
        endedRunnable = null
    }
}
