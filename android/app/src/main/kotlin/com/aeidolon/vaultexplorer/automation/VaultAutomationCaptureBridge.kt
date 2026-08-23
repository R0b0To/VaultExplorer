package com.aeidolon.vaultexplorer.automation

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * In-process hand-off between [com.aeidolon.vaultexplorer.service.VaultAutomationRecordingService]
 * (which owns the actual camera+encoder session, and can run for as long as
 * a recording lasts) and [VaultAutomationReceiver]'s automationExecutor
 * thread (which needs to reply on ACTION_AUTOMATION_RESULT the moment
 * START_RECORDING/STOP_RECORDING actually finish -- not the moment the
 * service was merely asked to start, which is all `startForegroundService`
 * itself can promise).
 *
 * This is plain [CountDownLatch] hand-off, not a MethodChannel bridge like
 * [com.aeidolon.vaultexplorer.bridge.VaultAutomationUnlockedBridge] --
 * those exist because their other end is Dart, and silently no-op when no
 * Flutter engine happens to be attached, which is *fine* for a
 * fire-and-forget UI notification but wrong here: both ends of this one
 * are plain Kotlin in the same process, and the receiver genuinely needs
 * to block briefly for a real answer.
 *
 * Single-slot by design: only one automation recording can be in flight at
 * a time (see the service's own single-instance enforcement in
 * handleStart), so there's never more than one waiter to juggle.
 */
object VaultAutomationCaptureBridge {
    data class Result(val ok: Boolean, val message: String?, val durationMs: Long = 0)

    @Volatile private var latch: CountDownLatch? = null
    private val pendingResult = AtomicReference<Result?>()

    /** Call immediately before triggering the async work, then [await] the returned latch. */
    @Synchronized
    fun arm(): CountDownLatch {
        val l = CountDownLatch(1)
        latch = l
        pendingResult.set(null)
        return l
    }

    /** Called by the service once the async operation it's running actually finishes. */
    @JvmStatic
    fun complete(result: Result) {
        pendingResult.set(result)
        latch?.countDown()
    }

    /** Blocks up to [timeoutMs] for a matching [complete] call; null on timeout. */
    fun await(armed: CountDownLatch, timeoutMs: Long): Result? {
        val reached = try {
            armed.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (e: InterruptedException) {
            false
        }
        return if (reached) pendingResult.get() else null
    }
}
