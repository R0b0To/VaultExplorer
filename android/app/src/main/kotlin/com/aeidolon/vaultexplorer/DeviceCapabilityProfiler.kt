package com.aeidolon.vaultexplorer

import android.app.ActivityManager
import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


object DeviceCapabilityProfiler {

    enum class Tier { LOW, MEDIUM, HIGH }

    /** Per-executor pool sizes for a given [Tier] — see [executorSizesFor]. */
    data class ExecutorSizes(
        val io: Int,
        val imageThumbnail: Int,
        val videoThumbnail: Int,
        val fullRes: Int,
    )

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


    fun tierFor(context: Context): Tier = classify(context)

    fun executorSizesFor(tier: Tier): ExecutorSizes = when (tier) {
        Tier.LOW -> ExecutorSizes(io = 2, imageThumbnail = 1, videoThumbnail = 1, fullRes = 1)
        Tier.MEDIUM -> ExecutorSizes(io = 4, imageThumbnail = 2, videoThumbnail = 1, fullRes = 2)
        Tier.HIGH -> ExecutorSizes(io = 6, imageThumbnail = 3, videoThumbnail = 2, fullRes = 3)
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