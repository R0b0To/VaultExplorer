package com.aeidolon.vaultexplorer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService

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
    private val createContainerLock = Object()

    private data class PendingCreate(
        val name: String, val sizeBytes: Long, val password: String,
        val pim: Int, val fileSystem: String,
        val containerFormat: Int = 0,
        val cipherId: Int = 255, val hashId: Int = 255,
        val keyfilePaths: List<String>? = null,
        val createHiddenVolume: Boolean = false,
        val hiddenPassword: String? = null,
        val hiddenFileSystem: String? = null,
        val hiddenSizeBytes: Long = 0,
        val hiddenKeyfilePaths: List<String>? = null,
        val hiddenPim: Int = 0,
        val hiddenCipherId: Int = 255,
        val hiddenHashId: Int = 255,
    )
    private var pendingCreate: PendingCreate? = null

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
                try {
                    val keyfileFds = nativeOps.openKeyfileFds(create.keyfilePaths)
                    val pfd = activity.contentResolver.openFileDescriptor(destUri, "rw")
                        ?: throw Exception("Could not open file descriptor")
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
                                keyfileFds, hiddenKeyfileFds
                            )
                        } else {
                            ContainerEngine.create(
                                pfd.detachFd(), create.password, create.pim, create.sizeBytes, create.fileSystem,
                                create.containerFormat, create.cipherId, create.hashId, keyfileFds
                            )
                        }
                    }
                    activity.runOnUiThread { res.success(success) }
                } catch (e: Exception) {
                    activity.runOnUiThread { nativeOps.dispatchNativeError(e, res) }
                }
            }
        } else {
            res.success(false)
        }
    }

    fun handleCreateContainer(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("displayName") ?: "vault.hc"
        val password = call.argument<String>("password") ?: ""
        val keyfilePaths = call.argument<List<String>>("keyfilePaths")
        if (password.isEmpty() && keyfilePaths.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "password or keyfiles required", null)
            return
        }

        pendingCreate = PendingCreate(
            name        = name,
            sizeBytes   = call.argument<Number>("sizeBytes")?.toLong() ?: 0L,
            password    = password,
            pim         = call.argument<Number>("pim")?.toInt() ?: 0,
            fileSystem  = call.argument<String>("fileSystem") ?: "fat",
            containerFormat = call.argument<Number>("containerFormat")?.toInt() ?: 0,
            cipherId    = call.argument<Number>("cipherId")?.toInt() ?: 255,
            hashId      = call.argument<Number>("hashId")?.toInt() ?: 255,
            keyfilePaths = keyfilePaths,
            createHiddenVolume = call.argument<Boolean>("createHiddenVolume") ?: false,
            hiddenPassword = call.argument<String>("hiddenPassword"),
            hiddenFileSystem = call.argument<String>("hiddenFileSystem"),
            hiddenSizeBytes = call.argument<Number>("hiddenSizeBytes")?.toLong() ?: 0L,
            hiddenKeyfilePaths = call.argument<List<String>>("hiddenKeyfilePaths"),
            hiddenPim = call.argument<Number>("hiddenPim")?.toInt() ?: 0,
            hiddenCipherId = call.argument<Number>("hiddenCipherId")?.toInt() ?: 255,
            hiddenHashId = call.argument<Number>("hiddenHashId")?.toInt() ?: 255,
        )
        pendingResult.stash(result)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        createContainerLauncher.launch(intent)
    }

    fun handleCreateCryptomatorVault(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("filePath")
        val password = call.argument<String>("password") ?: ""
        if (uriString == null || password.isEmpty()) {
            result.error("INVALID_ARGS", "filePath and password required", null)
            return
        }
        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val passwordChars = password.toCharArray()
                val createResult = try {
                    com.aeidolon.vaultexplorer.cryptomator.CryptomatorVault.create(activity, uri, passwordChars)
                } finally {
                    passwordChars.fill('\u0000')
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
        if (uriString == null || password.isEmpty()) {
            result.error("INVALID_ARGS", "filePath and password required", null)
            return
        }
        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val passwordChars = password.toCharArray()
                val createResult = try {
                    com.aeidolon.vaultexplorer.gocryptfs.GocryptfsVault.create(activity, uri, passwordChars)
                } finally {
                    passwordChars.fill('\u0000')
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
        if (uriString == null || password.isEmpty()) {
            result.error("INVALID_ARGS", "filePath and password required", null)
            return
        }
        ioExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val passwordChars = password.toCharArray()
                val createResult = try {
                    com.aeidolon.vaultexplorer.cryfs.CryfsVault.create(activity, uri, passwordChars)
                } finally {
                    passwordChars.fill('\u0000')
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
