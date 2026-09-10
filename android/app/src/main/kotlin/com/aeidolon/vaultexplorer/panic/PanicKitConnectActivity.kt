package com.aeidolon.vaultexplorer.panic

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog
import java.security.MessageDigest

class PanicKitConnectActivity : Activity() {

    companion object {
        private const val TAG = "PanicKit_Connect"

        fun getCertificateSha256(context: Context, packageName: String): String? {
            return try {
                val pm = context.packageManager
                val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                    val signingInfo = info.signingInfo ?: return null
                    if (signingInfo.hasMultipleSigners()) {
                        signingInfo.apkContentsSigners
                    } else {
                        signingInfo.signingCertificateHistory
                    }
                } else {
                    @Suppress("DEPRECATION")
                    val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                    @Suppress("DEPRECATION")
                    info.signatures
                }
                val firstSig = signatures?.firstOrNull() ?: return null
                val md = MessageDigest.getInstance("SHA-256")
                val digest = md.digest(firstSig.toByteArray())
                digest.joinToString("") { "%02x".format(it) }
            } catch (e: Exception) {
                VeLog.e(TAG, e) { "Failed to extract certificate for $packageName" }
                null
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        when (intent?.action) {
            PanicKitContract.ACTION_CONNECT -> handleConnect()
            PanicKitContract.ACTION_DISCONNECT -> handleDisconnect()
            else -> setResult(RESULT_CANCELED)
        }
        finish()
    }

    private fun handleConnect() {
        val senderPackage = callingPackage ?: intent?.getStringExtra(PanicKitContract.EXTRA_PACKAGE_NAME)
        if (senderPackage.isNullOrEmpty()) {
            VeLog.w(TAG) { "handleConnect: rejected -- senderPackage is null" }
            setResult(RESULT_CANCELED)
            return
        }

        if (!PanicKitSettings.isResponderEnabled(this)) {
            VeLog.i(TAG) { "handleConnect: declined -- PanicKit responder disabled in settings" }
            setResult(RESULT_CANCELED)
            return
        }

        val certSha256 = getCertificateSha256(this, senderPackage)
        if (certSha256 == null) {
            VeLog.w(TAG) { "handleConnect: could not extract certificate digest for $senderPackage" }
            setResult(RESULT_CANCELED)
            return
        }

        val previousTrigger = PanicKitSettings.getTrustedPackage(this)
        val isNewPairing = previousTrigger != senderPackage

        PanicKitSettings.setTrustedTrigger(this, senderPackage, certSha256)
        if (isNewPairing) {
            PanicKitConnectionNotifier.notifyPaired(this, senderPackage)
        }
        VeLog.i(TAG) { "handleConnect: successfully connected trigger=$senderPackage" }
        setResult(RESULT_OK)

        // Launch VaultExplorer so the user can configure their panic settings
        try {
            val launchIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            startActivity(launchIntent)
        } catch (e: Exception) {
            VeLog.w(TAG, e) { "handleConnect: could not launch MainActivity" }
        }
    }

    private fun handleDisconnect() {
        val previousTrigger = PanicKitSettings.getTrustedPackage(this)
        PanicKitSettings.clearTrustedTrigger(this)
        if (previousTrigger != null) {
            PanicKitConnectionNotifier.notifyUnpaired(this, previousTrigger)
            VeLog.i(TAG) { "handleDisconnect: successfully unpaired trigger=$previousTrigger" }
        }
        setResult(RESULT_OK)
    }
}