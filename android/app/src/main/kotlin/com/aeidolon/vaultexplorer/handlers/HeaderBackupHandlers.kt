package com.aeidolon.vaultexplorer.handlers

import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeEngine
import com.aeidolon.vaultexplorer.container.ContainerFormat
import com.aeidolon.vaultexplorer.saf.SafDocumentOps

/**
 * Container Utilities → Header Backup ([HeaderBackupSheet] on the Dart
 * side): export a container's (or folder vault's) header/key material to
 * an external file, and restore it later. Two very different families of
 * "header" are handled:
 *
 *  * A single-file container (VeraCrypt/LUKS1/LUKS2) whose header is a
 *    byte range at the start of the file -- see container_repair.cpp's
 *    "Header Backup / Restore" section for exactly what that range is per
 *    format and how it's verified before ever being restored. The actual
 *    file bytes cross the platform channel as a `ByteArray`; wrapping them
 *    with a magic/checksum envelope for the on-device backup file is a
 *    Dart-side concern (see header_backup_service.dart) since it's just
 *    framing, not anything that needs native code.
 *
 *  * A gocryptfs/CryFS/Cryptomator folder vault, whose entire key material
 *    lives in one small file at the vault root (gocryptfs.conf /
 *    cryfs.config / masterkey.cryptomator) -- lose that file and every
 *    encrypted file in the vault is unrecoverable even though the data
 *    itself is untouched. [handleResolveFolderVaultConfigFile] locates it
 *    for export (the actual byte read then reuses
 *    [HashVerifierHandlers.handleReadExternalFileBytes], since it's just
 *    "read a small file" once the URI is known).
 *    [handleRestoreFolderVaultConfig] handles the restore direction itself
 *    (rather than deferring to [HashVerifierHandlers.handleWriteExternalFileBytes])
 *    because restoring is the higher-stakes direction -- overwriting a
 *    live vault's only key material -- so it's worth validating the
 *    payload actually parses as a genuine config for the claimed format
 *    before ever touching the vault. That validation is structural only
 *    (does it parse, do the expected fields exist) -- it does NOT prove
 *    the payload's password matches the vault's, since that would require
 *    a full unlock attempt; the Dart UI is upfront about that.
 */
