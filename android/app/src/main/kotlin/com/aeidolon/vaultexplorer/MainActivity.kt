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
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor

private object ChannelMethods {
    const val PICK_CONTAINER            = "pickContainer"
    const val PICK_KEYFILES             = "pickKeyfiles"
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
    const val SET_SECURE_SCREEN         = "setSecureScreen"
    const val UPDATE_CONTAINER_SETTINGS = "updateContainerSettings"
    const val LIST_USB_DEVICES          = "listUsbDevices"
    const val REQUEST_USB_PERMISSION    = "requestUsbPermission"
    const val UNLOCK_USB_CONTAINER      = "unlockUsbContainer"
    const val DOCUMENT_EXISTS           = "documentExists"
    const val WARM_CONTAINER            = "warmContainer"
    const val CANCEL_UNLOCK             = "cancelUnlock"
    const val CHANGE_CONTAINER_PASSWORD = "changeContainerPassword"
    const val SET_LAST_MODIFIED_TIME    = "setLastModifiedTime"
    const val PICK_CRYPTOMATOR_VAULT    = "pickCryptomatorVault"
    const val UNLOCK_CRYPTOMATOR_VAULT  = "unlockCryptomatorVault"
    const val CREATE_CRYPTOMATOR_VAULT  = "createCryptomatorVault"
    const val PICK_GOCRYPTFS_VAULT      = "pickGocryptfsVault"
    const val UNLOCK_GOCRYPTFS_VAULT    = "unlockGocryptfsVault"
    const val CREATE_GOCRYPTFS_VAULT    = "createGocryptfsVault"
    const val FINISH_WRITE_IF_CRYPTOMATOR = "finishWriteIfCryptomator"
    const val IS_GOCRYPTFS_VAULT        = "isGocryptfsVault"
    const val PICK_CRYFS_VAULT          = "pickCryfsVault"
    const val UNLOCK_CRYFS_VAULT        = "unlockCryfsVault"
    const val CREATE_CRYFS_VAULT        = "createCryfsVault"
    const val IS_CRYFS_VAULT            = "isCryfsVault"
    const val MOUNT_CONTAINER_FOLDER    = "mountContainerFolder"
    const val UNMOUNT_CONTAINER_FOLDER  = "unmountContainerFolder"
    const val GET_MOUNTED_CONTAINER_FOLDERS = "getMountedContainerFolders"
    const val GET_DEVICE_CAPABILITY_PROFILE = "getDeviceCapabilityProfile"
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
    private var usbDetachReceiver: BroadcastReceiver? = null
    private var screenOffReceiver: BroadcastReceiver? = null
    private var vaultCameraPlugin: com.aeidolon.vaultexplorer.camera.VaultCameraPlugin? = null
    private val pendingResult = PendingActivityResult()
    private val nativeOps = NativeOpSupport(this, ioExecutor)
    private val derivedKeyHandlers = DerivedKeyHandlers(this, ioExecutor, nativeOps)
    private val usbHandlers = UsbContainerHandlers(this, ACTION_USB_PERMISSION, ioExecutor, nativeOps, derivedKeyHandlers)
    private val vaultPickerHandlers = VaultPickerHandlers(this, pendingResult, ioExecutor)
    private val vaultCreationHandlers = VaultCreationHandlers(this, pendingResult, ioExecutor, nativeOps)
    private val vaultUnlockHandlers = VaultUnlockHandlers(this, ioExecutor, nativeOps, derivedKeyHandlers)
    private val thumbnailHandlers = ThumbnailHandlers(this, imageThumbnailExecutor, videoThumbnailExecutor, nativeOps)
    private val importExportHandlers = ImportExportHandlers(this, pendingResult, ioExecutor, nativeOps)
    private val fileOperationHandlers = FileOperationHandlers(nativeOps, fullResExecutor)
    private val systemHandlers = SystemPermissionHandlers(this)
    private val folderDocumentProviderHandlers = FolderDocumentProviderHandlers(this)
    private val disguiseModeHandlers = DisguiseModeHandlers(this, pendingResult, ioExecutor)

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        disguiseModeHandlers.updateActivityIdentity()
        disguiseModeHandlers.handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        disguiseModeHandlers.updateActivityIdentity()
        disguiseModeHandlers.handleIncomingIntent(intent)
    }

    override fun onDestroy() {
        chooserReceiver?.let { unregisterReceiver(it) }
        usbPermissionReceiver?.let { unregisterReceiver(it) }
        usbDetachReceiver?.let { unregisterReceiver(it) }
        screenOffReceiver?.let { unregisterReceiver(it) }
        vaultCameraPlugin?.disposeAll()
        vaultCameraPlugin = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == com.aeidolon.vaultexplorer.camera.CAMERA_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == android.content.pm.PackageManager.PERMISSION_GRANTED }
            methodChannel?.invokeMethod("onCameraPermissionResult", mapOf("granted" to granted))
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
        vaultCameraPlugin = com.aeidolon.vaultexplorer.camera.VaultCameraPlugin(this, flutterEngine.dartExecutor.binaryMessenger, flutterEngine.renderer)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            com.aeidolon.vaultexplorer.htmlviewer.HTML_VIEWER_VIEW_TYPE,
            com.aeidolon.vaultexplorer.htmlviewer.HtmlViewerViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        UnlockProgressBridge.channel = channel
        ImportProgressBridge.channel = channel

        val disguiseChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DISGUISE_CHANNEL)
        ExternalOpenBridge.channel = disguiseChannel
        disguiseChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                DisguiseChannelMethods.GET_MODE -> disguiseModeHandlers.handleGetMode(call, result)
                DisguiseChannelMethods.SET_MODE -> disguiseModeHandlers.handleSetMode(call, result)
                DisguiseChannelMethods.PICK_LOCAL_PDF_FILE -> disguiseModeHandlers.handlePickLocalPdfFile(call, result)
                DisguiseChannelMethods.CONSUME_PENDING_OPEN_REQUEST -> disguiseModeHandlers.handleConsumePendingOpenRequest(call, result)
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
                ChannelMethods.CREATE_CONTAINER -> vaultCreationHandlers.handleCreateContainer(call, result)
                ChannelMethods.CREATE_USB_CONTAINER -> usbHandlers.handleCreateUsbContainer(call, result)
                ChannelMethods.GET_USB_DEVICE_CAPACITY -> usbHandlers.handleGetUsbDeviceCapacity(call, result)
                ChannelMethods.UNLOCK_CONTAINER -> vaultUnlockHandlers.handleUnlockContainer(call, result)
                ChannelMethods.UNLOCK_CRYPTOMATOR_VAULT -> vaultUnlockHandlers.handleUnlockCryptomatorVault(call, result)
                ChannelMethods.UNLOCK_GOCRYPTFS_VAULT -> vaultUnlockHandlers.handleUnlockGocryptfsVault(call, result)
                ChannelMethods.UNLOCK_CRYFS_VAULT -> vaultUnlockHandlers.handleUnlockCryfsVault(call, result)
                ChannelMethods.CREATE_CRYPTOMATOR_VAULT -> vaultCreationHandlers.handleCreateCryptomatorVault(call, result)
                ChannelMethods.CREATE_GOCRYPTFS_VAULT -> vaultCreationHandlers.handleCreateGocryptfsVault(call, result)
                ChannelMethods.IS_GOCRYPTFS_VAULT -> vaultUnlockHandlers.handleIsGocryptfsVault(call, result)
                ChannelMethods.CREATE_CRYFS_VAULT -> vaultCreationHandlers.handleCreateCryfsVault(call, result)
                ChannelMethods.IS_CRYFS_VAULT -> vaultUnlockHandlers.handleIsCryfsVault(call, result)
                ChannelMethods.FINISH_WRITE_IF_CRYPTOMATOR -> vaultUnlockHandlers.handleFinishWriteIfCryptomator(call, result)
                ChannelMethods.CANCEL_UNLOCK -> vaultUnlockHandlers.handleCancelUnlock(call, result)
                ChannelMethods.CANCEL_IMPORT -> importExportHandlers.handleCancelImport(call, result)
                ChannelMethods.DELETE_IMPORT_SOURCES -> importExportHandlers.handleDeleteImportSources(call, result)
                ChannelMethods.CHANGE_CONTAINER_PASSWORD -> vaultUnlockHandlers.handleChangeContainerPassword(call, result)
                ChannelMethods.DERIVE_DERIVED_KEY -> derivedKeyHandlers.handleDeriveDerivedKey(call, result)
                ChannelMethods.DOCUMENT_EXISTS -> vaultUnlockHandlers.handleDocumentExists(call, result)
                ChannelMethods.WARM_CONTAINER -> vaultUnlockHandlers.handleWarmContainer(call, result)
                ChannelMethods.STORE_DERIVED_KEY -> derivedKeyHandlers.handleStoreDerivedKey(call, result)
                ChannelMethods.LOAD_DERIVED_KEY -> derivedKeyHandlers.handleLoadDerivedKey(call, result)
                ChannelMethods.CLEAR_DERIVED_KEY -> derivedKeyHandlers.handleClearDerivedKey(call, result)
                ChannelMethods.HASH_PASSWORD -> derivedKeyHandlers.handleHashPassword(call, result)
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
                ChannelMethods.IMPORT_FILE -> importExportHandlers.handleImportFile(call, result)
                ChannelMethods.EXPORT_FILES_FOLDER -> importExportHandlers.handleExportFilesFolder(call, result)
                ChannelMethods.IMPORT_FOLDER -> importExportHandlers.handleImportFolder(call, result)
                ChannelMethods.EXPORT_FILE -> importExportHandlers.handleExportFile(call, result)
                ChannelMethods.WRITE_FILE_CHUNK -> fileOperationHandlers.handleWriteFileChunk(call, result)
                ChannelMethods.MOUNT_CONTAINER_FOLDER -> folderDocumentProviderHandlers.handleMountContainerFolder(call, result)
                ChannelMethods.UNMOUNT_CONTAINER_FOLDER -> folderDocumentProviderHandlers.handleUnmountContainerFolder(call, result)
                ChannelMethods.GET_MOUNTED_CONTAINER_FOLDERS -> folderDocumentProviderHandlers.handleGetMountedContainerFolders(call, result)
                ChannelMethods.GET_DEVICE_CAPABILITY_PROFILE -> DeviceCapabilityProfiler.handleGetDeviceCapabilityProfile(this, call, result)
                else -> result.notImplemented()
            }
        }
    }
}