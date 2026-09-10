package com.aeidolon.vaultexplorer.panic

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Binder
import java.util.concurrent.Executors
import com.aeidolon.vaultexplorer.VeLog

class PanicKitTriggerReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "PanicKit_Trigger"
        private val triggerExecutor = Executors.newSingleThreadExecutor()
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != PanicKitContract.ACTION_TRIGGER) return
        val appContext = context.applicationContext
        val callingUid = Binder.getCallingUid()
        val pending = goAsync()

        triggerExecutor.execute {
            try {
                handleTrigger(appContext, callingUid)
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "Unhandled error handling PanicKit trigger" }
            } finally {
                pending.finish()
            }
        }
    }

    private fun handleTrigger(context: Context, callingUid: Int) {
        if (!PanicKitSettings.isResponderEnabled(context)) {
            VeLog.i(TAG) { "Ignored trigger: PanicKit responder is disabled in settings" }
            return
        }

        val trustedPackage = PanicKitSettings.getTrustedPackage(context)
        val trustedCertSha256 = PanicKitSettings.getTrustedCertSha256(context)

        if (trustedPackage.isNullOrEmpty() || trustedCertSha256.isNullOrEmpty()) {
            VeLog.w(TAG) { "Ignored trigger: no trigger app is currently paired" }
            return
        }

        if (PanicKitSettings.isPairingEnforcementEnabled(context)) {
            val pm = context.packageManager
            val packagesForUid = pm.getPackagesForUid(callingUid)
            if (packagesForUid == null || !packagesForUid.contains(trustedPackage)) {
                VeLog.w(TAG) { "Security violation: calling UID $callingUid does not own trusted package $trustedPackage" }
                return
            }

            val actualCertSha256 = PanicKitConnectActivity.getCertificateSha256(context, trustedPackage)
            if (!trustedCertSha256.equals(actualCertSha256, ignoreCase = true)) {
                VeLog.w(TAG) { "Security violation: certificate mismatch for package $trustedPackage" }
                return
            }
        }

        val tier = PanicSettings.getConfiguredTier(context)
        VeLog.i(TAG) { "PanicKit trigger verified from $trustedPackage. Executing tier: $tier" }
        PanicManager.execute(context, tier, source = "panickit")
    }
}
