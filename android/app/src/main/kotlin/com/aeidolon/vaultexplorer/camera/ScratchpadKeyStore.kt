package com.aeidolon.vaultexplorer.camera

import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * Holds ephemeral AES-256 keys for in-progress Quick Capture scratchpad
 * sessions (see docs/architecture.md, "Capture-First + Encrypted
 * Scratchpad"), keyed by an opaque session token.
 *
 * Keys live ONLY here, in this process's heap, for exactly as long as a
 * capture is awaiting a save/discard decision. They are never written to
 * disk, never included in a backup, and never cross the Flutter method
 * channel -- Dart only ever holds the token (via
 * [QuickCaptureScratchpadPlugin]) and the scratchpad file's path, both of
 * which are useless without the key held here.
 *
 * A process death (OOM kill, force-stop, crash) drops every entry along
 * with the process. That's intentional, not a bug to work around: any
 * scratchpad file found on the next launch with no matching key is
 * unrecoverable ciphertext, which is exactly what
 * [ScratchpadTransfer.sweepOrphaned] expects and simply wipes -- see its
 * doc comment. It also means a quick capture in progress does not
 * survive the app process being killed, the same tradeoff the person who
 * spec'd this flow asked for explicitly (an ephemeral, RAM-only key)
 * over a device-Keystore-backed key that would survive a process death
 * but persist the key material, even if only in wrapped form, for the
 * lifetime of the pending capture.
 */
object ScratchpadKeyStore {
    private val keys = ConcurrentHashMap<String, SecretKey>()
    private val secureRandom = SecureRandom()

    /** Generates a fresh 256-bit AES key, stores it under a new random
     *  token, and returns the token. */
    fun createSession(): String {
        val tokenBytes = ByteArray(16).also { secureRandom.nextBytes(it) }
        val token = tokenBytes.joinToString("") { "%02x".format(it) }
        val keyGen = KeyGenerator.getInstance("AES")
        keyGen.init(256, secureRandom)
        keys[token] = keyGen.generateKey()
        return token
    }

    fun get(token: String): SecretKey? = keys[token]

    /** Drops the key for [token], if present. Wiping the scratchpad file
     *  itself (if any) is the caller's responsibility -- see
     *  [ScratchpadTransfer.finalizeIntoVault]/[ScratchpadTransfer.discard] --
     *  this only ever forgets the key. */
    fun forget(token: String) {
        keys.remove(token)
    }
}
