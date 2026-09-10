package com.aeidolon.vaultexplorer.panic

import android.app.Activity
import android.os.Bundle
import com.aeidolon.vaultexplorer.VeLog

class PanicKitTriggerActivity : Activity() {

    companion object {
        private const val TAG = "PanicKit_TriggerActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            handleTrigger()
        } catch (e: Exception) {
            VeLog.e(TAG, e) { "Failed to handle PanicKit trigger activity" }
        } finally {
            finish()
        }
    }

    private fun handleTrigger() {
        if (!PanicKitSettings.isResponderEnabled(this)) {
            VeLog.i(TAG) { "Ignored trigger: PanicKit responder is disabled in settings" }
            return
        }

        val trustedPackage = PanicKitSettings.getTrustedPackage(this)
        if (trustedPackage.isNullOrEmpty()) {
            VeLog.w(TAG) { "Ignored trigger: no trigger app is currently paired" }
            return
        }

        if (PanicKitSettings.isPairingEnforcementEnabled(this)) {
            val caller = callingPackage 
                ?: referrer?.authority 
                ?: intent?.getStringExtra(PanicKitContract.EXTRA_PACKAGE_NAME)

            if (caller != null && caller != trustedPackage) {
                VeLog.w(TAG) { "Security violation: caller $caller does not match trusted package $trustedPackage" }
                return
            }

            val trustedCert = PanicKitSettings.getTrustedCertSha256(this)
            if (caller != null && trustedCert != null) {
                val actualCert = PanicKitConnectActivity.getCertificateSha256(this, caller)
                if (!trustedCert.equals(actualCert, ignoreCase = true)) {
                    VeLog.w(TAG) { "Security violation: certificate mismatch for $caller" }
                    return
                }
            }
        }

        val tier = PanicSettings.getConfiguredTier(this)
        VeLog.i(TAG) { "PanicKit trigger activity verified. Executing tier: $tier" }
        PanicManager.execute(applicationContext, tier, source = "panickit_activity")
    }
}