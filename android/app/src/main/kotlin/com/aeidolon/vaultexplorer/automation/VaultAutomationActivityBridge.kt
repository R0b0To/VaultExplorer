package com.aeidolon.vaultexplorer.automation

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * In-process hand-off between [VaultAutomationCaptureActivity] (which briefly
 * runs in the foreground to satisfy Android 14+ camera/microphone while-in-use
 * requirements) and [VaultAutomationReceiver]'s background worker thread.
 */
object VaultAutomationActivityBridge {
    data class Result(
        val ok: Boolean,
        val message: String?,
        val durationMs: Long = 0,
        val vaultPath: String? = null,
    )

    @Volatile private var latch: CountDownLatch? = null
    private val pendingResult = AtomicReference<Result?>()

    /** Call immediately before launching [VaultAutomationCaptureActivity], then [await]. */
    @Synchronized
    fun arm(): CountDownLatch {
        val l = CountDownLatch(1)
        latch = l
        pendingResult.set(null)
        return l
    }

    /** Called by [VaultAutomationCaptureActivity] once capture/start completes. */
    @JvmStatic
    fun complete(result: Result) {
        pendingResult.set(result)
        latch?.countDown()
    }

    /** Blocks up to [timeoutMs] for a matching [complete] call; returns null on timeout. */
    fun await(armed: CountDownLatch, timeoutMs: Long): Result? {
        val reached = try {
            armed.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (e: InterruptedException) {
            false
        }
        return if (reached) pendingResult.get() else null
    }
}
