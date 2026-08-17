package com.aeidolon.vaultexplorer

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import com.aeidolon.vaultexplorer.bridge.ExternalOpenBridge
import com.aeidolon.vaultexplorer.bridge.HashProgressBridge
import com.aeidolon.vaultexplorer.bridge.HiddenVolumeProtectionBridge
import com.aeidolon.vaultexplorer.bridge.ImportProgressBridge
import com.aeidolon.vaultexplorer.bridge.RepairLogBridge
import com.aeidolon.vaultexplorer.bridge.SplitJoinProgressBridge
import com.aeidolon.vaultexplorer.bridge.UnlockProgressBridge
import com.aeidolon.vaultexplorer.handlers.AppSettingsFileHandlers
import com.aeidolon.vaultexplorer.handlers.DerivedKeyHandlers
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers
import com.aeidolon.vaultexplorer.handlers.FileOperationHandlers
import com.aeidolon.vaultexplorer.handlers.FolderDocumentProviderHandlers
import com.aeidolon.vaultexplorer.handlers.HashVerifierHandlers
import com.aeidolon.vaultexplorer.handlers.ImportExportHandlers
import com.aeidolon.vaultexplorer.handlers.RepairHandlers
import com.aeidolon.vaultexplorer.handlers.SecureStorageHandlers
import com.aeidolon.vaultexplorer.handlers.SingleFileCryptoHandlers
import com.aeidolon.vaultexplorer.handlers.SplitContainerMountHandlers
import com.aeidolon.vaultexplorer.handlers.SplitJoinHandlers
import com.aeidolon.vaultexplorer.handlers.SystemPermissionHandlers
import com.aeidolon.vaultexplorer.handlers.ThumbnailHandlers
import com.aeidolon.vaultexplorer.handlers.UsbContainerHandlers
import com.aeidolon.vaultexplorer.handlers.VaultCreationHandlers
import com.aeidolon.vaultexplorer.handlers.VaultPickerHandlers
import com.aeidolon.vaultexplorer.handlers.VaultUnlockHandlers
import com.aeidolon.vaultexplorer.handlers.DisguiseChannelMethods
import com.aeidolon.vaultexplorer.handlers.STORAGE_PERMISSION_REQUEST_CODE

