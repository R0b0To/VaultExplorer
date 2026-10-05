package com.aeidolon.vaultexplorer.saf

import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Process-wide activity for remote writes performed by a mirror proxy. */
object MirrorPushEvents {
    private const val IDLE_GRACE_MS = 2_500L

    data class Snapshot(val activeCount: Int)

    fun interface Listener {
        fun onMirrorPushActivity(snapshot: Snapshot)
    }

    private val nextId = AtomicLong(1)
    private val activePushes = HashSet<Long>()
    private val listeners = CopyOnWriteArraySet<Listener>()
    private val idleExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "mirror-push-activity").apply { isDaemon = true }
    }
    private var pendingIdleClear: ScheduledFuture<*>? = null
    private var idleClearGeneration = 0L

    @Volatile
    private var current = Snapshot(activeCount = 0)

    fun snapshot(): Snapshot = current

    fun addListener(listener: Listener) {
        listeners.add(listener)
        listener.onMirrorPushActivity(current)
    }

    fun removeListener(listener: Listener) {
        listeners.remove(listener)
    }

    fun begin(): Long {
        val id = nextId.getAndIncrement()
        var update: Snapshot? = null
        synchronized(activePushes) {
            idleClearGeneration++
            pendingIdleClear?.cancel(false)
            pendingIdleClear = null
            activePushes.add(id)
            val next = Snapshot(activePushes.size)
            if (next.activeCount != current.activeCount) {
                current = next
                update = next
            }
        }
        update?.let(::notifyListeners)
        return id
    }

    fun finish(id: Long) {
        var immediateUpdate: Snapshot? = null
        synchronized(activePushes) {
            if (!activePushes.remove(id)) return
            if (activePushes.isNotEmpty()) {
                immediateUpdate = Snapshot(activePushes.size).also { current = it }
            } else {
                pendingIdleClear?.cancel(false)
                val generation = ++idleClearGeneration
                pendingIdleClear = idleExecutor.schedule({
                    val cleared = synchronized(activePushes) {
                        if (generation != idleClearGeneration) {
                            null
                        } else {
                            pendingIdleClear = null
                            if (activePushes.isNotEmpty()) null
                            else Snapshot(activeCount = 0).also { current = it }
                        }
                    }
                    if (cleared != null) notifyListeners(cleared)
                }, IDLE_GRACE_MS, TimeUnit.MILLISECONDS)
            }
        }
        immediateUpdate?.let(::notifyListeners)
    }

    private fun notifyListeners(snapshot: Snapshot) {
        listeners.forEach { it.onMirrorPushActivity(snapshot) }
    }
}
