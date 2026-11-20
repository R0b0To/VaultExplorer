package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.foldervault.NativeVaultSession

/**
 * An unlocked Cryptomator vault (format 7 or 8). Everything -- including Check & Repair -- runs in the native
 * core (cpp/foldervault); the key material never leaves it.
 */
class CryptomatorSession internal constructor(
    context: Context,
    vaultRootUri: Uri,
    handle: Long,
    readOnly: Boolean,
    volIdRef: java.util.concurrent.atomic.AtomicInteger = java.util.concurrent.atomic.AtomicInteger(-1),
) : NativeVaultSession(context, vaultRootUri, ContainerFormat.CRYPTOMATOR, handle, readOnly, volIdRef)