private object ChannelMethods {
    const val PICK_CONTAINER            = "pickContainer"
    const val PICK_KEYFILES             = "pickKeyfiles"
    const val PICK_CRYPTO_FILES         = "pickCryptoFiles"
    const val PICK_ARCHIVE_FILE         = "pickArchiveFile"
    const val PICK_EXTRACT_FOLDER       = "pickExtractFolder"
    const val CREATE_CONTAINER          = "createContainer"
    const val CREATE_USB_CONTAINER      = "createUsbContainer"
    const val GET_USB_DEVICE_CAPACITY   = "getUsbDeviceCapacity"
    const val UNLOCK_CONTAINER          = "unlockContainer"
    const val LOCK_CONTAINER            = "lockContainer"
    const val DECRYPT_FILE              = "decryptFile"
    const val EXPORT_FILE               = "exportFileToStorage"
    const val EXPORT_FILES_FOLDER       = "exportFilesToFolder"
    const val IMPORT_FILE               = "importFile"
    const val IMPORT_FOLDER             = "importFolder"
    const val EXPORT_APP_SETTINGS_FILE  = "exportAppSettingsFile"
    const val IMPORT_APP_SETTINGS_FILE  = "importAppSettingsFile"
    const val CANCEL_IMPORT             = "cancelImport"
    const val DELETE_IMPORT_SOURCES     = "deleteImportSources"
    const val GET_FILE_SIZE             = "getFileSize"
    const val READ_FILE_CHUNK           = "readFileChunk"
    const val GET_MEDIA_FILE_SIZE       = "getMediaFileSize"
    const val HAS_ALL_FILES_ACCESS      = "hasAllFilesAccess"
    const val REQUEST_ALL_FILES_ACCESS  = "requestAllFilesAccess"
    const val READ_MEDIA_FILE_CHUNK     = "readMediaFileChunk"
    const val WRITE_BACK_FILE           = "writeBackFile"
    const val GET_SPACE_INFO            = "getSpaceInfo"
    const val LIST_DIRECTORY            = "listDirectory"
    const val CREATE_DIRECTORY          = "createDirectory"
    const val RENAME_FILE               = "renameFile"
    const val DELETE_FILE               = "deleteFile"
    const val OPEN_WITH_APP             = "openWithApp"
    const val GET_VIDEO_THUMBNAIL       = "getVideoThumbnail"
    const val GET_IMAGE_THUMBNAIL       = "getImageThumbnail"
    const val GET_IMAGE_THUMBNAIL_WITH_SIZE = "getImageThumbnailWithSize"
    const val GET_VIDEO_THUMBNAIL_WITH_SIZE = "getVideoThumbnailWithSize"
    const val SET_PLAYBACK_ACTIVE       = "setPlaybackActive"
    const val GET_FOLDER_SIZE           = "getFolderSize"
    const val HASH_PASSWORD             = "hashPassword"
    const val DERIVE_DERIVED_KEY        = "deriveDerivedKey"
    const val STORE_DERIVED_KEY         = "storeDerivedKey"
    const val LOAD_DERIVED_KEY          = "loadDerivedKey"
    const val CLEAR_DERIVED_KEY         = "clearDerivedKey"
    const val WRITE_FILE_CHUNK          = "writeFileChunk"
    const val BEGIN_BATCH_WRITE         = "beginBatchWrite"
    const val END_BATCH_WRITE           = "endBatchWrite"
    const val SET_SECURE_SCREEN         = "setSecureScreen"
    const val SET_RECENTS_SNAPSHOT_BLOCKED = "setRecentsSnapshotBlocked"
    const val NOTIFY_RESUMED_FRAME_PAINTED = "notifyResumedFramePainted"
    const val SET_SENSITIVE_CLIPBOARD_TEXT = "setSensitiveClipboardText"
    const val UPDATE_CONTAINER_SETTINGS = "updateContainerSettings"
    const val LIST_USB_DEVICES          = "listUsbDevices"
    const val REQUEST_USB_PERMISSION    = "requestUsbPermission"
    const val UNLOCK_USB_CONTAINER      = "unlockUsbContainer"
    const val DOCUMENT_EXISTS           = "documentExists"
    const val WARM_CONTAINER            = "warmContainer"
    const val CANCEL_UNLOCK             = "cancelUnlock"
    const val CHANGE_CONTAINER_PASSWORD = "changeContainerPassword"
    const val CHANGE_LUKS_CONTAINER_PASSWORD = "changeLuksContainerPassword"
    const val SET_LAST_MODIFIED_TIME    = "setLastModifiedTime"
    const val PICK_CRYPTOMATOR_VAULT    = "pickCryptomatorVault"
    const val UNLOCK_CRYPTOMATOR_VAULT  = "unlockCryptomatorVault"
    const val CREATE_CRYPTOMATOR_VAULT  = "createCryptomatorVault"
    const val CHANGE_CRYPTOMATOR_VAULT_PASSWORD = "changeCryptomatorVaultPassword"
    const val PICK_GOCRYPTFS_VAULT      = "pickGocryptfsVault"
    const val UNLOCK_GOCRYPTFS_VAULT    = "unlockGocryptfsVault"
    const val CREATE_GOCRYPTFS_VAULT    = "createGocryptfsVault"
    const val CHANGE_GOCRYPTFS_VAULT_PASSWORD = "changeGocryptfsVaultPassword"
    const val FINISH_WRITE              = "finishWrite"
    const val IS_GOCRYPTFS_VAULT        = "isGocryptfsVault"
    const val PICK_CRYFS_VAULT          = "pickCryfsVault"
    const val UNLOCK_CRYFS_VAULT        = "unlockCryfsVault"
    const val CREATE_CRYFS_VAULT        = "createCryfsVault"
    const val CHANGE_CRYFS_VAULT_PASSWORD = "changeCryfsVaultPassword"
    const val IS_CRYFS_VAULT            = "isCryfsVault"
    const val MOUNT_CONTAINER_FOLDER    = "mountContainerFolder"
    const val UNMOUNT_CONTAINER_FOLDER  = "unmountContainerFolder"
    const val GET_MOUNTED_CONTAINER_FOLDERS = "getMountedContainerFolders"
    const val GET_DEVICE_CAPABILITY_PROFILE = "getDeviceCapabilityProfile"
    const val GET_AVIF_INFO = "getAvifInfo"
    const val DECODE_AVIF_FRAME = "decodeAvifFrame"
    const val DECODE_AVIF = "decodeAvif"
    const val SET_KEEP_SCREEN_ON = "setKeepScreenOn"
    const val LAUNCH_URL = "launchUrl"
    const val GET_APP_VERSION = "getAppVersion"
    const val GET_ANDROID_SDK_INT = "getAndroidSdkInt"
    const val SPLIT_CONTAINER = "splitContainer"
    const val JOIN_CONTAINER = "joinContainer"
    const val CANCEL_SPLIT_JOIN = "cancelSplitJoin"
    const val UNLOCK_SPLIT_CONTAINER = "unlockSplitContainer"
    const val ENCRYPT_SINGLE_FILE = "encryptSingleFile"
    const val DECRYPT_SINGLE_FILE = "decryptSingleFile"

    const val COMPUTE_EXTERNAL_FILE_HASH = "computeExternalFileHash"
    const val CANCEL_HASH_COMPUTE = "cancelHashCompute"
    const val READ_EXTERNAL_FILE_BYTES = "readExternalFileBytes"
    const val HASH_BYTES_SHA256 = "hashBytesSha256"
    const val HASH_BYTES_MD5 = "hashBytesMd5"
    const val BEGIN_HASH_SESSION = "beginHashSession"
    const val UPDATE_HASH_SESSION = "updateHashSession"
    const val FINISH_HASH_SESSION = "finishHashSession"
    const val DISCARD_HASH_SESSION = "discardHashSession"

