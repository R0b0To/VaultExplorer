package com.aeidolon.vaultexplorer.gocryptfs

import android.content.Context
import android.net.Uri
import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.foldervault.NativeVaultSession

/**
 * An unlocked gocryptfs vault. All vault operations run in the native core
 * (cpp/foldervault); this class only adds [nameCryptor] / [contentCryptor],
 * rebuilt on demand from the session's key material, because the folder
 * Check & Repair tooling still walks the vault with the Kotlin primitives.
 */
class GocryptfsSession internal constructor(
    context: Context,
    vaultRootUri: Uri,
    handle: Long,
    readOnly: Boolean,
    volIdRef: java.util.concurrent.atomic.AtomicInteger = java.util.concurrent.atomic.AtomicInteger(-1),
) : NativeVaultSession(context, vaultRootUri, ContainerFormat.GOCRYPTFS, handle, readOnly, volIdRef) {

    val nameCryptor: GocryptfsFileNameCryptor by lazy {
        val k = keyMaterial()
        GocryptfsFileNameCryptor(
            k.bytes("nameKey"), k.string("longNameMax").toInt(), k.string("plaintextNames") == "1",
            raw64 = k.stringOrNull("raw64") != "0",
        )
    }

    val contentCryptor: GocryptfsContentCryptor by lazy {
        val k = keyMaterial()
        GocryptfsContentCryptor(k.bytes("contentKey"), GocryptfsCipher.values()[k.string("cipher").toInt()])
    }
}
