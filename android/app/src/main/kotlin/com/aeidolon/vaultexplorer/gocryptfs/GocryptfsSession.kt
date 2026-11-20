package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.foldervault.NativeVaultSession

/**
 * An unlocked gocryptfs vault. Everything -- including Check & Repair -- runs in the native core
 * (cpp/foldervault); the key material never leaves it.
 */
class GocryptfsSession internal constructor(
    context: Context,
    vaultRootUri: Uri,
    handle: Long,
    readOnly: Boolean,
    volIdRef: java.util.concurrent.atomic.AtomicInteger = java.util.concurrent.atomic.AtomicInteger(-1),
) : NativeVaultSession(context, vaultRootUri, ContainerFormat.GOCRYPTFS, handle, readOnly, volIdRef)
