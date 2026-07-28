package com.aeidolon.vaultexplorer

import android.app.ActivityManager
import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Classifies the device's CPU/RAM headroom once at startup (ADR-011,
 * Finding F-14) so the Dart-side concurrency and memory budgets that
 * already existed with no caller — `ThumbnailConcurrency.resizeForDevice`,
 * `PriorityTaskQueue.resize`, `LruCache.resize`, `ByteBudgetCache.resize`,
 * `FullResImageCache.resize`, `ThumbnailCacheService.resizeMemoryBudget` —
 * can size a low-RAM device and a flagship tablet differently instead of
 * sharing one hardcoded set of constants everywhere.
 *
 * Deliberately simple: three tiers, derived from two cheap, standard
 * Android signals ([ActivityManager.isLowRamDevice] and
 * [ActivityManager.getMemoryClass]) plus core count. No per-device
 * allowlist to maintain, and no dependency on anything that could change
 * between Android versions in a way that needs tracking here.
 *
 * `ioExecutor`/`thumbnailExecutor`/`fullResExecutor` in [MainActivity] are
 * NOT resized by this — those are fixed-size `ExecutorService`s created at
 * construction time, before `Context` is fully available for this check to
 * run, and resizing a live thread pool's core/max size in place is a
 * separate, riskier change than the Dart-side primitives this profiler
 * currently drives. That remains open (see architecture.md Finding F-14).
 */
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
