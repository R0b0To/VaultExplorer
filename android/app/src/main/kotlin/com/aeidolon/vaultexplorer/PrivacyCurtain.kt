package com.aeidolon.vaultexplorer

import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup

/**
 * Covers the Activity's content with a plain, branding-free scrim the
 * instant the window stops being the foreground window (screen off,
 * device lock, task switch, a system picker taking over, ...), and only
 * reveals the content again once Flutter has actually painted a frame
 * after resuming - never on a blind guess.
 *
 * ## Why this exists
 *
 * [MainActivity.onPause] is where [SessionLockController] reacts to the
 * screen turning off - it updates the Dart widget tree (pushes the
 * Flutter-side LockGateScreen, or flips a container to its locked
 * placeholder) so that, logically, the sensitive screen is already gone.
 * But Flutter's `SchedulerBinding` stops producing frames as soon as the
 * app leaves `resumed`, so that widget-tree change is never actually
 * rasterized before the display goes dark. Android is free to keep the
 * last real frame that *was* rasterized - the unlocked container content -
 * sitting in this Activity's Surface. When the device is unlocked, that
 * stale frame is what gets shown first, until Flutter resumes and finally
 * paints the already-updated tree. That's the "last frame flashes on
 * unlock" bug.
 *
 * A plain [View] like this one is drawn by the ordinary Android view
 * pipeline, not Flutter's engine, so toggling it from the real
 * `onPause`/`onResume` callbacks is not subject to that same frame-
 * scheduling gap. Showing it is synchronous and unconditional. Hiding it
 * is not on a timer: [armPendingReveal] waits for [reveal] to be called
 * with fresh confirmation from Dart (`ResumePaintSignal`, wired through
 * `notifyResumedFramePainted`) that a post-resume frame actually painted,
 * because how long that takes varies - it can be much longer than one or
 * two frames if the GPU surface had to be recreated, on a slower device,
 * or under memory pressure. A short safety-net timeout still exists so a
 * missed/late signal can never leave the curtain stuck up forever.
 *
 * Note this is one of two complementary fixes for the same bug -
 * [SystemPermissionHandlers.setBackgroundProtectionActive] forces
 * FLAG_SECURE for the same paused window, which closes a separate leak
 * path: the OS's own task-snapshot mechanism, which this curtain (being
 * purely about the *live* frame) has no influence over.
 */
class PrivacyCurtain(private val activity: MainActivity) {

    private var curtain: View? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // True only between a completed armPendingReveal() and the matching
    // reveal(), i.e. "resumed and waiting to confirm it's safe to show
    // content again". Guards against a late/stray reveal() (a delayed
    // safety-net Runnable, or a slow-arriving Dart signal from a resume
    // that's already been superseded) revealing the curtain during a
    // *later* pause it doesn't belong to.
    private var isForeground = false

    // Bumped on every show(); a safety-net Runnable captures the token it
    // was armed with and checks it still matches before firing, so a
    // pause/resume/pause happening faster than the timeout can't cause a
    // stale timeout to hide a curtain a later pause re-showed.
    private var revealToken = 0
    private var pendingSafetyNet: Runnable? = null

    /** Call once, after `super.onCreate()`, while the content view exists. */
    fun install() {
        val root = activity.findViewById<ViewGroup>(android.R.id.content) ?: return

        val background = TypedValue()
        activity.theme.resolveAttribute(android.R.attr.colorBackground, background, true)

        val curtainView = View(activity).apply {
            setBackgroundColor(background.data)
            visibility = View.GONE
            // Swallow touches/focus so nothing underneath is reachable
            // while the curtain is up.
            isClickable = true
            isFocusable = true
        }
        root.addView(
            curtainView,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )
        curtain = curtainView
    }

    /**
     * Call from [MainActivity.onPause]. Must run synchronously on the call
     * path from `onPause` (no posting/delaying) so the curtain is already
     * part of the next draw pass before the window leaves the foreground.
     */
    fun show() {
        isForeground = false
        pendingSafetyNet?.let { mainHandler.removeCallbacks(it) }
        pendingSafetyNet = null
        revealToken++
        curtain?.apply {
            bringToFront()
            visibility = View.VISIBLE
        }
    }

    /**
     * Call from [MainActivity.onResume]. Keeps the curtain up until
     * [reveal] is called - either by the `notifyResumedFramePainted`
     * channel call once Dart confirms a post-resume frame painted, or by
     * the [safetyNetMs] fallback below, whichever comes first.
     */
    fun armPendingReveal(safetyNetMs: Long = 600L) {
        if (curtain?.visibility != View.VISIBLE) return
        isForeground = true
        pendingSafetyNet?.let { mainHandler.removeCallbacks(it) }
        val tokenAtArmTime = revealToken
        val runnable = Runnable { reveal(tokenAtArmTime) }
        pendingSafetyNet = runnable
        mainHandler.postDelayed(runnable, safetyNetMs)
    }

    /**
     * Hides the curtain. Called either from the `notifyResumedFramePainted`
     * channel handler (no args - always applies to the current cycle) or
     * from the safety-net Runnable scheduled in [armPendingReveal] (passes
     * the token it was armed with, so a superseded timeout is a no-op).
     */
    fun reveal(expectedToken: Int = revealToken) {
        if (!isForeground) return
        if (expectedToken != revealToken) return
        pendingSafetyNet?.let { mainHandler.removeCallbacks(it) }
        pendingSafetyNet = null
        if (!activity.isFinishing && !activity.isDestroyed) {
            curtain?.visibility = View.GONE
        }
    }
}