class HeaderBackupHandlers(
    private val activity: MainActivity,
    private val ioExecutor: ExecutorService,
) {
    private val folderVaultConfigFileNames = mapOf(
        "gocryptfs" to "gocryptfs.conf",
        "cryfs" to "cryfs.config",
        "cryptomator" to "masterkey.cryptomator",
        "directory_vault" to "masterkey.cryptomator",
    )

    private fun containerFormatOrdinalForWire(wire: String): Int? = when (wire) {
        "veracrypt" -> 0
        "luks1" -> 1
        "luks2" -> 2
        else -> null
    }

    // ── Single-file containers (VeraCrypt/LUKS) ─────────────────────────

    /**
     * Reads [uri]'s header region (see container_repair.cpp) and returns
     * `{"format": wireName, "bytes": ByteArray}` on success. Errors:
     * `UNRECOGNIZED_FILE` (not a supported container at all),
     * `UNSUPPORTED_FORMAT` (BitLocker/Plain -- no header backup support),
     * `HEADER_UNREADABLE` (recognized format, but its sizing fields don't
     * parse -- suggest Check & Repair first), `IO_ERROR`.
     */
    fun handleExportContainerHeader(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val opId = call.argument<Number>("opId")?.toInt() ?: -1
        if (uri.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "uri required", null)
            return
        }

        ioExecutor.execute {
            try {
                val pfd = activity.contentResolver.openFileDescriptor(Uri.parse(uri), "r")
                    ?: throw Exception("Could not open file descriptor")
                val packed = NativeEngine.nativeExportContainerHeader(pfd.detachFd(), opId)
                activity.runOnUiThread {
                    if (packed == null || packed.size < 10) {
                        result.error("IO_ERROR", "Could not read the container file", null)
                        return@runOnUiThread
                    }
                    when (val resultCode = packed[0].toInt() and 0xFF) {
                        0 -> {
                            val formatOrdinal = packed[1].toInt() and 0xFF
                            val format = ContainerFormat.fromNative(formatOrdinal).wireName
                            val payload = packed.copyOfRange(10, packed.size)
                            result.success(mapOf("format" to format, "bytes" to payload))
                        }
                        1 -> result.error(
                            "UNRECOGNIZED_FILE",
                            "This doesn't look like a container this app recognizes.",
                            null,
                        )
                        2 -> result.error(
                            "UNSUPPORTED_FORMAT",
                            "This container format doesn't support header backup.",
                            null,
                        )
                        3 -> result.error(
                            "HEADER_UNREADABLE",
                            "Could not read this container's header fields -- try Check & Repair first.",
                            null,
                        )
                        else -> result.error("IO_ERROR", "Could not read the container file (code $resultCode)", null)
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message, null) }
            }
        }
    }

    /**
     * Verifies [bytes] is a genuine header for [format] (decrypt-and-CRC
     * for VeraCrypt, needs [password]; checksum for LUKS2; field-sanity
     * for LUKS1 -- see container_repair.cpp), then overwrites [uri]'s
     * leading header bytes with it. [pim]/[cipherId]/[hashId] of 255
     * auto-detect, same defaults [VaultRepairApi.restoreBackupHeaderUnmounted]
     * uses. Errors: `PASSWORD_REQUIRED`/`PASSWORD_INCORRECT` (VeraCrypt
     * only), `BACKUP_INVALID`, `SIZE_MISMATCH` (the target is smaller than
     * the backup -- almost certainly the wrong file), `UNSUPPORTED_FORMAT`,
     * `IO_ERROR`.
     */
    fun handleRestoreContainerHeaderRegion(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val format = call.argument<String>("format")
        val bytes = call.argument<ByteArray>("bytes")
        val password = call.argument<String>("password")
        val pim = call.argument<Number>("pim")?.toInt() ?: 0
        val cipherId = call.argument<Number>("cipherId")?.toInt() ?: 255
        val hashId = call.argument<Number>("hashId")?.toInt() ?: 255
        val opId = call.argument<Number>("opId")?.toInt() ?: -1
        if (uri.isNullOrEmpty() || format.isNullOrEmpty() || bytes == null || bytes.isEmpty()) {
            result.error("INVALID_ARGS", "uri, format, and bytes are required", null)
            return
        }
        val formatOrdinal = containerFormatOrdinalForWire(format)
        if (formatOrdinal == null) {
            result.error("UNSUPPORTED_FORMAT", "This container format doesn't support header restore.", null)
            return
        }
        if (formatOrdinal == 0 && password.isNullOrEmpty()) {
            result.error("PASSWORD_REQUIRED", "A password is needed to verify the backup header", null)
            return
        }

        ioExecutor.execute {
            try {
                val pfd = activity.contentResolver.openFileDescriptor(Uri.parse(uri), "rw")
                    ?: throw Exception("Could not open file descriptor")
                val outcome = NativeEngine.nativeRestoreContainerHeaderRegion(
                    pfd.detachFd(), formatOrdinal, bytes, password, pim, cipherId, hashId, opId,
                )
                activity.runOnUiThread {
                    when (outcome) {
                        0 -> result.success(true)
                        1 -> result.error("PASSWORD_INCORRECT", "Incorrect password", null)
                        2 -> result.error(
                            "BACKUP_INVALID",
                            "This backup doesn't look genuine for this container.",
                            null,
                        )
                        3 -> result.error(
                            "SIZE_MISMATCH",
                            "The selected container is smaller than the backup header -- wrong file?",
                            null,
                        )
                        else -> result.error("IO_ERROR", "Could not restore the header (code $outcome)", null)
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message, null) }
            }
        }
    }

    // ── Folder vaults (gocryptfs/CryFS/Cryptomator) ─────────────────────

    /**
     * Locates [format]'s config/masterkey file inside the vault at [uri]
     * (a SAF tree Uri) and returns `{"fileName": ..., "uri": contentUri?,
     * "exists": Boolean}`. `uri` is null when the file isn't there right
     * now (e.g. it was already lost) -- `fileName` is still returned so
     * the Dart caller knows what a restore would need to recreate.
     */
    fun handleResolveFolderVaultConfigFile(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        val format = call.argument<String>("format")
        if (uriStr.isNullOrEmpty() || format.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "uri and format are required", null)
            return
        }
        val fileName = folderVaultConfigFileNames[format]
        if (fileName == null) {
            result.error("UNSUPPORTED_FORMAT", "Unknown folder vault format: $format", null)
            return
        }

        ioExecutor.execute {
            try {
                val root = DocumentFile.fromTreeUri(activity, Uri.parse(uriStr))
                    ?: throw Exception("Cannot access the selected folder.")
                val saf = SafDocumentOps(activity)
                val configDoc = saf.childOf(root, fileName)
                activity.runOnUiThread {
                    result.success(
                        mapOf(
                            "fileName" to fileName,
                            "uri" to configDoc?.uri?.toString(),
                            "exists" to (configDoc != null),
                        ),
                    )
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }

    /**
     * Validates [bytes] structurally parses as a genuine [format]
     * config/masterkey file (see this class's doc comment for exactly
     * what that does and doesn't prove), then replaces the vault's
     * existing config file at [uri] with it -- creating it if it's
     * currently missing. `BACKUP_INVALID` if validation fails (nothing is
     * written); `UNSUPPORTED_FORMAT` for an unrecognized format.
     */
    fun handleRestoreFolderVaultConfig(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        val format = call.argument<String>("format")
        val bytes = call.argument<ByteArray>("bytes")
        if (uriStr.isNullOrEmpty() || format.isNullOrEmpty() || bytes == null || bytes.isEmpty()) {
            result.error("INVALID_ARGS", "uri, format, and bytes are required", null)
            return
        }
        val fileName = folderVaultConfigFileNames[format]
        if (fileName == null) {
            result.error("UNSUPPORTED_FORMAT", "Unknown folder vault format: $format", null)
            return
        }

        ioExecutor.execute {
            try {
                val invalidReason: String? = when (format) {
                    "gocryptfs" -> try {
                        com.aeidolon.vaultexplorer.gocryptfs.GocryptfsConfig.parse(bytes)
                        null
                    } catch (e: Exception) {
                        e.message ?: "Malformed gocryptfs.conf"
                    }
                    "cryptomator", "directory_vault" -> try {
                        com.aeidolon.vaultexplorer.cryptomator.CryptomatorMasterkeyFile.parse(bytes)
                        null
                    } catch (e: Exception) {
                        e.message ?: "Malformed masterkey.cryptomator"
                    }
                    "cryfs" -> {
                        // cryfs.config's outer envelope is itself password-encrypted
                        // (see CryfsConfigFile.kt), so this can't fully parse it
                        // without a password -- just check the cleartext prefix
                        // every genuine cryfs.config starts with, plus its fixed
                        // total size.
                        val prefix = "cryfs.config;1;scrypt".toByteArray(Charsets.US_ASCII)
                        val looksGenuine = bytes.size >= 1024 &&
                            bytes.copyOfRange(0, prefix.size).contentEquals(prefix)
                        if (looksGenuine) null else "Doesn't look like a genuine cryfs.config."
                    }
                    else -> "Unknown folder vault format: $format"
                }
                if (invalidReason != null) {
                    activity.runOnUiThread { result.error("BACKUP_INVALID", invalidReason, null) }
                    return@execute
                }

                val root = DocumentFile.fromTreeUri(activity, Uri.parse(uriStr))
                    ?: throw Exception("Cannot access the selected folder.")
                val saf = SafDocumentOps(activity)
                saf.childOf(root, fileName)?.delete()
                val doc = saf.createFileSafe(root, "application/octet-stream", fileName)
                    ?: throw Exception("Could not create \"$fileName\" in the vault folder")
                saf.writeWhole(doc, bytes)

                activity.runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("IO_ERROR", e.message ?: e.toString(), null) }
            }
        }
    }
}
