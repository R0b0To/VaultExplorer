package com.aeidolon.vaultexplorer.automation

import android.content.Context
import android.content.Intent
import com.aeidolon.vaultexplorer.container.ContainerSessionRegistry
import com.aeidolon.vaultexplorer.service.VaultKeepAliveService
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/** Progress state for headless automation transfers. The notification is
 * owned by VaultKeepAliveService so it remains visible while Flutter has no
 * engine or Activity attached. */
internal object VaultAutomationProgress {
    private data class Operation(
        val context: Context,
        val title: String,
        var currentName: String? = null,
        var fileSize: Long = 0L,
        var bytesDone: Long = 0L,
        var filesProcessed: Int = 0,
        var lastPublishedAt: Long = 0L,
    )

    private val nextId = AtomicInteger(1_000_000)
    private val operations = ConcurrentHashMap<Int, Operation>()

    @Volatile
    private var displayedOperationId: Int? = null

    fun begin(context: Context, title: String): Int {
        val id = nextId.incrementAndGet()
        val operation = Operation(context.applicationContext, title)
        operations[id] = operation
        displayedOperationId = id
        publish(id, force = true)
        return id
    }

    fun beginFile(opId: Int, name: String, fileSize: Long) {
        val operation = operations[opId] ?: return
        synchronized(operation) {
            operation.currentName = name.substringAfterLast('/').substringAfterLast('\\')
            operation.fileSize = fileSize.coerceAtLeast(0L)
            operation.bytesDone = 0L
        }
        publish(opId, force = true)
    }

    /** A byte delta from a streaming path or CopyProgressBridge. */
    fun reportBytes(opId: Int, bytesDelta: Long) {
        if (bytesDelta <= 0L) return
        val operation = operations[opId] ?: return
        synchronized(operation) {
            val sum = if (Long.MAX_VALUE - operation.bytesDone < bytesDelta) Long.MAX_VALUE
                else operation.bytesDone + bytesDelta
            operation.bytesDone = sum.coerceAtMost(operation.fileSize.takeIf { it > 0L } ?: Long.MAX_VALUE)
        }
        publish(opId)
    }

    /** Absolute per-file byte progress from Import/ExportProgressBridge. */
    fun reportAbsoluteBytes(opId: Int, bytesDone: Long) {
        if (bytesDone < 0L) return
        val operation = operations[opId] ?: return
        synchronized(operation) {
            operation.bytesDone = bytesDone.coerceAtMost(operation.fileSize.takeIf { it > 0L } ?: Long.MAX_VALUE)
        }
        publish(opId)
    }

    fun finishFile(opId: Int) {
        val operation = operations[opId] ?: return
        synchronized(operation) {
            operation.filesProcessed++
            operation.currentName = null
            operation.fileSize = 0L
            operation.bytesDone = 0L
        }
        publish(opId, force = true)
    }

    fun finish(opId: Int) {
        val finished = operations.remove(opId) ?: return
        if (displayedOperationId == opId) {
            displayedOperationId = operations.keys.maxOrNull()
        }
        val nextId = displayedOperationId
        if (nextId != null) {
            publish(nextId, force = true)
            return
        }

        // Return the shared notification to the normal open-vault status or
        // remove the service entirely when there is no session to keep alive.
        VaultKeepAliveService.updateOperationProgress(
            context = finished.context,
            hasActive = false,
            title = null,
            text = null,
            progress = null,
            indeterminate = false,
        )
        if (!ContainerSessionRegistry.hasAnyActiveSessions()) {
            finished.context.stopService(
                Intent(finished.context, VaultKeepAliveService::class.java),
            )
        } else {
            VaultKeepAliveService.refreshNotification()
        }
    }

    private fun publish(opId: Int, force: Boolean = false) {
        if (displayedOperationId != opId) return
        val operation = operations[opId] ?: return
        val now = System.currentTimeMillis()
        val title: String
        val text: String
        val progress: Int?
        val indeterminate: Boolean
        synchronized(operation) {
            if (!force && now - operation.lastPublishedAt < 120L) return
            operation.lastPublishedAt = now
            val name = operation.currentName
            val size = operation.fileSize
            val done = operation.bytesDone
            title = operation.title
            text = if (name != null) {
                if (size > 0L) "$name · ${(done.toDouble() / size.toDouble() * 100.0).toInt().coerceIn(0, 100)}%"
                else name
            } else {
                "${operation.filesProcessed} file(s) processed"
            }
            indeterminate = name == null || size <= 0L
            progress = if (!indeterminate) {
                (done.coerceAtMost(size).toDouble() / size.toDouble() * 1000.0).toInt()
            } else null
        }
        VaultKeepAliveService.updateOperationProgress(
            context = operation.context,
            hasActive = true,
            title = title,
            text = text,
            progress = progress,
            max = 1000,
            indeterminate = indeterminate,
        )
        if (!VaultKeepAliveService.isRunning) {
            VaultAutomationNotification.notify(
                operation.context,
                title,
                text,
                progress,
                max = 1000,
                indeterminate = indeterminate,
            )
        }
    }
}
