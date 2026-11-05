package com.aeidolon.vaultexplorer.cryptomator

import android.content.Context
import android.net.Uri
import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.foldervault.NativeVaultSession

/**
 * An unlocked Cryptomator vault (format 7 or 8). Vault operations run in the
 * native core (cpp/foldervault); [masterkey], [nameCryptor] and
 * [contentCryptor] are rebuilt on demand for the folder Check & Repair tooling.
 */
class CryptomatorSession internal constructor(
    context: Context,
    vaultRootUri: Uri,
    handle: Long,
    readOnly: Boolean,
    volIdRef: java.util.concurrent.atomic.AtomicInteger = java.util.concurrent.atomic.AtomicInteger(-1),
) : NativeVaultSession(context, vaultRootUri, ContainerFormat.CRYPTOMATOR, handle, readOnly, volIdRef) {

    val masterkey: CryptomatorMasterkey by lazy { CryptomatorMasterkey(keyMaterial().bytes("masterkey")) }
    val vaultFormat: Int by lazy { keyMaterial().string("vaultFormat").toInt() }
    val cipherCombo: String by lazy { keyMaterial().string("cipherCombo") }
    val shorteningThreshold: Int by lazy { keyMaterial().string("shorteningThreshold").toInt() }
    val nameCryptor: CryptomatorFileNameCryptor by lazy { CryptomatorFileNameCryptor(masterkey) }
    val contentCryptor: CryptomatorContentCryptor by lazy { CryptomatorContentCryptor.forCipherCombo(cipherCombo) }
}
