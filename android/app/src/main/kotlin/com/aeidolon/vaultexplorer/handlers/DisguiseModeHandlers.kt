package com.aeidolon.vaultexplorer.handlers

import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.aeidolon.vaultexplorer.R
import com.aeidolon.vaultexplorer.container.ContainerDocumentsProvider
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.VeLog

internal object DisguiseChannelMethods {
    const val GET_MODE = "getMode"
    const val SET_MODE = "setMode"
}

internal object DisguiseMode {
    const val VAULT = "vault"
    const val DECOY = "decoy"
}

class DisguiseModeHandlers(
    private val activity: MainActivity,
) {
    companion object {
        private const val ALIAS_VAULT = "com.aeidolon.vaultexplorer.VaultLauncherAlias"
        private const val ALIAS_DECOY = "com.aeidolon.vaultexplorer.ZipExplorerAlias"
        private const val TAG = "DisguiseModeHandlers"

        /**
         * Context-only equivalent of [isAliasEnabled]/[updateActivityIdentity]'s
         * decoy check, for callers with no MainActivity instance --
         * currently only [com.aeidolon.vaultexplorer.service.
         * VaultKeepAliveService], which must never reveal "Vault Explorer"
         * identity or vault state in its notification while decoy mode is
         * active.
         */
        @JvmStatic
        fun isDecoyActive(context: Context): Boolean {
            val pm = context.packageManager
            fun enabled(name: String): Boolean {
                val setting = pm.getComponentEnabledSetting(ComponentName(context.packageName, name))
                return when (setting) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED -> false
                    else -> name == ALIAS_VAULT
                }
            }
            return enabled(ALIAS_DECOY) && !enabled(ALIAS_VAULT)
        }
    }

    private fun aliasComponent(name: String) = ComponentName(activity.packageName, name)

    private fun isAliasEnabled(name: String): Boolean {
        val pm = activity.packageManager
        val setting = pm.getComponentEnabledSetting(aliasComponent(name))
        return when (setting) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED -> false
            else -> name == ALIAS_VAULT
        }
    }

    fun updateActivityIdentity() {
        val decoyActive = isAliasEnabled(ALIAS_DECOY) && !isAliasEnabled(ALIAS_VAULT)
        val label = if (decoyActive) activity.getString(R.string.decoy_app_name) else activity.getString(R.string.app_name)
        val iconRes = if (decoyActive) R.mipmap.ic_launcher_zip else R.mipmap.ic_launcher
        activity.title = label

        val pm = activity.packageManager
        val docProviderComponent = ComponentName(activity, ContainerDocumentsProvider::class.java)
        val expectedDocProviderState = if (decoyActive) {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        }
        if (pm.getComponentEnabledSetting(docProviderComponent) != expectedDocProviderState) {
            try {
                pm.setComponentEnabledSetting(
                    docProviderComponent,
                    expectedDocProviderState,
                    PackageManager.DONT_KILL_APP,
                )
            } catch (e: Exception) {
                VeLog.w(TAG) { "Failed to update ContainerDocumentsProvider state: ${e.message}" }
            }
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val taskDesc = ActivityManager.TaskDescription.Builder()
                    .setLabel(label)
                    .setIcon(iconRes)
                    .build()
                activity.setTaskDescription(taskDesc)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                @Suppress("DEPRECATION")
                val taskDesc = ActivityManager.TaskDescription(label, iconRes)
                activity.setTaskDescription(taskDesc)
            } else {
                val iconBitmap = BitmapFactory.decodeResource(activity.resources, iconRes)
                @Suppress("DEPRECATION")
                val taskDesc = ActivityManager.TaskDescription(label, iconBitmap)
                activity.setTaskDescription(taskDesc)
            }
        } catch (_: Exception) {}
    }

    fun handleGetMode(call: MethodCall, result: MethodChannel.Result) {
        val decoyActive = isAliasEnabled(ALIAS_DECOY) && !isAliasEnabled(ALIAS_VAULT)
        result.success(if (decoyActive) DisguiseMode.DECOY else DisguiseMode.VAULT)
    }

    fun handleSetMode(call: MethodCall, result: MethodChannel.Result) {
        val mode = call.argument<String>("mode")
        if (mode != DisguiseMode.VAULT && mode != DisguiseMode.DECOY) {
            result.error("INVALID_ARGS", "mode must be \"vault\" or \"decoy\"", null)
            return
        }
        try {
            val pm = activity.packageManager
            val enableDecoy = mode == DisguiseMode.DECOY
            val targetAlias = if (enableDecoy) ALIAS_DECOY else ALIAS_VAULT
            val oldAlias    = if (enableDecoy) ALIAS_VAULT else ALIAS_DECOY
            pm.setComponentEnabledSetting(
                aliasComponent(targetAlias),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            pm.setComponentEnabledSetting(
                aliasComponent(oldAlias),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
            val docProviderComponent = ComponentName(activity, ContainerDocumentsProvider::class.java)
            pm.setComponentEnabledSetting(
                docProviderComponent,
                if (enableDecoy) PackageManager.COMPONENT_ENABLED_STATE_DISABLED else PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            updateActivityIdentity()
            result.success(null)
        } catch (e: Exception) {
            result.error("DISGUISE_MODE_ERROR", e.message, null)
        }
    }
}