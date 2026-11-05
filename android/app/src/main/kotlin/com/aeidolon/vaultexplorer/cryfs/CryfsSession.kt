package com.aeidolon.vaultexplorer.cryfs

import android.content.Context
import android.net.Uri
import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.foldervault.NativeVaultSession

/**
 * An unlocked CryFS vault. Vault operations run in the native core
 * (cpp/foldervault); [config] is rebuilt on demand for the folder Check &
 * Repair tooling.
 */
class CryfsSession internal constructor(
    context: Context,
    vaultRootUri: Uri,
    handle: Long,
    readOnly: Boolean,
    volIdRef: java.util.concurrent.atomic.AtomicInteger = java.util.concurrent.atomic.AtomicInteger(-1),
) : NativeVaultSession(context, vaultRootUri, ContainerFormat.CRYFS, handle, readOnly, volIdRef) {

    val config: CryfsConfig by lazy {
        val k = keyMaterial()
        CryfsConfig(
            blockCipherName = k.string("blockCipherName"),
            encryptionKey = k.bytes("key"),
            blocksizeBytes = k.string("blocksizeBytes").toInt(),
            rootBlobId = CryfsBlockId.fromHex(k.string("rootBlobId")),
            filesystemId = k.bytes("filesystemId"),
            exclusiveClientId = k.stringOrNull("exclusiveClientId")?.toLong(),
            formatVersion = k.string("formatVersion"),
            createdWithVersion = k.string("createdWithVersion"),
            lastOpenedWithVersion = k.string("lastOpenedWithVersion"),
        )
    }
}
