package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.net.Uri
import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.foldervault.NativeVaultSession

/**
 * An unlocked CryFS vault. Everything -- including Check -- runs in the native core (cpp/foldervault); the key
 * material never leaves it.
 */
class CryfsSession internal constructor(
    context: Context,
    vaultRootUri: Uri,
    handle: Long,
    readOnly: Boolean,
    volIdRef: java.util.concurrent.atomic.AtomicInteger = java.util.concurrent.atomic.AtomicInteger(-1),
) : NativeVaultSession(context, vaultRootUri, ContainerFormat.CRYFS, handle, readOnly, volIdRef)
