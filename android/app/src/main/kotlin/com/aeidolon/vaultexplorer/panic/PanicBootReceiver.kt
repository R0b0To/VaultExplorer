package com.aeidolon.vaultexplorer.panic

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.concurrent.Executors
import com.aeidolon.vaultexplorer.VeLog

/**
 * The "wipe on reboot" trigger: if [PanicBootTriggerSettings] is armed
 * when this device finishes booting, runs the armed [PanicTier] headlessly
 * -- no need to open the app, and no external PanicKit sender (Ripple,
 * Wasted, etc.) required, unlike [PanicKitTriggerReceiver]'s trigger path.
 *
 * A user who expects they may soon need this arms it in advance from the
 * Emergency Panic settings screen; at the critical moment, powering the
 * device off and back on (or a plain reboot) is the entire trigger action.
 *
 * Registered for the standard (non-direct-boot) android.intent.action.BOOT_COMPLETED.
 * The OS only delivers that to this app once its credential-encrypted
 * storage has been unlocked at least once since boot -- the same storage
 * [PanicManager]'s purge pipeline (AndroidKeyStore, SharedPreferences,
 * internal files) already assumes is available, so arming this and then
 * rebooting still requires unlocking the device once with its normal
 * PIN/pattern/password/biometric before the wipe can run. There is
 * deliberately no attempt at a pre-unlock Direct Boot purge here: nearly
 * everything a Tier 2/3 purge touches lives in credential-encrypted
 * storage the OS will not hand this app any earlier regardless, and
 * half-purging via a separate device-protected-storage code path would
 * add real complexity and a second, harder-to-verify wipe pipeline for
 * comparatively little benefit. What this trigger removes is the need to
 * open the app or tap anything once that first unlock happens -- from
 * there the wipe runs on its own, the moment the OS delivers the
 * broadcast.
 *
 * Fires at most once per arm: disarms itself (synchronously, before
 * calling [PanicManager.execute]) the instant it fires, so an ordinary
 * later reboot -- an OS update, a low-battery restart -- does not wipe
 * again. Arming is single-shot by design; re-arming for the next occasion
 * is a deliberate action from Settings.
 */
class PanicBootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "PanicBootReceiver"
        private val triggerExecutor = Executors.newSingleThreadExecutor()
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val appContext = context.applicationContext
        if (!PanicBootTriggerSettings.isArmed(appContext)) return

        val pending = goAsync()
        triggerExecutor.execute {
            try {
                val tier = PanicBootTriggerSettings.getArmedTier(appContext)
                PanicBootTriggerSettings.disarmSynchronously(appContext)
                VeLog.i(TAG) { "Boot trigger was armed for $tier -- executing after boot" }
                PanicManager.execute(appContext, tier, source = "boot_trigger")
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "Unhandled error executing boot-triggered panic wipe" }
            } finally {
                pending.finish()
            }
        }
    }
}
