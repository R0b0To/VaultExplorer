package com.aeidolon.vaultexplorer.syncbridge

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

/**
 * `${applicationName}` in AndroidManifest.xml resolves to Flutter's own
 * `FlutterApplication`, which this repo does not subclass — adding a
 * custom `Application` just to capture a process-lifetime `Context` for
 * [LedgerWriterClient] would risk interacting with Flutter's own embedding
 * setup for no real benefit. A manifest-declared, `exported=false`
 * `ContentProvider` gets `Context.attachInfo` at the same point in process
 * startup (before `Application.onCreate`, in fact) with none of that risk
 * — the same trick AndroidX App Startup and WorkManager's own
 * auto-initializer use. This provider does nothing else: every CRUD
 * method is a no-op, and nothing outside this process can even reach it.
 */
class SyncBridgeContextInitializer : ContentProvider() {
    override fun onCreate(): Boolean {
        context?.let { LedgerWriterClient.attachContext(it) }
        return true
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
