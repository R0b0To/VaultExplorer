package com.aeidolon.vaultexplorer

import io.flutter.plugin.common.MethodChannel

/**
 * Coordinates the single in-flight Flutter [MethodChannel.Result] for
 * whichever system picker / create-document / import / export Intent is
 * currently awaiting an onActivityResult callback. Shared across every
 * handler group that launches such an intent ([VaultPickerHandlers],
 * [VaultCreationHandlers], [ImportExportHandlers]) since only one of those
 * system UIs can be on screen at a time — this preserves the original
 * single `pendingFlutterResult` field's exact semantics: starting a new
 * picker cancels whichever one was already pending.
 */
class PendingActivityResult {
    @Volatile private var pending: MethodChannel.Result? = null

    /** Cancels any previous pending result and stashes [result] as the new one. */
    fun stash(result: MethodChannel.Result) {
        pending?.error("CANCELLED", "Operation superseded by a new request", null)
        pending = result
    }

    /** Takes and clears the pending result, or null if none is waiting. */
    fun take(): MethodChannel.Result? {
        val r = pending
        pending = null
        return r
    }
}