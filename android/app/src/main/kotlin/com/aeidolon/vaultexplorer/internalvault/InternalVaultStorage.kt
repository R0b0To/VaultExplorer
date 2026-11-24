package com.aeidolon.vaultexplorer.internalvault

import android.content.Context
import android.net.Uri
import java.io.File
import java.util.concurrent.locks.ReentrantReadWriteLock

/**
 * Android binding for [AppVaultStore]: the vault directory is
 * `<filesDir>/vaults`, the app's private storage. Nothing outside the app can
 * read it and no storage permission is needed, which is also why it is gone
 * when the app is uninstalled or its data is cleared (Android backup is off).
 *
 * A vault in here is addressed by a plain `file://` URI. Every code path that
 * already handles `file://` URIs (unlock, lock, the session registry, document
 * provider, automation) keeps working unchanged; only the folder-vault opener
 * needed to learn to accept a local directory (see FolderVaultOpener).
 */
object InternalVaultStorage {

    /**
     * Creates and copies hold the read side for their whole duration, so the
     * leftover sweep (which takes the write side) can never run while one is
     * writing into a staging entry.
     */
    private val opLock = ReentrantReadWriteLock()

    fun store(context: Context): AppVaultStore =
        AppVaultStore(File(context.filesDir, AppVaultStore.DIR_NAME))

    fun uriString(file: File): String = AppVaultStore.fileUriString(file)

    /** The file or folder a vault URI names, only if it is inside app storage. */
    fun localFile(context: Context, uri: Uri?): File? =
        if (uri == null) null else store(context).resolveUri(uri.toString())

    fun localFile(context: Context, uriString: String?): File? =
        if (uriString == null) null else store(context).resolveUri(uriString)

    fun isAppStorageUri(context: Context, uriString: String?): Boolean = localFile(context, uriString) != null

    /** Runs [block] as a create/copy operation: no leftover sweep can run until it returns. */
    fun <T> runOperation(block: () -> T): T {
        val lock = opLock.readLock()
        lock.lock()
        try {
            return block()
        } finally {
            lock.unlock()
        }
    }

    /**
     * Removes what a crash can leave behind (half-built staging entries and
     * reserved-but-empty names). Does nothing, and returns 0, if an operation
     * is running right now.
     */
    fun sweepLeftoversIfIdle(context: Context): Int {
        val lock = opLock.writeLock()
        if (!lock.tryLock()) return 0
        try {
            val store = store(context)
            if (!store.root.isDirectory) return 0
            return store.sweepStaging() + store.sweepReservations()
        } finally {
            lock.unlock()
        }
    }
}
