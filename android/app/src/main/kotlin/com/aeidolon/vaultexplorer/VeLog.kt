package com.aeidolon.vaultexplorer

import android.util.Log

/**
 * Master switch for verbose native-side diagnostic logging.
 *
 * Mirrors the Dart-side `VeLog` (lib/core/utils/ve_log.dart) and is kept in
 * sync with the "Debug logging" settings toggle via MethodChannel --
 * see MainActivity's ChannelMethods.SET_DEBUG_LOGGING handler, and
 * VaultExplorerApi.setDebugLogging() on the Dart side which calls it at
 * app startup, on toggle change, and after a settings import.
 *
 * [enabled] starts `false` so nothing extra hits logcat in normal use.
 * Call sites should prefer the lambda-taking helpers below over building
 * a message string and guarding it with `if (VeLog.enabled)` themselves --
 * the lambda is only invoked when logging is actually on, so a disabled
 * profiling block (string formatting, etc.) costs nothing.
 */
object VeLog {
    @Volatile
    var enabled: Boolean = false

    inline fun d(tag: String, msg: () -> String) {
        if (enabled) Log.d(tag, msg())
    }

    inline fun i(tag: String, msg: () -> String) {
        if (enabled) Log.i(tag, msg())
    }

    inline fun w(tag: String, msg: () -> String) {
        if (enabled) Log.w(tag, msg())
    }
}