    const val DIAGNOSE_UNMOUNTED_CONTAINER_FILE = "diagnoseUnmountedContainerFile"
    const val DIAGNOSE_MOUNTED_VOLUME_FILESYSTEM = "diagnoseMountedVolumeFilesystem"
    const val RESTORE_BACKUP_HEADER_UNMOUNTED = "restoreBackupHeaderUnmounted"
    const val RUN_MOUNTED_VOLUME_FILESYSTEM_CHECK = "runMountedVolumeFilesystemCheck"
    const val PICK_FOLDER_VAULT_FOR_REPAIR = "pickFolderVaultForRepair"
    const val CHECK_FOLDER_VAULT = "checkFolderVault"

    const val OPEN_PDF = "openPdf"
    const val GET_PDF_PAGE_SIZE = "getPdfPageSize"
    const val RENDER_PDF_PAGE = "renderPdfPage"
    const val CLOSE_PDF = "closePdf"

    const val IS_JETPACK_PDF_VIEWER_SUPPORTED = "isJetpackPdfViewerSupported"
    const val REGISTER_JETPACK_PDF_SESSION = "registerJetpackPdfSession"
    const val REVOKE_JETPACK_PDF_SESSION = "revokeJetpackPdfSession"
    const val PRINT_PDF = "printPdf"
}

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.aeidolon.vaultexplorer/engine"
    private val DISGUISE_CHANNEL = "com.aeidolon.vaultexplorer/disguise_channel"
    internal val ACTION_CHOOSER = "com.aeidolon.vaultexplorer.ACTION_CHOOSER"
    private var chooserReceiver: BroadcastReceiver? = null
    internal var methodChannel: MethodChannel? = null
    internal val usbManager: UsbManager by lazy {
        getSystemService(Context.USB_SERVICE) as UsbManager
    }
    private val ACTION_USB_PERMISSION = "com.aeidolon.vaultexplorer.USB_PERMISSION"
    private var usbPermissionReceiver: BroadcastReceiver? = null
    private val ioExecutor = Executors.newFixedThreadPool(4) as ThreadPoolExecutor
    private val imageThumbnailExecutor = Executors.newFixedThreadPool(2) as ThreadPoolExecutor
    private val videoThumbnailExecutor = Executors.newFixedThreadPool(1) as ThreadPoolExecutor
    private val fullResExecutor = Executors.newFixedThreadPool(2) as ThreadPoolExecutor
    private val pdfExecutor = Executors.newFixedThreadPool(2) as ThreadPoolExecutor
    private var usbDetachReceiver: BroadcastReceiver? = null
    private var screenOffReceiver: BroadcastReceiver? = null
    private var vaultCameraPlugin: com.aeidolon.vaultexplorer.camera.VaultCameraPlugin? = null
    private val privacyCurtain = PrivacyCurtain(this)
    private val pendingResult = PendingActivityResult()
    private val nativeOps = NativeOpSupport(this, ioExecutor)
    private val derivedKeyHandlers = DerivedKeyHandlers(this, ioExecutor, nativeOps)
    private val usbHandlers = UsbContainerHandlers(this, ACTION_USB_PERMISSION, ioExecutor, nativeOps, derivedKeyHandlers)
    private val vaultPickerHandlers = VaultPickerHandlers(this, pendingResult, ioExecutor)
    private val vaultCreationHandlers = VaultCreationHandlers(this, pendingResult, ioExecutor, nativeOps)
    private val vaultUnlockHandlers = VaultUnlockHandlers(this, ioExecutor, nativeOps, derivedKeyHandlers)
    private val thumbnailHandlers = ThumbnailHandlers(this, imageThumbnailExecutor, videoThumbnailExecutor, nativeOps)
    private val importExportHandlers = ImportExportHandlers(this, pendingResult, ioExecutor, nativeOps)
    private val appSettingsFileHandlers = AppSettingsFileHandlers(this, pendingResult, ioExecutor)
    private val splitJoinHandlers = SplitJoinHandlers(this, ioExecutor)
    private val singleFileCryptoHandlers = SingleFileCryptoHandlers(this, ioExecutor, nativeOps)
    private val hashVerifierHandlers = HashVerifierHandlers(this, ioExecutor)
    private val splitContainerMountHandlers = SplitContainerMountHandlers(this, ioExecutor, nativeOps, vaultUnlockHandlers)
    private val fileOperationHandlers = FileOperationHandlers(nativeOps, fullResExecutor)
    private val systemHandlers = SystemPermissionHandlers(this)
    private val folderDocumentProviderHandlers = FolderDocumentProviderHandlers(this)
    private val disguiseModeHandlers = DisguiseModeHandlers(this)
    private val secureStorageHandlers = SecureStorageHandlers(this)
    private val repairHandlers = RepairHandlers(this, ioExecutor)
    private val pdfViewerHandlers = com.aeidolon.vaultexplorer.pdf.PdfViewerHandlers(this, pdfExecutor)
    private val nativePlayerManager by lazy { com.aeidolon.vaultexplorer.engine.NativePlayerManager(this) }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        setTheme(R.style.NormalTheme)
        super.onCreate(savedInstanceState)
        disguiseModeHandlers.updateActivityIdentity()
        privacyCurtain.install()
        ioExecutor.execute {
            com.aeidolon.vaultexplorer.camera.VaultVideoRecorder.sweepOrphanedTempFiles(cacheDir)
            SecureFileWipe.sweepOrphanedFiles(cacheDir, listOf("thumb_", "export_"))
        }
    }

    override fun onPause() {
    super.onPause()
    if (systemHandlers.userWantsSecureScreen) {
        privacyCurtain.show()
    }
}

    override fun onResume() {
    super.onResume()
    systemHandlers.setBackgroundProtectionActive(false)
    if (systemHandlers.userWantsSecureScreen) {
        privacyCurtain.armPendingReveal()
    }
}

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        disguiseModeHandlers.updateActivityIdentity()
    }

    override fun startActivity(intent: Intent) {
        if (intent.action == "android.intent.action.ANNOTATE") {
            handleNativePdfEditFabTap()
            return
        }
        super.startActivity(intent)
    }

    override fun startActivityForResult(intent: Intent, requestCode: Int) {
        if (intent.action == "android.intent.action.ANNOTATE") {
            handleNativePdfEditFabTap()
            return
        }
        super.startActivityForResult(intent, requestCode)
    }

    private fun handleNativePdfEditFabTap() {
        val instance = com.aeidolon.vaultexplorer.pdf.JetpackPdfViewerPlatformView.activeInstance
        if (instance != null) {
            instance.onNativeEditFabTapped()
        } else {
            android.widget.Toast.makeText(
                this,
                getString(R.string.pdf_edit_unavailable),
                android.widget.Toast.LENGTH_SHORT,
            ).show()
        }
    }

    override fun onDestroy() {
        chooserReceiver?.let { unregisterReceiver(it) }
        usbPermissionReceiver?.let { unregisterReceiver(it) }
        usbDetachReceiver?.let { unregisterReceiver(it) }
        screenOffReceiver?.let { unregisterReceiver(it) }
        vaultCameraPlugin?.disposeAll()
        vaultCameraPlugin = null
        nativePlayerManager.release()
        com.aeidolon.vaultexplorer.pdf.PdfRendererRegistry.closeAll()
        com.aeidolon.vaultexplorer.pdf.VaultPdfSessionRegistry.revokeAll()
        vaultUnlockHandlers.onActivityDestroyed()
        splitContainerMountHandlers.onActivityDestroyed()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == com.aeidolon.vaultexplorer.camera.CAMERA_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == android.content.pm.PackageManager.PERMISSION_GRANTED }
            methodChannel?.invokeMethod("onCameraPermissionResult", mapOf("granted" to granted))
        } else if (requestCode == STORAGE_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == android.content.pm.PackageManager.PERMISSION_GRANTED }
            methodChannel?.invokeMethod("onStoragePermissionResult", mapOf("granted" to granted))
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) systemHandlers.sanitizeClipboard()
    }

    private fun resizeExecutorPools() {
        val sizes = DeviceCapabilityProfiler.executorSizesFor(DeviceCapabilityProfiler.tierFor(this))
        resizeThreadPool(ioExecutor, sizes.io)
        resizeThreadPool(imageThumbnailExecutor, sizes.imageThumbnail)
        resizeThreadPool(videoThumbnailExecutor, sizes.videoThumbnail)
        resizeThreadPool(fullResExecutor, sizes.fullRes)
    }

    private fun resizeThreadPool(executor: ThreadPoolExecutor, newSize: Int) {
        if (newSize >= executor.corePoolSize) {
            executor.maximumPoolSize = newSize
            executor.corePoolSize = newSize
        } else {
            executor.corePoolSize = newSize
            executor.maximumPoolSize = newSize
        }
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        methodChannel?.invokeMethod("onTrimMemory", mapOf("level" to level))
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        resizeExecutorPools()
        
        nativePlayerManager.setTextureRegistry(flutterEngine.renderer)

        vaultCameraPlugin = com.aeidolon.vaultexplorer.camera.VaultCameraPlugin(this, flutterEngine.dartExecutor.binaryMessenger, flutterEngine.renderer)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            com.aeidolon.vaultexplorer.htmlviewer.HTML_VIEWER_VIEW_TYPE,
            com.aeidolon.vaultexplorer.htmlviewer.HtmlViewerViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            com.aeidolon.vaultexplorer.pdf.JETPACK_PDF_VIEWER_VIEW_TYPE,
            com.aeidolon.vaultexplorer.pdf.JetpackPdfViewerViewFactory(this, flutterEngine.dartExecutor.binaryMessenger),
        )

        val playerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.aeidolon.vaultexplorer/player")
        nativePlayerManager.methodChannel = playerChannel
        playerChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val volId = call.argument<Int>("volId") ?: -1
                    val filePath = call.argument<String>("filePath") ?: ""
                    val textureId = nativePlayerManager.initialize(volId, filePath)
                    result.success(mapOf("textureId" to textureId))
                }
                "play" -> {
                    nativePlayerManager.play()
                    result.success(null)
                }
                "pause" -> {
                    nativePlayerManager.pause()
                    result.success(null)
                }
                "seekTo" -> {
                    val pos = call.argument<Number>("positionMs")?.toLong() ?: 0L
                    nativePlayerManager.seekTo(pos)
                    result.success(null)
                }
                "setSpeed" -> {
                    val speed = call.argument<Number>("speed")?.toFloat() ?: 1.0f
                    nativePlayerManager.setSpeed(speed)
                    result.success(null)
                }
                "setVolume" -> {
                    val volume = call.argument<Number>("volume")?.toFloat() ?: 1.0f
                    nativePlayerManager.setVolume(volume)
                    result.success(null)
                }
                "setLooping" -> {
                    val loop = call.argument<Boolean>("loop") ?: false
                    nativePlayerManager.setLooping(loop)
                    result.success(null)
                }
                "getAudioTracks" -> {
                    result.success(nativePlayerManager.getAudioTracks())
                }
                "getSubtitleTracks" -> {
                    result.success(nativePlayerManager.getSubtitleTracks())
                }
                "selectAudioTrack" -> {
                    val groupIdx = call.argument<Int>("groupIndex") ?: -1
                    val trackIdx = call.argument<Int>("trackIndex") ?: -1
                    nativePlayerManager.selectAudioTrack(groupIdx, trackIdx)
                    result.success(null)
                }
                "selectSubtitleTrack" -> {
                    val groupIdx = call.argument<Int>("groupIndex") ?: -1
                    val trackIdx = call.argument<Int>("trackIndex") ?: -1
                    nativePlayerManager.selectSubtitleTrack(groupIdx, trackIdx)
                    result.success(null)
                }
                "disableSubtitleTrack" -> {
                    nativePlayerManager.disableSubtitleTrack()
                    result.success(null)
                }
                "getDiagnostics" -> {
                    result.success(nativePlayerManager.getDiagnosticsMap())
                }
                "release" -> {
                    nativePlayerManager.release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val playerEventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.aeidolon.vaultexplorer/player_events")
        playerEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                nativePlayerManager.eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                nativePlayerManager.eventSink = null
            }
        })

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        UnlockProgressBridge.channel = channel
        ImportProgressBridge.channel = channel
        HiddenVolumeProtectionBridge.channel = channel
        SplitJoinProgressBridge.channel = channel
        RepairLogBridge.channel = channel
        HashProgressBridge.channel = channel

        val disguiseChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DISGUISE_CHANNEL)
        ExternalOpenBridge.channel = disguiseChannel
        disguiseChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                DisguiseChannelMethods.GET_MODE -> disguiseModeHandlers.handleGetMode(call, result)
                DisguiseChannelMethods.SET_MODE -> disguiseModeHandlers.handleSetMode(call, result)
                else -> result.notImplemented()
            }
        }

        val filter = IntentFilter(ACTION_CHOOSER)
        chooserReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == ACTION_CHOOSER) {
                    val selectedComponent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_CHOSEN_COMPONENT, ComponentName::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra<ComponentName>(Intent.EXTRA_CHOSEN_COMPONENT)
                    }
                    selectedComponent?.let {
                        val pkg = it.packageName
                        val ext = intent.getStringExtra("extension") ?: ""
                        runOnUiThread {
                            methodChannel?.invokeMethod("onAppSelected", mapOf("extension" to ext, "package" to pkg))
                        }
                    }
                }
            }
        }

        val usbFilter = IntentFilter(ACTION_USB_PERMISSION)
        usbPermissionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                usbHandlers.onPermissionBroadcast(intent)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbPermissionReceiver, usbFilter, RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(usbPermissionReceiver, usbFilter)
        }

        usbDetachReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != UsbManager.ACTION_USB_DEVICE_DETACHED) return
                val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                } ?: return
                usbHandlers.onDeviceDetached(device)
            }
        }
        val detachFilter = IntentFilter(UsbManager.ACTION_USB_DEVICE_DETACHED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbDetachReceiver, detachFilter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(usbDetachReceiver, detachFilter)
        }

        screenOffReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != Intent.ACTION_SCREEN_OFF) return
                runOnUiThread {
                    methodChannel?.invokeMethod("onScreenOff", null)
                }
            }
        }
        val screenOffFilter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenOffReceiver, screenOffFilter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(screenOffReceiver, screenOffFilter)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(chooserReceiver, filter, RECEIVER_EXPORTED)
        } else {
            registerReceiver(chooserReceiver, filter)
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                ChannelMethods.SET_SECURE_SCREEN -> systemHandlers.handleSetSecureScreen(call, result)
                ChannelMethods.SET_RECENTS_SNAPSHOT_BLOCKED -> systemHandlers.handleSetRecentsSnapshotBlocked(call, result)
                ChannelMethods.NOTIFY_RESUMED_FRAME_PAINTED -> { privacyCurtain.reveal(); result.success(true) }
                ChannelMethods.SET_SENSITIVE_CLIPBOARD_TEXT -> systemHandlers.handleSetSensitiveClipboardText(call, result)
                ChannelMethods.HAS_ALL_FILES_ACCESS -> systemHandlers.handleHasAllFilesAccess(call, result)
                ChannelMethods.REQUEST_ALL_FILES_ACCESS -> systemHandlers.handleRequestAllFilesAccess(call, result)
                ChannelMethods.LIST_USB_DEVICES -> usbHandlers.handleListUsbDevices(call, result)
                ChannelMethods.REQUEST_USB_PERMISSION -> usbHandlers.handleRequestUsbPermission(call, result)
                ChannelMethods.UNLOCK_USB_CONTAINER -> usbHandlers.handleUnlockUsbContainer(call, result)
                ChannelMethods.PICK_CONTAINER -> vaultPickerHandlers.handlePickContainer(call, result)
                ChannelMethods.PICK_CRYPTOMATOR_VAULT -> vaultPickerHandlers.handlePickCryptomatorVault(call, result)
                ChannelMethods.PICK_GOCRYPTFS_VAULT -> vaultPickerHandlers.handlePickGocryptfsVault(call, result)
                ChannelMethods.PICK_CRYFS_VAULT -> vaultPickerHandlers.handlePickCryfsVault(call, result)
                ChannelMethods.PICK_KEYFILES -> vaultPickerHandlers.handlePickKeyfiles(call, result)
                ChannelMethods.PICK_CRYPTO_FILES -> vaultPickerHandlers.handlePickCryptoFiles(call, result)
                ChannelMethods.PICK_ARCHIVE_FILE -> vaultPickerHandlers.handlePickArchiveFile(call, result)
                ChannelMethods.PICK_EXTRACT_FOLDER -> vaultPickerHandlers.handlePickExtractFolder(call, result)
                ChannelMethods.CREATE_CONTAINER -> vaultCreationHandlers.handleCreateContainer(call, result)
                ChannelMethods.CREATE_USB_CONTAINER -> usbHandlers.handleCreateUsbContainer(call, result)
                ChannelMethods.GET_USB_DEVICE_CAPACITY -> usbHandlers.handleGetUsbDeviceCapacity(call, result)
                ChannelMethods.UNLOCK_CONTAINER -> vaultUnlockHandlers.handleUnlockContainer(call, result)
                ChannelMethods.UNLOCK_SPLIT_CONTAINER -> vaultUnlockHandlers.handleUnlockContainer(call, result)
                ChannelMethods.UNLOCK_CRYPTOMATOR_VAULT -> vaultUnlockHandlers.handleUnlockCryptomatorVault(call, result)
                ChannelMethods.UNLOCK_GOCRYPTFS_VAULT -> vaultUnlockHandlers.handleUnlockGocryptfsVault(call, result)
                ChannelMethods.UNLOCK_CRYFS_VAULT -> vaultUnlockHandlers.handleUnlockCryfsVault(call, result)
                ChannelMethods.CREATE_CRYPTOMATOR_VAULT -> vaultCreationHandlers.handleCreateCryptomatorVault(call, result)
                ChannelMethods.CHANGE_CRYPTOMATOR_VAULT_PASSWORD -> vaultUnlockHandlers.handleChangeCryptomatorVaultPassword(call, result)
                ChannelMethods.CREATE_GOCRYPTFS_VAULT -> vaultCreationHandlers.handleCreateGocryptfsVault(call, result)
                ChannelMethods.CHANGE_GOCRYPTFS_VAULT_PASSWORD -> vaultUnlockHandlers.handleChangeGocryptfsVaultPassword(call, result)
                ChannelMethods.IS_GOCRYPTFS_VAULT -> vaultUnlockHandlers.handleIsGocryptfsVault(call, result)
                ChannelMethods.CREATE_CRYFS_VAULT -> vaultCreationHandlers.handleCreateCryfsVault(call, result)
                ChannelMethods.CHANGE_CRYFS_VAULT_PASSWORD -> vaultUnlockHandlers.handleChangeCryfsVaultPassword(call, result)
                ChannelMethods.IS_CRYFS_VAULT -> vaultUnlockHandlers.handleIsCryfsVault(call, result)
                ChannelMethods.FINISH_WRITE -> vaultUnlockHandlers.handleFinishWrite(call, result)
                ChannelMethods.CANCEL_UNLOCK -> vaultUnlockHandlers.handleCancelUnlock(call, result)
                ChannelMethods.CANCEL_IMPORT -> importExportHandlers.handleCancelImport(call, result)
                ChannelMethods.DELETE_IMPORT_SOURCES -> importExportHandlers.handleDeleteImportSources(call, result)
                ChannelMethods.CHANGE_CONTAINER_PASSWORD -> vaultUnlockHandlers.handleChangeContainerPassword(call, result)
                ChannelMethods.CHANGE_LUKS_CONTAINER_PASSWORD -> vaultUnlockHandlers.handleChangeLuksContainerPassword(call, result)
                ChannelMethods.DERIVE_DERIVED_KEY -> derivedKeyHandlers.handleDeriveDerivedKey(call, result)
                ChannelMethods.DOCUMENT_EXISTS -> vaultUnlockHandlers.handleDocumentExists(call, result)
                ChannelMethods.WARM_CONTAINER -> vaultUnlockHandlers.handleWarmContainer(call, result)
                ChannelMethods.STORE_DERIVED_KEY -> derivedKeyHandlers.handleStoreDerivedKey(call, result)
                ChannelMethods.LOAD_DERIVED_KEY -> derivedKeyHandlers.handleLoadDerivedKey(call, result)
                ChannelMethods.CLEAR_DERIVED_KEY -> derivedKeyHandlers.handleClearDerivedKey(call, result)
                ChannelMethods.HASH_PASSWORD -> derivedKeyHandlers.handleHashPassword(call, result)
                "hashPasswordSha256" -> derivedKeyHandlers.handleHashPasswordSha256(call, result)
                "aesGcmEncrypt" -> derivedKeyHandlers.handleAesGcmEncrypt(call, result)
                "aesGcmDecrypt" -> derivedKeyHandlers.handleAesGcmDecrypt(call, result)
                "readSecure" -> secureStorageHandlers.handleRead(call, result)
                "writeSecure" -> secureStorageHandlers.handleWrite(call, result)
                "deleteSecure" -> secureStorageHandlers.handleDelete(call, result)
                "deleteAllSecure" -> secureStorageHandlers.handleDeleteAll(call, result)
                "readAllSecure" -> secureStorageHandlers.handleReadAll(call, result)
                "containsKeySecure" -> secureStorageHandlers.handleContainsKey(call, result)
                ChannelMethods.GET_VIDEO_THUMBNAIL -> thumbnailHandlers.handleGetVideoThumbnail(call, result)
                ChannelMethods.GET_IMAGE_THUMBNAIL -> thumbnailHandlers.handleGetImageThumbnail(call, result)
                ChannelMethods.GET_IMAGE_THUMBNAIL_WITH_SIZE -> thumbnailHandlers.handleGetImageThumbnailWithSize(call, result)
                ChannelMethods.GET_VIDEO_THUMBNAIL_WITH_SIZE -> thumbnailHandlers.handleGetVideoThumbnailWithSize(call, result)
                ChannelMethods.SET_PLAYBACK_ACTIVE -> thumbnailHandlers.handleSetPlaybackActive(call, result)
                ChannelMethods.LOCK_CONTAINER -> vaultUnlockHandlers.handleLockContainer(call, result)
                ChannelMethods.UPDATE_CONTAINER_SETTINGS -> vaultUnlockHandlers.handleUpdateContainerSettings(call, result)
                ChannelMethods.DECRYPT_FILE -> fileOperationHandlers.handleDecryptFile(call, result)
                ChannelMethods.GET_FILE_SIZE -> fileOperationHandlers.handleGetFileSize(call, result)
                ChannelMethods.GET_FOLDER_SIZE -> fileOperationHandlers.handleGetFolderSize(call, result)
                ChannelMethods.READ_FILE_CHUNK -> fileOperationHandlers.handleReadFileChunk(call, result)
                ChannelMethods.GET_MEDIA_FILE_SIZE -> fileOperationHandlers.handleGetMediaFileSize(call, result)
                ChannelMethods.READ_MEDIA_FILE_CHUNK -> fileOperationHandlers.handleReadMediaFileChunk(call, result)
                ChannelMethods.LIST_DIRECTORY -> fileOperationHandlers.handleListDirectory(call, result)
                ChannelMethods.CREATE_DIRECTORY -> fileOperationHandlers.handleCreateDirectory(call, result)
                ChannelMethods.RENAME_FILE -> fileOperationHandlers.handleRenameFile(call, result)
                ChannelMethods.WRITE_BACK_FILE -> fileOperationHandlers.handleWriteBackFile(call, result)
                ChannelMethods.SET_LAST_MODIFIED_TIME -> fileOperationHandlers.handleSetLastModifiedTime(call, result)
                ChannelMethods.GET_SPACE_INFO -> fileOperationHandlers.handleGetSpaceInfo(call, result)
                ChannelMethods.DELETE_FILE -> fileOperationHandlers.handleDeleteFile(call, result)
                ChannelMethods.OPEN_WITH_APP -> systemHandlers.handleOpenWithApp(call, result)
                ChannelMethods.SET_KEEP_SCREEN_ON -> systemHandlers.handleSetKeepScreenOn(call, result)
                ChannelMethods.LAUNCH_URL -> systemHandlers.handleLaunchUrl(call, result)
                ChannelMethods.GET_APP_VERSION -> systemHandlers.handleGetAppVersion(call, result)
                ChannelMethods.GET_ANDROID_SDK_INT -> systemHandlers.handleGetAndroidSdkInt(call, result)
                ChannelMethods.IMPORT_FILE -> importExportHandlers.handleImportFile(call, result)
                ChannelMethods.EXPORT_FILES_FOLDER -> importExportHandlers.handleExportFilesFolder(call, result)
                ChannelMethods.IMPORT_FOLDER -> importExportHandlers.handleImportFolder(call, result)
                ChannelMethods.EXPORT_FILE -> importExportHandlers.handleExportFile(call, result)
                ChannelMethods.EXPORT_APP_SETTINGS_FILE -> appSettingsFileHandlers.handleExportAppSettingsFile(call, result)
                ChannelMethods.IMPORT_APP_SETTINGS_FILE -> appSettingsFileHandlers.handleImportAppSettingsFile(call, result)
                ChannelMethods.SPLIT_CONTAINER -> splitJoinHandlers.handleSplitContainer(call, result)
                ChannelMethods.JOIN_CONTAINER -> splitJoinHandlers.handleJoinContainer(call, result)
                ChannelMethods.CANCEL_SPLIT_JOIN -> splitJoinHandlers.handleCancelSplitJoin(call, result)
                ChannelMethods.UNLOCK_SPLIT_CONTAINER -> splitContainerMountHandlers.handleUnlockSplitContainer(call, result)
                ChannelMethods.ENCRYPT_SINGLE_FILE -> singleFileCryptoHandlers.handleEncryptSingleFile(call, result)
                ChannelMethods.DECRYPT_SINGLE_FILE -> singleFileCryptoHandlers.handleDecryptSingleFile(call, result)
                ChannelMethods.COMPUTE_EXTERNAL_FILE_HASH -> hashVerifierHandlers.handleComputeExternalFileHash(call, result)
                ChannelMethods.CANCEL_HASH_COMPUTE -> hashVerifierHandlers.handleCancelHashCompute(call, result)
                ChannelMethods.READ_EXTERNAL_FILE_BYTES -> hashVerifierHandlers.handleReadExternalFileBytes(call, result)
                ChannelMethods.HASH_BYTES_SHA256 -> hashVerifierHandlers.handleHashBytesSha256(call, result)
                ChannelMethods.HASH_BYTES_MD5 -> hashVerifierHandlers.handleHashBytesMd5(call, result)
                ChannelMethods.BEGIN_HASH_SESSION -> hashVerifierHandlers.handleBeginHashSession(call, result)
                ChannelMethods.UPDATE_HASH_SESSION -> hashVerifierHandlers.handleUpdateHashSession(call, result)
                ChannelMethods.FINISH_HASH_SESSION -> hashVerifierHandlers.handleFinishHashSession(call, result)
                ChannelMethods.DISCARD_HASH_SESSION -> hashVerifierHandlers.handleDiscardHashSession(call, result)
                ChannelMethods.WRITE_FILE_CHUNK -> fileOperationHandlers.handleWriteFileChunk(call, result)
                ChannelMethods.BEGIN_BATCH_WRITE -> fileOperationHandlers.handleBeginBatchWrite(call, result)
                ChannelMethods.END_BATCH_WRITE -> fileOperationHandlers.handleEndBatchWrite(call, result)
                ChannelMethods.MOUNT_CONTAINER_FOLDER -> folderDocumentProviderHandlers.handleMountContainerFolder(call, result)
                ChannelMethods.UNMOUNT_CONTAINER_FOLDER -> folderDocumentProviderHandlers.handleUnmountContainerFolder(call, result)
                ChannelMethods.GET_MOUNTED_CONTAINER_FOLDERS -> folderDocumentProviderHandlers.handleGetMountedContainerFolders(call, result)
                ChannelMethods.GET_DEVICE_CAPABILITY_PROFILE -> DeviceCapabilityProfiler.handleGetDeviceCapabilityProfile(this, call, result)
                ChannelMethods.GET_AVIF_INFO -> derivedKeyHandlers.handleGetAvifInfo(call, result)
                ChannelMethods.DECODE_AVIF_FRAME -> derivedKeyHandlers.handleDecodeAvifFrame(call, result)
                ChannelMethods.DECODE_AVIF -> derivedKeyHandlers.handleDecodeAvif(call, result)
                ChannelMethods.DIAGNOSE_UNMOUNTED_CONTAINER_FILE -> repairHandlers.handleDiagnoseUnmountedContainerFile(call, result)
                ChannelMethods.DIAGNOSE_MOUNTED_VOLUME_FILESYSTEM -> repairHandlers.handleDiagnoseMountedVolumeFilesystem(call, result)
                ChannelMethods.RESTORE_BACKUP_HEADER_UNMOUNTED -> repairHandlers.handleRestoreBackupHeaderUnmounted(call, result)
                ChannelMethods.RUN_MOUNTED_VOLUME_FILESYSTEM_CHECK -> repairHandlers.handleRunMountedVolumeFilesystemCheck(call, result)
                ChannelMethods.PICK_FOLDER_VAULT_FOR_REPAIR -> vaultPickerHandlers.handlePickFolderVaultForRepair(call, result)
                ChannelMethods.CHECK_FOLDER_VAULT -> repairHandlers.handleCheckFolderVault(call, result)
                ChannelMethods.OPEN_PDF -> pdfViewerHandlers.handleOpenPdf(call, result)
                ChannelMethods.GET_PDF_PAGE_SIZE -> pdfViewerHandlers.handleGetPdfPageSize(call, result)
                ChannelMethods.RENDER_PDF_PAGE -> pdfViewerHandlers.handleRenderPdfPage(call, result)
                ChannelMethods.CLOSE_PDF -> pdfViewerHandlers.handleClosePdf(call, result)
                ChannelMethods.IS_JETPACK_PDF_VIEWER_SUPPORTED -> pdfViewerHandlers.handleIsJetpackPdfViewerSupported(result)
                ChannelMethods.REGISTER_JETPACK_PDF_SESSION -> pdfViewerHandlers.handleRegisterJetpackPdfSession(call, result)
                ChannelMethods.REVOKE_JETPACK_PDF_SESSION -> pdfViewerHandlers.handleRevokeJetpackPdfSession(call, result)
                ChannelMethods.PRINT_PDF -> pdfViewerHandlers.handlePrintPdf(call, result)
                else -> result.notImplemented()
            }
        }
    }
}