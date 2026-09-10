package com.aeidolon.vaultexplorer.panic

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.concurrent.Executors
import com.aeidolon.vaultexplorer.VeLog

class PanicKitTriggerReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "PanicKit_TriggerReceiver"
        private val triggerExecutor = Executors.newSingleThreadExecutor()
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != PanicKitContract.ACTION_TRIGGER) return
        val appContext = context.applicationContext
        val pending = goAsync()

        triggerExecutor.execute {
            try {
                handleTrigger(appContext, intent)
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "Unhandled error handling PanicKit trigger broadcast" }
            } finally {
                pending.finish()
            }
        }
    }

    private fun handleTrigger(context: Context, intent: Intent) {
        if (!PanicKitSettings.isResponderEnabled(context)) {
            VeLog.i(TAG) { "Ignored trigger: PanicKit responder is disabled in settings" }
            return
        }

        val trustedPackage = PanicKitSettings.getTrustedPackage(context)
        if (trustedPackage.isNullOrEmpty()) {
            VeLog.w(TAG) { "Ignored trigger: no trigger app is currently paired" }
            return
        }

        if (PanicKitSettings.isPairingEnforcementEnabled(context)) {
            // On Android 34+, verify package identity from broadcast metadata if available
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val sender = sentFromPackage
                if (sender != null && sender != trustedPackage) {
                    VeLog.w(TAG) { "Security violation: sender $sender does not match trusted package $trustedPackage" }
                    return
                }
            }

            // Verify extra package if provided
            val extraPackage = intent.getStringExtra(PanicKitContract.EXTRA_PACKAGE_NAME)
            if (extraPackage != null && extraPackage != trustedPackage) {
                VeLog.w(TAG) { "Security violation: extra package $extraPackage does not match $trustedPackage" }
                return
            }

            // Verify paired package certificate signature
            val trustedCert = PanicKitSettings.getTrustedCertSha256(context)
            if (trustedCert != null) {
                val actualCert = PanicKitConnectActivity.getCertificateSha256(context, trustedPackage)
                if (!trustedCert.equals(actualCert, ignoreCase = true)) {
                    VeLog.w(TAG) { "Security violation: certificate mismatch for package $trustedPackage" }
                    return
                }
            }
        }

        val tier = PanicSettings.getConfiguredTier(context)
        VeLog.i(TAG) { "PanicKit trigger broadcast verified. Executing tier: $tier" }
        PanicManager.execute(context, tier, source = "panickit_broadcast")
    }
}