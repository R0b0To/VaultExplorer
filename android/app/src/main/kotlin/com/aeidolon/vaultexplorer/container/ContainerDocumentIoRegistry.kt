package com.aeidolon.vaultexplorer.container

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Tracks open document-provider descriptors so a lock cannot tear down a
 * container in the middle of a file-manager read or write. Per-call volume
 * locks are not enough here: [ContainerProxyCallback] buffers writes and a
 * client may issue many callbacks before it closes the descriptor. */
object ContainerDocumentIoRegistry {
    private val lock = ReentrantLock()
    private val handlesDrained = lock.newCondition()
    private val activeHandles = mutableMapOf<Int, Int>()
    private val lockPending = mutableSetOf<Int>()

    class HandleLease internal constructor(private val volId: Int) : AutoCloseable {
        private val closed = java.util.concurrent.atomic.AtomicBoolean(false)

        override fun close() {
            if (closed.compareAndSet(false, true)) releaseHandle(volId)
        }
    }

    /**
     * True once a lock has started draining [volId]. Long-running holders of
     * a [HandleLease] (a folder share streaming a whole subtree, unlike a
     * single proxy descriptor the receiver closes on its own schedule) poll
     * this between chunks and bail out, so [LockPermit.awaitHandlesClosed]
     * -- and with it auto-lock -- never waits on a share to finish.
     */
    fun isLockPending(volId: Int): Boolean = lock.withLock { volId in lockPending }

    /** Returns null once a lock has started draining this container. */
    fun acquireHandle(volId: Int): HandleLease? = lock.withLock {
        if (volId in lockPending) return null
        activeHandles[volId] = (activeHandles[volId] ?: 0) + 1
        HandleLease(volId)
    }

    /**
     * Closes the gate to new document descriptors, then waits for existing
     * clients to close theirs. A permit owns the gate until the native
     * container lock has completed or failed.
     */
    fun beginLock(volId: Int): LockPermit? = lock.withLock {
        if (!lockPending.add(volId)) return null
        LockPermit(volId, activeHandles[volId] ?: 0)
    }

    class LockPermit internal constructor(
        private val volId: Int,
        val handlesAtStart: Int,
    ) : AutoCloseable {
        private var closed = false

        fun awaitHandlesClosed() = lock.withLock {
            while ((activeHandles[volId] ?: 0) > 0) handlesDrained.await()
        }

        override fun close(): Unit {
            lock.withLock {
                if (closed) return
                closed = true
                lockPending.remove(volId)
                handlesDrained.signalAll()
            }
        }
    }

    private fun releaseHandle(volId: Int) {
        lock.withLock {
            val count = activeHandles[volId] ?: return@withLock
            if (count <= 1) activeHandles.remove(volId) else activeHandles[volId] = count - 1
            handlesDrained.signalAll()
        }
    }
}
