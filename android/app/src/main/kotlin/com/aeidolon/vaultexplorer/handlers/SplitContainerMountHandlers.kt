package com.aeidolon.vaultexplorer.handlers

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeOpSupport

class SplitContainerMountHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
    private val vaultUnlockHandlers: VaultUnlockHandlers,
) {
    fun handleUnlockSplitContainer(call: MethodCall, result: MethodChannel.Result) {
        vaultUnlockHandlers.handleUnlockContainer(call, result)
    }

    fun onActivityDestroyed() {
        // Managed by VaultUnlockHandlers
    }
}