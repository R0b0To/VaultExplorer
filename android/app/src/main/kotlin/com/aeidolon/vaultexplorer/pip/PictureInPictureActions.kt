package com.aeidolon.vaultexplorer.pip

import android.app.Activity
import android.app.PendingIntent
import android.app.RemoteAction
import android.content.Intent
import android.graphics.drawable.Icon
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.engine.VaultPlaybackSession
import com.aeidolon.vaultexplorer.util.NotificationLocale

/**
 * The buttons inside the picture-in-picture window.
 *
 * Android shows the media session's own controls in a PiP window only while the
 * activity has not set any actions of its own, so as soon as the window needs a
 * button the session does not have ("audio only") it has to draw all of them.
 * That is what this builds, from the same session the notification uses:
 *
 *     [previous]  play / pause  [next]  audio only
 *
 * Previous / next only appear when the playlist has such an item, and Android
 * limits how many buttons a window can show (usually three); when the list is
 * too long, the buttons that matter least are dropped: play / pause and audio
 * only always stay, then next, then previous.
 *
 * Taps come back as a broadcast ([BROADCAST_ACTION]) that
 * [PictureInPictureController] receives, because a PiP button is a
 * `PendingIntent`. No button is offered while there is no media session: the
 * window then simply has no controls, as before.
 */
internal object PictureInPictureActions {

    const val BROADCAST_ACTION = "com.aeidolon.vaultexplorer.action.PIP_CONTROL"
    const val EXTRA_CONTROL = "control"

    const val CONTROL_PREVIOUS = 1
    const val CONTROL_TOGGLE = 2
    const val CONTROL_NEXT = 3
    const val CONTROL_AUDIO_ONLY = 4

    /** The buttons for the window of [activity], in the order they are shown. */
    fun build(activity: Activity): List<RemoteAction> {
        val snapshot = VaultPlaybackSession.snapshot() ?: return emptyList()
        val localized = NotificationLocale.wrap(activity)

        // Most important first: what survives when the window has little room.
        val wanted = ArrayList<Int>(4)
        wanted.add(CONTROL_TOGGLE)
        wanted.add(CONTROL_AUDIO_ONLY)
        if (snapshot.hasNext) wanted.add(CONTROL_NEXT)
        if (snapshot.hasPrevious) wanted.add(CONTROL_PREVIOUS)
        val chosen = wanted.take(activity.maxNumPictureInPictureActions.coerceAtLeast(1)).toSet()

        // ...and the order they are laid out in.
        val layout = intArrayOf(CONTROL_PREVIOUS, CONTROL_TOGGLE, CONTROL_NEXT, CONTROL_AUDIO_ONLY)
        val actions = ArrayList<RemoteAction>(layout.size)
        for (control in layout) {
            if (control !in chosen) continue
            actions.add(
                when (control) {
                    CONTROL_PREVIOUS -> action(
                        activity,
                        control,
                        R.drawable.ic_vault_media_previous,
                        localized.getString(R.string.vault_media_action_previous),
                    )
                    CONTROL_TOGGLE ->
                        if (snapshot.showsPause) {
                            action(
                                activity,
                                control,
                                R.drawable.ic_vault_media_pause,
                                localized.getString(R.string.vault_media_action_pause),
                            )
                        } else {
                            action(
                                activity,
                                control,
                                R.drawable.ic_vault_media_play,
                                localized.getString(R.string.vault_media_action_play),
                            )
                        }
                    CONTROL_NEXT -> action(
                        activity,
                        control,
                        R.drawable.ic_vault_media_next,
                        localized.getString(R.string.vault_media_action_next),
                    )
                    else -> action(
                        activity,
                        control,
                        R.drawable.ic_vault_pip_audio_only,
                        localized.getString(R.string.vault_pip_action_audio_only),
                    )
                },
            )
        }
        return actions
    }

    private fun action(activity: Activity, control: Int, iconRes: Int, label: String): RemoteAction {
        val intent = Intent(BROADCAST_ACTION)
            .setPackage(activity.packageName)
            .putExtra(EXTRA_CONTROL, control)
        // A PendingIntent is identified without its extras, so each button
        // needs a request code of its own or they would all become one.
        val pending = PendingIntent.getBroadcast(
            activity,
            control,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return RemoteAction(Icon.createWithResource(activity, iconRes), label, label, pending)
    }
}
