package com.aeidolon.vaultexplorer.handlers

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.system.Os
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.concurrent.ExecutorService
import com.aeidolon.vaultexplorer.container.ContainerEngine
import com.aeidolon.vaultexplorer.internalvault.InternalVaultStorage
import com.aeidolon.vaultexplorer.MainActivity
import com.aeidolon.vaultexplorer.NativeOpSupport
import com.aeidolon.vaultexplorer.PendingActivityResult

/**
 * Vault creation: the ACTION_CREATE_DOCUMENT-based flow for VeraCrypt/LUKS
 * containers (including optional hidden-volume creation), plus the
 * directory-vault formats (Cryptomator/gocryptfs/CryFS), which create
 * their vault.cryptomator/gocryptfs.conf/cryfs.config directly against an
 * already-picked folder URI with no further system UI needed.
 */
class VaultCreationHandlers(
    private val activity: MainActivity,
    private val pendingResult: PendingActivityResult,
    private val ioExecutor: ExecutorService,
    private val nativeOps: NativeOpSupport,
) {
    companion object {
        /**
         * True if neither a password nor any keyfiles were supplied for a
         * create-container call. Extracted as a pure function (no
         * MainActivity/Android dependency) purely so it's directly testable
         * from a plain JVM unit test — see
         * PendingResultLeakTest's "invalid create call never stashes"
         * case, which exercises this exact predicate to confirm
         * [handleCreateContainer] replies and returns *before* calling
         * [PendingActivityResult.stash], never after.
         */
        fun isMissingCredentials(password: String, keyfilePaths: List<String>?): Boolean =
            password.isEmpty() && keyfilePaths.isNullOrEmpty()

        /**
         * Free space that must remain after creating a container in app
         * storage. That folder shares the volume with the app's own data and
         * the OS, so unlike a container on an SD card it must never be allowed
         * to fill the volume, even when a quick format would leave most of
         * the file sparse initially.
         */
        const val APP_STORAGE_RESERVE_BYTES = 64L * 1024 * 1024

        /** Same idea for a folder vault, which starts tiny and grows as files are added. */
        const val APP_STORAGE_FOLDER_VAULT_RESERVE_BYTES = 16L * 1024 * 1024
    }

    private val createContainerLock = Object()

    private data class PendingCreate(
        val name: String, val sizeBytes: Long, val password: String,
        val pim: Int, val fileSystem: String,
        val containerFormat: Int = 0,
        val cipherId: Int = 255, val hashId: Int = 255,
        val keyfilePaths: List<String>? = null,
        val quickFormat: Boolean = false,
        val createHiddenVolume: Boolean = false,
        val hiddenPassword: String? = null,
        val hiddenFileSystem: String? = null,
        val hiddenSizeBytes: Long = 0,
        val hiddenKeyfilePaths: List<String>? = null,
        val hiddenPim: Int = 0,
        val hiddenCipherId: Int = 255,
        val hiddenHashId: Int = 255,
        /** Touch-movement entropy from the wizard (null = skipped); wiped once the create call returns. */
        val userEntropy: ByteArray? = null,
    )
    private class InsufficientSpaceException(
        val neededBytes: Long,
        val availableBytes: Long,
    ) : IOException("Not enough local space to stage this container")

    private var pendingCreate: PendingCreate? = null

    private fun statvfsAvailableBytes(pfd: ParcelFileDescriptor): Long? = try {
        val stat = Os.fstatvfs(pfd.fileDescriptor)
        stat.f_bavail * stat.f_frsize
    } catch (_: Exception) {
        null
    }

    /**
     * Native container creation needs truncate plus random `pwrite` access.
     * Many SAF providers (especially cloud-storage bridges) only expose
     * sequential output streams, and reject the `rw` mode before native code
     * can write anything. Build the container in a regular local file, then
     * stream the completed bytes to the document the user selected.
     */
    private fun createLocalContainer(create: PendingCreate, stagingTarget: File? = null): File {
        // With no target the container is staged in the cache and later streamed to a document;
        // with one (app storage) it is built where it will stay, then renamed into place.
        val stagingFile = stagingTarget?.also {
            if (!it.createNewFile()) throw IOException("Staging file already exists")
        } ?: File.createTempFile("vaultexplorer-container-", ".tmp", activity.cacheDir)
        try {
            ParcelFileDescriptor.open(stagingFile, ParcelFileDescriptor.MODE_READ_WRITE).use { pfd ->
                // A non-quick create encrypts the full virtual disk into the
                // staging file. Quick format can keep most of that file sparse.
                val availableBytes = statvfsAvailableBytes(pfd)
                if (!create.quickFormat && availableBytes != null && availableBytes < create.sizeBytes) {
                    throw InsufficientSpaceException(create.sizeBytes, availableBytes)
                }
                val keyfileFds = nativeOps.openKeyfileFds(create.keyfilePaths)
                val success = synchronized(createContainerLock) {
                    if (create.createHiddenVolume && create.containerFormat == 0) {
                        val hiddenKeyfileFds = nativeOps.openKeyfileFds(create.hiddenKeyfilePaths)
                        ContainerEngine.createWithHidden(
                            pfd.detachFd(), create.password, create.hiddenPassword ?: "",
                            create.pim, create.hiddenPim, create.sizeBytes,
                            create.fileSystem, create.hiddenFileSystem ?: "fat",
                            create.hiddenSizeBytes,
                            create.cipherId, create.hashId,
                            create.hiddenCipherId, create.hiddenHashId,
                            keyfileFds, hiddenKeyfileFds,
                            create.quickFormat, create.userEntropy
                        )
                    } else {
                        ContainerEngine.create(
                            pfd.detachFd(), create.password, create.pim, create.sizeBytes, create.fileSystem,
                            create.containerFormat, create.cipherId, create.hashId, keyfileFds,
                            create.quickFormat, create.userEntropy
                        )
                    }
                }
                if (!success) throw IOException("Container creation failed")
            }
            if (stagingFile.length() == 0L) throw IOException("Container creation produced an empty file")
            return stagingFile
        } catch (e: Exception) {
            stagingFile.delete()
            throw e
        }
    }

    private fun copyToDocument(stagingFile: File, destUri: Uri) {
        val output = activity.contentResolver.openOutputStream(destUri, "wt")
            ?: throw IOException("Could not open the selected cloud document for writing")
        var copiedBytes = 0L
        output.use { out ->
            FileInputStream(stagingFile).use { input ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    out.write(buffer, 0, count)
                    copiedBytes += count
                }
                out.flush()
            }
        }
        if (copiedBytes != stagingFile.length()) {
            throw IOException("Only $copiedBytes of ${stagingFile.length()} container bytes were uploaded")
        }
    }

    private fun deleteIncompleteDocument(uri: Uri) {
        try { DocumentFile.fromSingleUri(activity, uri)?.delete() } catch (_: Exception) {}
    }

    private val createContainerLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { activityResult ->
        val res = pendingResult.take() ?: return@registerForActivityResult
        val create = pendingCreate
        pendingCreate = null

        val data = activityResult.data
        if (activityResult.resultCode == Activity.RESULT_OK && data?.data != null && create != null) {
            val destUri = data.data!!
            ioExecutor.execute {
                var stagingFile: File? = null
                try {
                    stagingFile = createLocalContainer(create)
                    copyToDocument(stagingFile, destUri)
                    activity.runOnUiThread {
                        res.success(mapOf("success" to true, "uri" to destUri.toString()))
                    }
                } catch (e: InsufficientSpaceException) {
                    deleteIncompleteDocument(destUri)
                    activity.runOnUiThread {
                        res.error(
                            "INSUFFICIENT_SPACE",
                            e.message,
                            mapOf("neededBytes" to e.neededBytes, "availableBytes" to e.availableBytes)
                        )
                    }
                } catch (e: Exception) {
                    deleteIncompleteDocument(destUri)
                    activity.runOnUiThread { nativeOps.dispatchNativeError(e, res) }
                } finally {
                    stagingFile?.delete()
                    create.userEntropy?.fill(0)
                }
            }
        } else {
            create?.userEntropy?.fill(0)
            res.success(mapOf("success" to false, "uri" to null))
        }
    }

    fun handleCreateContainer(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("displayName") ?: "vault.hc"
        val password = call.argument<String>("password") ?: ""
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        if (isMissingCredentials(password, keyfilePaths)) {
            result.error("INVALID_ARGS", "password or keyfiles required", null)
            return
        }

        pendingCreate = parsePendingCreate(call, name, password, keyfilePaths)
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        createContainerLauncher.launch(intent)
    }

    private fun parsePendingCreate(
        call: MethodCall,
        name: String,
        password: String,
        keyfilePaths: List<String>?,
    ): PendingCreate {
        return PendingCreate(
            name        = name,
            sizeBytes   = call.argument<Number>("sizeBytes")?.toLong() ?: 0L,
            password    = password,
            pim         = call.argument<Number>("pim")?.toInt() ?: 0,
            fileSystem  = call.argument<String>("fileSystem") ?: "fat",
            containerFormat = call.argument<Number>("containerFormat")?.toInt() ?: 0,
            cipherId    = call.argument<Number>("cipherId")?.toInt() ?: 255,
            hashId      = call.argument<Number>("hashId")?.toInt() ?: 255,
            keyfilePaths = keyfilePaths,
            quickFormat = call.argument<Boolean>("quickFormat") ?: false,
            createHiddenVolume = call.argument<Boolean>("createHiddenVolume") ?: false,
            hiddenPassword = call.argument<String>("hiddenPassword"),
            hiddenFileSystem = call.argument<String>("hiddenFileSystem"),
            hiddenSizeBytes = call.argument<Number>("hiddenSizeBytes")?.toLong() ?: 0L,
            hiddenKeyfilePaths = call.argument<List<String>>("hiddenKeyfilePaths"),
            hiddenPim = call.argument<Number>("hiddenPim")?.toInt() ?: 0,
            hiddenCipherId = call.argument<Number>("hiddenCipherId")?.toInt() ?: 255,
            hiddenHashId = call.argument<Number>("hiddenHashId")?.toInt() ?: 255,
            userEntropy = call.argument<ByteArray>("userEntropy"),
        )
    }

    // ── App storage ─────────────────────────────────────────────────────────
    // Vaults created in the app's private storage: no file picker, no SAF.

    /**
     * Creates a container in app storage (same arguments as [handleCreateContainer], minus the picker).
     * Built under a hidden staging name inside the vault folder and renamed into place only once complete,
     * so a crash can never leave a truncated vault under a real name.
     */
    fun handleCreateAppStorageContainer(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("displayName") ?: "vault.hc"
        val password = call.argument<String>("password") ?: ""
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        if (isMissingCredentials(password, keyfilePaths)) {
            call.argument<ByteArray>("userEntropy")?.fill(0)
            result.error("INVALID_ARGS", "password or keyfiles required", null)
            return
        }
        val create = parsePendingCreate(call, name, password, keyfilePaths)
        ioExecutor.execute {
            val store = InternalVaultStorage.store(activity)
            var staging: File? = null
            var reserved: File? = null
            var published = false
            try {
                val uri = InternalVaultStorage.runOperation {
                    val free = store.availableBytes()
                    val needed = create.sizeBytes + APP_STORAGE_RESERVE_BYTES
                    if (free < needed) throw InsufficientSpaceException(needed, free)
                    val claimed = store.reserveContainerFile(create.name).also { reserved = it }
                    val stage = store.newStagingPath().also { staging = it }
                    createLocalContainer(create, stage)
                    store.publish(stage, claimed)
                    published = true
                    InternalVaultStorage.uriString(claimed)
                }
                activity.runOnUiThread { result.success(mapOf("success" to true, "uri" to uri)) }
            } catch (e: InsufficientSpaceException) {
                cleanUpAppStorageCreate(store, staging, reserved, published)
                activity.runOnUiThread {
                    result.error(
                        "INSUFFICIENT_SPACE",
                        e.message,
                        mapOf("neededBytes" to e.neededBytes, "availableBytes" to e.availableBytes),
                    )
                }
            } catch (e: Exception) {
                cleanUpAppStorageCreate(store, staging, reserved, published)
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            } finally {
                create.userEntropy?.fill(0)
            }
        }
    }

    /**
     * Creates a Cryptomator / gocryptfs / CryFS vault in app storage. [format] is `cryptomator`, `gocryptfs` or
     * `cryfs`; the other arguments are those of the matching per-format create call. Built in a hidden staging
     * directory and renamed into place on success. Replies with the new vault's `file://` URI.
     */
    fun handleCreateAppStorageFolderVault(call: MethodCall, result: MethodChannel.Result) {
        val format = call.argument<String>("format")
        val name = call.argument<String>("displayName") ?: "Vault"
        val password = call.argument<String>("password") ?: ""
        val cipher = call.argument<String>("cipher") ?: ""
        val userEntropy = call.argument<ByteArray>("userEntropy")
        val deterministicNames = call.argument<Boolean>("deterministicNames") ?: false
        val longNameMax = call.argument<Number>("longNameMax")?.toInt() ?: 0
        val blockSize = call.argument<Number>("blockSize")?.toInt() ?: 0
        if (format !in listOf("cryptomator", "gocryptfs", "cryfs") || password.isEmpty()) {
            userEntropy?.fill(0)
            result.error("INVALID_ARGS", "a known format and a password are required", null)
            return
        }
        ioExecutor.execute {
            val store = InternalVaultStorage.store(activity)
            var staging: File? = null
            var reserved: File? = null
            var published = false
            try {
                val uri = InternalVaultStorage.runOperation {
                    val free = store.availableBytes()
                    if (free < APP_STORAGE_FOLDER_VAULT_RESERVE_BYTES) {
                        throw InsufficientSpaceException(APP_STORAGE_FOLDER_VAULT_RESERVE_BYTES, free)
                    }
                    val claimed = store.reserveFolderVaultDir(name).also { reserved = it }
                    val stage = store.newStagingPath().also { staging = it }
                    if (!stage.mkdir()) throw IOException("Could not create the vault folder")
                    val stageUri = Uri.parse(InternalVaultStorage.uriString(stage))
                    val passwordChars = password.toCharArray()
                    val createResult = try {
                        when (format) {
                            "cryptomator" -> com.aeidolon.vaultexplorer.cryptomator.CryptomatorVault.create(
                                activity, stageUri, passwordChars, userEntropy,
                            )
                            "gocryptfs" -> com.aeidolon.vaultexplorer.gocryptfs.GocryptfsVault.create(
                                activity, stageUri, passwordChars, cipher, userEntropy = userEntropy,
                                deterministicNames = deterministicNames, longNameMax = longNameMax,
                            )
                            else -> com.aeidolon.vaultexplorer.cryfs.CryfsVault.create(
                                activity, stageUri, passwordChars, cipher, blockSize, userEntropy,
                            )
                        }
                    } finally {
                        passwordChars.fill('\u0000')
                        userEntropy?.fill(0)
                    }
                    when (createResult) {
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success -> createResult.session.close()
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault ->
                            throw IOException(createResult.reason)
                        else -> throw IOException("Unexpected result")
                    }
                    store.publish(stage, claimed)
                    published = true
                    InternalVaultStorage.uriString(claimed)
                }
                activity.runOnUiThread { result.success(mapOf("success" to true, "uri" to uri)) }
            } catch (e: InsufficientSpaceException) {
                cleanUpAppStorageCreate(store, staging, reserved, published)
                activity.runOnUiThread {
                    result.error(
                        "INSUFFICIENT_SPACE",
                        e.message,
                        mapOf("neededBytes" to e.neededBytes, "availableBytes" to e.availableBytes),
                    )
                }
            } catch (e: Exception) {
                cleanUpAppStorageCreate(store, staging, reserved, published)
                // A rejected creation (for example a too-weak setting) carries its own message.
                activity.runOnUiThread {
                    if (e is IOException) result.error("CREATE_FAILED", e.message, null)
                    else nativeOps.dispatchNativeError(e, result)
                }
            } finally {
                userEntropy?.fill(0)
            }
        }
    }

    /** Removes what a failed app-storage creation left: the staging entry and the reserved (still empty) name. */
    private fun cleanUpAppStorageCreate(
        store: com.aeidolon.vaultexplorer.internalvault.AppVaultStore,
        staging: File?,
        reserved: File?,
        published: Boolean,
    ) {
        if (published) return
        staging?.let { store.deleteTree(it) }
        reserved?.let { store.deleteTree(it) }
    }

    fun handleCreateCryptomatorVault(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val password = call.argument<String>("password") ?: ""
        val userEntropy = call.argument<ByteArray>("userEntropy")
        if (uriString == null || password.isEmpty()) {
            userEntropy?.fill(0)
            result.error("INVALID_ARGS", "filePath and password required", null)
            return
        }
        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val passwordChars = password.toCharArray()
                val createResult = try {
                    com.aeidolon.vaultexplorer.cryptomator.CryptomatorVault.create(
                        activity, uri, passwordChars, userEntropy
                    )
                } finally {
                    passwordChars.fill('\u0000')
                    userEntropy?.fill(0)
                }
                activity.runOnUiThread {
                    when (createResult) {
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success -> {
                            createResult.session.close()
                            result.success(true)
                        }
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault -> {
                            result.error("CREATE_FAILED", createResult.reason, null)
                        }
                        else -> result.error("CREATE_FAILED", "Unexpected result", null)
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleCreateGocryptfsVault(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val password = call.argument<String>("password") ?: ""
        // 'aes-256-gcm' (default) or 'xchacha20-poly1305'. Passed through as is: the native core picks the cipher
        // and falls back to AES-256-GCM for anything else (including omitted/older Dart callers).
        val cipher = call.argument<String>("cipher") ?: ""
        val userEntropy = call.argument<ByteArray>("userEntropy")
        // Both optional: callers from before these options existed omit them.
        val deterministicNames = call.argument<Boolean>("deterministicNames") ?: false
        val longNameMax = call.argument<Number>("longNameMax")?.toInt() ?: 0
        if (uriString == null || password.isEmpty()) {
            userEntropy?.fill(0)
            result.error("INVALID_ARGS", "filePath and password required", null)
            return
        }
        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val passwordChars = password.toCharArray()
                val createResult = try {
                    com.aeidolon.vaultexplorer.gocryptfs.GocryptfsVault.create(
                        activity, uri, passwordChars, cipher, userEntropy = userEntropy,
                        deterministicNames = deterministicNames, longNameMax = longNameMax,
                    )
                } finally {
                    passwordChars.fill('\u0000')
                    userEntropy?.fill(0)
                }
                activity.runOnUiThread {
                    when (createResult) {
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success -> {
                            createResult.session.close()
                            result.success(true)
                        }
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault -> {
                            result.error("CREATE_FAILED", createResult.reason, null)
                        }
                        else -> result.error("CREATE_FAILED", "Unexpected result", null)
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }

    fun handleCreateCryfsVault(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val password = call.argument<String>("password") ?: ""
        // 'xchacha20-poly1305' (default) or 'aes-256-gcm', and the on-disk block size in bytes (CryFS CLI's
        // `--blocksize`). Passed through as is: the native core (fv_formats.h) falls back to its defaults for a
        // missing or unsupported cipher and for a block size outside 4 KiB..64 MiB, so older Dart callers and
        // malformed values cannot produce a vault that does not work.
        val cipher = call.argument<String>("cipher") ?: ""
        val blockSize = call.argument<Number>("blockSize")?.toInt() ?: 0
        val userEntropy = call.argument<ByteArray>("userEntropy")
        if (uriString == null || password.isEmpty()) {
            userEntropy?.fill(0)
            result.error("INVALID_ARGS", "filePath and password required", null)
            return
        }
        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val passwordChars = password.toCharArray()
                val createResult = try {
                    com.aeidolon.vaultexplorer.cryfs.CryfsVault.create(
                        activity, uri, passwordChars, cipher, blockSize, userEntropy
                    )
                } finally {
                    passwordChars.fill('\u0000')
                    userEntropy?.fill(0)
                }
                activity.runOnUiThread {
                    when (createResult) {
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.Success -> {
                            createResult.session.close()
                            result.success(true)
                        }
                        is com.aeidolon.vaultexplorer.engine.VaultOpenResult.InvalidVault -> {
                            result.error("CREATE_FAILED", createResult.reason, null)
                        }
                        else -> result.error("CREATE_FAILED", "Unexpected result", null)
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { nativeOps.dispatchNativeError(e, result) }
            }
        }
    }
}
