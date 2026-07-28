package com.aeidolon.vaultexplorer

import android.app.ActivityManager
import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


object DeviceCapabilityProfiler {

    enum class Tier { LOW, MEDIUM, HIGH }

    /** Computed once and cached — the underlying signals don't change for
     *  the lifetime of the process. */
    private var cachedTier: Tier? = null

    private fun classify(context: Context): Tier {
        cachedTier?.let { return it }

        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val isLowRam = am?.isLowRamDevice ?: false
        val memoryClassMb = am?.memoryClass ?: 128
        val cores = Runtime.getRuntime().availableProcessors()

        val tier = when {
            isLowRam || memoryClassMb <= 128 || cores <= 4 -> Tier.LOW
            memoryClassMb >= 256 && cores >= 8 -> Tier.HIGH
            else -> Tier.MEDIUM
        }
        cachedTier = tier
        return tier
    }

    fun handleGetDeviceCapabilityProfile(
        activity: MainActivity,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        result.success(
            mapOf(
                "tier" to classify(activity).name,
                "cores" to Runtime.getRuntime().availableProcessors(),
                "memoryClassMb" to (am?.memoryClass ?: 128),
                "isLowRamDevice" to (am?.isLowRamDevice ?: false),
            )
        )
    }
}
