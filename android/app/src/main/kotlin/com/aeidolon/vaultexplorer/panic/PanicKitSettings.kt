package com.aeidolon.vaultexplorer.panic

import android.content.Context

object PanicKitSettings {
    private const val PREFS_NAME = "vaultexplorer_panickit_settings"
    private const val PREF_RESPONDER_ENABLED = "responder_enabled"
    private const val PREF_PAIRING_ENFORCEMENT_ENABLED = "pairing_enforcement_enabled"
    private const val PREF_TRUSTED_PACKAGE = "trusted_trigger_package"
    private const val PREF_TRUSTED_CERT_SHA256 = "trusted_trigger_cert_sha256"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isResponderEnabled(context: Context): Boolean =
        prefs(context).getBoolean(PREF_RESPONDER_ENABLED, false)

    fun setResponderEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(PREF_RESPONDER_ENABLED, enabled).apply()
    }

    fun isPairingEnforcementEnabled(context: Context): Boolean =
        prefs(context).getBoolean(PREF_PAIRING_ENFORCEMENT_ENABLED, true)

    fun setPairingEnforcementEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(PREF_PAIRING_ENFORCEMENT_ENABLED, enabled).apply()
    }

    fun getTrustedPackage(context: Context): String? =
        prefs(context).getString(PREF_TRUSTED_PACKAGE, null)

    fun getTrustedCertSha256(context: Context): String? =
        prefs(context).getString(PREF_TRUSTED_CERT_SHA256, null)

    fun setTrustedTrigger(context: Context, packageName: String, certSha256: String) {
        prefs(context).edit()
            .putString(PREF_TRUSTED_PACKAGE, packageName)
            .putString(PREF_TRUSTED_CERT_SHA256, certSha256)
            .apply()
    }

    fun clearTrustedTrigger(context: Context) {
        prefs(context).edit()
            .remove(PREF_TRUSTED_PACKAGE)
            .remove(PREF_TRUSTED_CERT_SHA256)
            .apply()
    }
}
