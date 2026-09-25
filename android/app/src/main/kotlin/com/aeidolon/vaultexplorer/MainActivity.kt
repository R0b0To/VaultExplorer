package com.aeidolon.vaultexplorer

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.media.AudioManager
import android.os.Build
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import com.aeidolon.vaultexplorer.saf.SafDocumentOps
import com.aeidolon.vaultexplorer.saf.VaultPathUtils
import androidx.documentfile.provider.DocumentFile
import android.net.Uri
import com.aeidolon.vaultexplorer.bridge.CopyProgressBridge
import com.aeidolon.vaultexplorer.bridge.ExportProgressBridge
import com.aeidolon.vaultexplorer.bridge.ExternalOpenBridge
import com.aeidolon.vaultexplorer.bridge.HashProgressBridge
import com.aeidolon.vaultexplorer.bridge.HiddenVolumeProtectionBridge
import com.aeidolon.vaultexplorer.bridge.ImportProgressBridge
import com.aeidolon.vaultexplorer.bridge.IncomingShareBridge
import com.aeidolon.vaultexplorer.bridge.LocalIncomingShareBridge
import com.aeidolon.vaultexplorer.bridge.RepairLogBridge
import com.aeidolon.vaultexplorer.bridge.SplitJoinProgressBridge
import com.aeidolon.vaultexplorer.bridge.UnlockProgressBridge
import com.aeidolon.vaultexplorer.bridge.VaultAutomationUnlockedBridge
import com.aeidolon.vaultexplorer.bridge.VaultCameraStopRequestedBridge
import com.aeidolon.vaultexplorer.bridge.VaultForceLockedBridge
import com.aeidolon.vaultexplorer.container.VideoThumbnailCoordinator
import com.aeidolon.vaultexplorer.service.VaultCameraRecordingService
import com.aeidolon.vaultexplorer.handlers.AppSettingsFileHandlers
import com.aeidolon.vaultexplorer.handlers.BackgroundServiceHandlers
import com.aeidolon.vaultexplorer.handlers.CameraRecordingServiceHandlers
import com.aeidolon.vaultexplorer.handlers.DerivedKeyHandlers
import com.aeidolon.vaultexplorer.handlers.DisguiseModeHandlers
import com.aeidolon.vaultexplorer.handlers.FileOperationHandlers
import com.aeidolon.vaultexplorer.handlers.FolderDocumentProviderHandlers
import com.aeidolon.vaultexplorer.handlers.HashVerifierHandlers
import com.aeidolon.vaultexplorer.handlers.ImportExportHandlers
import com.aeidolon.vaultexplorer.handlers.LogExportHandlers
import com.aeidolon.vaultexplorer.handlers.RepairHandlers
import com.aeidolon.vaultexplorer.handlers.HeaderBackupHandlers
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
import com.aeidolon.vaultexplorer.handlers.LocalFileHandlers
import com.aeidolon.vaultexplorer.handlers.ShareIntentHandlers
import com.aeidolon.vaultexplorer.handlers.PanicSettingsHandlers
import com.aeidolon.vaultexplorer.handlers.QuickCaptureSettingsHandlers
import com.aeidolon.vaultexplorer.bridge.QuickCaptureBridge
import com.aeidolon.vaultexplorer.quickcapture.QuickCaptureShortcuts
import com.aeidolon.vaultexplorer.panic.PanicHooks
import com.aeidolon.vaultexplorer.panic.PanicManager
import com.aeidolon.vaultexplorer.automation.AutomationSettingsHandlers
import com.aeidolon.vaultexplorer.handlers.DisguiseChannelMethods
import com.aeidolon.vaultexplorer.handlers.STORAGE_PERMISSION_REQUEST_CODE
import com.aeidolon.vaultexplorer.handlers.NOTIFICATION_PERMISSION_REQUEST_CODE

private object ChannelMethods {
    const val GET_LOCAL_FILE_URI        = "getLocalFileUri"
    const val PICK_CONTAINER            = "pickContainer"
    const val PICK_KEYFILES             = "pickKeyfiles"
    const val PICK_CRYPTO_FILES         = "pickCryptoFiles"
    const val PICK_ARCHIVE_FILE         = "pickArchiveFile"
    const val PICK_EXTRACT_FOLDER       = "pickExtractFolder"
    const val CREATE_CONTAINER          = "createContainer"
    const val CREATE_USB_CONTAINER      = "createUsbContainer"
    const val GET_USB_DEVICE_CAPACITY   = "getUsbDeviceCapacity"
    const val UNLOCK_CONTAINER          = "unlockContainer"
    const val DETECTS_AS_PLAIN_DISK_IMAGE = "detectsAsPlainDiskImage"
    const val PROBE_CONTAINER_FORMAT    = "probeContainerFormat"
    const val LOCK_CONTAINER            = "lockContainer"
    const val SYNC_BACKGROUND_SERVICE   = "syncBackgroundService"
    const val UPDATE_BACKGROUND_SERVICE_PROGRESS = "updateBackgroundServiceProgress"
    const val START_BACKGROUND_RECORDING = "startBackgroundRecording"
    const val STOP_BACKGROUND_RECORDING = "stopBackgroundRecording"
    const val DECRYPT_FILE              = "decryptFile"
    const val EXPORT_FILE               = "exportFileToStorage"
    const val EXPORT_FILES_FOLDER       = "exportFilesToFolder"
    const val IMPORT_FILE               = "importFile"
    const val IMPORT_FOLDER             = "importFolder"
    const val PICK_IMPORT_FILES         = "pickImportFiles"
    const val PICK_IMPORT_FOLDER        = "pickImportFolder"
    const val CANCEL_PICKED_IMPORT      = "cancelPickedImport"
    const val EXPORT_APP_SETTINGS_FILE  = "exportAppSettingsFile"
    const val IMPORT_APP_SETTINGS_FILE  = "importAppSettingsFile"
    const val EXPORT_LOG_FILE           = "exportLogFile"
    const val CANCEL_IMPORT             = "cancelImport"
    const val CANCEL_EXPORT             = "cancelExport"
    const val DELETE_IMPORT_SOURCES     = "deleteImportSources"
    const val GET_FILE_SIZE             = "getFileSize"
    const val READ_FILE_CHUNK           = "readFileChunk"
    const val GET_MEDIA_FILE_SIZE       = "getMediaFileSize"
    const val HAS_ALL_FILES_ACCESS      = "hasAllFilesAccess"
    const val REQUEST_ALL_FILES_ACCESS  = "requestAllFilesAccess"
    const val HAS_OVERLAY_PERMISSION    = "hasOverlayPermission"
    const val REQUEST_OVERLAY_PERMISSION = "requestOverlayPermission"
    const val REQUEST_NOTIFICATION_PERMISSION = "requestNotificationPermission"
    const val READ_MEDIA_FILE_CHUNK     = "readMediaFileChunk"
    const val WRITE_BACK_FILE           = "writeBackFile"
    const val GET_SPACE_INFO            = "getSpaceInfo"
    const val GET_VAULT_INFO            = "getVaultInfo"
    const val LIST_DIRECTORY            = "listDirectory"
    const val CREATE_DIRECTORY          = "createDirectory"
    const val RENAME_FILE               = "renameFile"
    const val COPY_FILE                 = "copyFile"
    const val CANCEL_COPY               = "cancelCopy"
    const val CLEAR_COPY_STATE          = "clearCopyState"
    const val DELETE_FILE               = "deleteFile"
    const val OPEN_WITH_APP             = "openWithApp"
    const val INSTALL_APK               = "installApk"
    const val SHARE_FILE                = "shareFile"
    const val GET_VIDEO_THUMBNAIL       = "getVideoThumbnail"
    const val GET_IMAGE_THUMBNAIL       = "getImageThumbnail"
    const val GET_IMAGE_THUMBNAIL_WITH_SIZE = "getImageThumbnailWithSize"
    const val GET_VIDEO_THUMBNAIL_WITH_SIZE = "getVideoThumbnailWithSize"
    const val GET_APK_ICON              = "getApkIcon"
    const val ENCODE_IMAGE              = "encodeImage"
    const val SET_PLAYBACK_ACTIVE       = "setPlaybackActive"
    const val GET_FOLDER_SIZE           = "getFolderSize"
    const val HASH_PASSWORD             = "hashPassword"
    const val HASH_PASSWORD_SHA256      = "hashPasswordSha256"
    const val AES_GCM_ENCRYPT           = "aesGcmEncrypt"
    const val AES_GCM_DECRYPT           = "aesGcmDecrypt"
    const val READ_SECURE               = "readSecure"
    const val WRITE_SECURE              = "writeSecure"
    const val DELETE_SECURE             = "deleteSecure"
    const val GET_AUTOMATION_TOKEN            = "getAutomationToken"
    const val REGENERATE_AUTOMATION_TOKEN     = "regenerateAutomationToken"
    const val GET_AUTOMATION_VAULT_CONFIG     = "getAutomationVaultConfig"
    const val SET_AUTOMATION_TIER             = "setAutomationTier"
    const val SET_AUTOMATION_PASSWORD         = "setAutomationPassword"
    const val GET_AUTOMATION_KEYFILES         = "getAutomationKeyfiles"
    const val SET_AUTOMATION_KEYFILES         = "setAutomationKeyfiles"
    const val GET_AUTOMATION_PIM              = "getAutomationPim"
    const val SET_AUTOMATION_PIM              = "setAutomationPim"
    const val SET_AUTOMATION_CAPTURE_ENABLED  = "setAutomationCaptureEnabled"
    const val DELETE_ALL_SECURE         = "deleteAllSecure"
    const val READ_ALL_SECURE           = "readAllSecure"
    const val CONTAINS_KEY_SECURE       = "containsKeySecure"
    const val DERIVE_DERIVED_KEY        = "deriveDerivedKey"
    const val STORE_DERIVED_KEY         = "storeDerivedKey"
    const val LOAD_DERIVED_KEY          = "loadDerivedKey"
    const val CLEAR_DERIVED_KEY         = "clearDerivedKey"
    const val SET_DERIVED_KEY_EXPIRY    = "setDerivedKeyExpiry"
    const val GET_DERIVED_KEY_EXPIRY    = "getDerivedKeyExpiry"
    const val PURGE_EXPIRED_DERIVED_KEYS = "purgeExpiredDerivedKeys"
    const val WRITE_FILE_CHUNK          = "writeFileChunk"
    const val BEGIN_BATCH_WRITE         = "beginBatchWrite"
    const val END_BATCH_WRITE           = "endBatchWrite"
    const val BEGIN_BATCH_DELETE        = "beginBatchDelete"
    const val END_BATCH_DELETE          = "endBatchDelete"
    const val SET_SECURE_SCREEN         = "setSecureScreen"
    const val SET_DEBUG_LOGGING         = "setDebugLogging"
    const val SET_RECENTS_SNAPSHOT_BLOCKED = "setRecentsSnapshotBlocked"
    const val NOTIFY_RESUMED_FRAME_PAINTED = "notifyResumedFramePainted"
    const val SET_SENSITIVE_CLIPBOARD_TEXT = "setSensitiveClipboardText"
    const val CLEAR_SENSITIVE_CLIPBOARD_TEXT = "clearSensitiveClipboardText"
    const val UPDATE_CONTAINER_SETTINGS = "updateContainerSettings"
    const val GET_ACTIVE_CONTAINER_SESSIONS = "getActiveContainerSessions"
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
    const val CANCEL_HASH_COMPUTE       = "cancelHashCompute"
    const val READ_EXTERNAL_FILE_BYTES  = "readExternalFileBytes"
    const val WRITE_EXTERNAL_FILE_BYTES = "writeExternalFileBytes"
    const val HASH_BYTES_SHA256         = "hashBytesSha256"
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
    const val REPAIR_FOLDER_VAULT = "repairFolderVault"
    const val EXPORT_CONTAINER_HEADER = "exportContainerHeader"
    const val RESTORE_CONTAINER_HEADER_REGION = "restoreContainerHeaderRegion"
    const val RESOLVE_FOLDER_VAULT_CONFIG_FILE = "resolveFolderVaultConfigFile"
    const val RESTORE_FOLDER_VAULT_CONFIG = "restoreFolderVaultConfig"
    const val OPEN_LOCAL_FILE_WITH_APP = "openLocalFileWithApp"
    const val SHARE_LOCAL_FILE = "shareLocalFile"
    const val ARCHIVE_SCAN_VAULT = "archiveScanVault"
    const val ARCHIVE_EXTRACT_VAULT_ENTRY = "archiveExtractVaultEntry"
    const val ARCHIVE_EXTRACT_VAULT_ALL = "archiveExtractVaultAll"
    const val ARCHIVE_SCAN_LOCAL = "archiveScanLocal"
    const val ARCHIVE_EXTRACT_LOCAL_ENTRY = "archiveExtractLocalEntry"
    const val ARCHIVE_CREATE = "archiveCreate"
    const val PROFILE_CARRIERS = "profileCarriers"
    const val CREATE_COMPOSITE_CONTAINER = "createCompositeContainer"
    const val UNLOCK_COMPOSITE_CONTAINER = "unlockCompositeContainer"

    // Android Share Sheet integration (see ShareIntentHandlers).
    const val SET_SHARE_TARGET_ENABLED = "setShareTargetEnabled"
    const val IS_SHARE_TARGET_ENABLED = "isShareTargetEnabled"
    const val CHECK_PENDING_SHARE_REQUEST = "checkPendingShareRequest"
    const val CANCEL_PENDING_SHARE_REQUEST = "cancelPendingShareRequest"
    const val RETURN_TO_SHARING_APP = "returnToSharingApp"
    const val PREPARE_SHARE_IMPORT = "prepareShareImport"

    // Quick Capture (Quick Settings tile / pinned shortcut) integration
    const val CHECK_PENDING_QUICK_CAPTURE_REQUEST = "checkPendingQuickCaptureRequest"
    const val GET_QUICK_CAPTURE_SETTINGS = "getQuickCaptureSettings"
    const val SET_QUICK_CAPTURE_TILE_ENABLED = "setQuickCaptureTileEnabled"
    const val REQUEST_PIN_QUICK_CAPTURE_SHORTCUT = "requestPinQuickCaptureShortcut"

    // Panic, PanicKit & Emergency Tile integration
    const val GET_PANIC_SETTINGS = "getPanicSettings"
    const val SET_PANIC_TIER = "setPanicTier"
    const val SET_QUICK_TILE_ENABLED = "setQuickTileEnabled"
    const val GET_PANIC_KIT_STATUS = "getPanicKitStatus"
    const val SET_PANIC_KIT_ENABLED = "setPanicKitEnabled"
    const val SET_PANIC_KIT_PAIRING_ENFORCEMENT = "setPanicKitPairingEnforcement"
    const val UNPAIR_PANIC_KIT = "unpairPanicKit"
    const val TRIGGER_PANIC = "triggerPanic"
    const val GET_PANIC_BOOT_TRIGGER_SETTINGS = "getPanicBootTriggerSettings"
    const val SET_PANIC_BOOT_TRIGGER_TIER = "setPanicBootTriggerTier"
   const val SET_PANIC_BOOT_TRIGGER_ARMED = "setPanicBootTriggerArmed"

    // Document Providers & SAF Storage
    const val SAF_LIST_DIRECTORY        = "safListDirectory"
    const val SAF_CHECK_TREE_ACCESS     = "safCheckTreeAccess"
    const val SAF_GET_FILE_SIZE         = "safGetFileSize"
    const val SAF_READ_FILE_CHUNK       = "safReadFileChunk"
    const val SAF_WRITE_FILE_CHUNK      = "safWriteFileChunk"
    const val SAF_CREATE_FILE           = "safCreateFile"
    const val SAF_CREATE_DIRECTORY      = "safCreateDirectory"
    const val SAF_RENAME_FILE           = "safRenameFile"
    const val SAF_DELETE_FILE           = "safDeleteFile"
    const val SAF_GET_SPACE_INFO        = "safGetSpaceInfo"
    const val SAF_GET_THUMBNAIL         = "safGetThumbnail"
    const val SAF_OPEN_WITH_APP         = "safOpenWithApp"
    const val SAF_SHARE_FILES           = "safShareFiles"
    const val SAF_GET_DOCUMENT_URI      = "safGetDocumentUri"
    const val SAF_COPY_FILE             = "safCopyFile"
    const val GET_STORAGE_VOLUMES       = "getStorageVolumes"
}

open class MainActivity : FlutterFragmentActivity() {
    companion object {
        @Volatile var activeMainActivity: MainActivity? = null
    }

    protected val CHANNEL = "com.aeidolon.vaultexplorer/engine"
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
    private val imageThumbnailExecutor get() = VideoThumbnailCoordinator.imageExecutor
    private val videoThumbnailExecutor get() = VideoThumbnailCoordinator.videoExecutor
    private val fullResExecutor = Executors.newFixedThreadPool(2) as ThreadPoolExecutor
    private val pdfExecutor = Executors.newFixedThreadPool(2) as ThreadPoolExecutor
    private var usbDetachReceiver: BroadcastReceiver? = null
    private var screenOffReceiver: BroadcastReceiver? = null
    private var vaultCameraPlugin: com.aeidolon.vaultexplorer.camera.VaultCameraPlugin? = null
    private var quickCaptureScratchpadPlugin: com.aeidolon.vaultexplorer.camera.QuickCaptureScratchpadPlugin? = null
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
    private val logExportHandlers = LogExportHandlers(this, pendingResult, ioExecutor)
    private val splitJoinHandlers = SplitJoinHandlers(this, ioExecutor)
    private val singleFileCryptoHandlers = SingleFileCryptoHandlers(this, ioExecutor, nativeOps)
    private val hashVerifierHandlers = HashVerifierHandlers(this, ioExecutor)
    private val splitContainerMountHandlers = SplitContainerMountHandlers(this, ioExecutor, nativeOps, vaultUnlockHandlers)
    private val fileOperationHandlers = FileOperationHandlers(nativeOps, fullResExecutor)
    private val systemHandlers = SystemPermissionHandlers(this)
    private val localFileHandlers = LocalFileHandlers(this, ioExecutor)
    private val shareIntentHandlers = ShareIntentHandlers(this, ioExecutor)
    private val backgroundServiceHandlers = BackgroundServiceHandlers(this)
    private val cameraRecordingServiceHandlers = CameraRecordingServiceHandlers(this)
    private val folderDocumentProviderHandlers = FolderDocumentProviderHandlers(this)
    private val disguiseModeHandlers = DisguiseModeHandlers(this)
    private val secureStorageHandlers = SecureStorageHandlers(this)
    private val automationSettingsHandlers = AutomationSettingsHandlers(this)
    private val repairHandlers = RepairHandlers(this, ioExecutor)
    private val headerBackupHandlers = HeaderBackupHandlers(this, ioExecutor, nativeOps)
    private val pdfViewerHandlers = com.aeidolon.vaultexplorer.pdf.PdfViewerHandlers(this, pdfExecutor)
    private val archiveHandlers = com.aeidolon.vaultexplorer.handlers.ArchiveHandlers(this, ioExecutor, nativeOps)
    private val nativePlayerManager by lazy { com.aeidolon.vaultexplorer.engine.NativePlayerManager(this) }
    private val compositeHandlers = com.aeidolon.vaultexplorer.handlers.CompositeContainerHandlers(this, ioExecutor, nativeOps)
     private val panicSettingsHandlers = PanicSettingsHandlers(this, ioExecutor)
    private val quickCaptureSettingsHandlers = QuickCaptureSettingsHandlers(this)
    internal val safStorageManager by lazy { com.aeidolon.vaultexplorer.saf.SafStorageManager(this) }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        setTheme(R.style.NormalTheme)
        super.onCreate(savedInstanceState)
        disguiseModeHandlers.updateActivityIdentity()
        if (this is VaultShareActivity) {
            shareIntentHandlers.handleIncomingIntent(intent)
        }
        privacyCurtain.install()
        ioExecutor.execute {
            com.aeidolon.vaultexplorer.camera.VaultVideoRecorder.sweepOrphanedTempFiles(cacheDir)
            com.aeidolon.vaultexplorer.camera.QuickCaptureScratchpadPlugin.sweepOrphanedScratchpads(applicationContext)
            SecureFileWipe.sweepOrphanedFiles(cacheDir, listOf("thumb_", "export_"))
            QuickCaptureShortcuts.refreshDynamicShortcut(applicationContext)
        }

        // Phase 4: let a panic trigger arriving with no Activity currently
        // foregrounded (PanicKit broadcast, Quick Settings tile, headless
        // automation) still finish Tier 1's finishForegroundActivity() step
        // against *this* Activity -- see PanicManager.registerActivity's
        // doc comment for why it's a weak reference the object never keeps
        // alive on its own.
       if (this !is VaultShareActivity) {
            activeMainActivity = this
            PanicManager.registerActivity(this)
        }
        PanicManager.hooks = object : PanicHooks {
            // Posted via runOnUiThread rather than assumed-already-main:
            // execute() itself, and therefore every PanicHooks callback,
            // can run on whichever background thread the trigger arrived
            // on (a BroadcastReceiver's goAsync() executor, a TileService
            // click's own executor, or the MethodChannel handler's
            // ioExecutor below) -- and MethodChannel.invokeMethod must be
            // called from the platform thread.
            override fun onAfterSessionPurge(context: Context) {
                runOnUiThread { methodChannel?.invokeMethod("onPanicSessionPurged", null) }
            }

            override fun onAfterCredentialPurge(context: Context) {
                runOnUiThread { methodChannel?.invokeMethod("onPanicCredentialsPurged", null) }
            }
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
        if (this is VaultShareActivity) {
            shareIntentHandlers.handleIncomingIntent(intent)
        }
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
        quickCaptureScratchpadPlugin?.dispose()
        quickCaptureScratchpadPlugin = null
        nativePlayerManager.release()

         if (this !is VaultShareActivity) {
            if (activeMainActivity === this) activeMainActivity = null
            com.aeidolon.vaultexplorer.pdf.PdfRendererRegistry.closeAll()
            com.aeidolon.vaultexplorer.pdf.VaultPdfSessionRegistry.revokeAll()
            PanicManager.unregisterActivity(this)
            PanicManager.hooks = null
        }

        vaultUnlockHandlers.onActivityDestroyed()
        splitContainerMountHandlers.onActivityDestroyed()
        usbHandlers.onActivityDestroyed()
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
        } else if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == android.content.pm.PackageManager.PERMISSION_GRANTED }
            methodChannel?.invokeMethod("onNotificationPermissionResult", mapOf("granted" to granted))
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
    
   private fun resolveSafDocument(treeUriStr: String, relativePath: String): DocumentFile? {
        val treeUri = Uri.parse(treeUriStr)
        var doc: DocumentFile? = DocumentFile.fromTreeUri(this, treeUri)
        if (doc == null) {
            VeLog.w("MainActivity") { "resolveSafDocument: DocumentFile.fromTreeUri returned null for $treeUriStr" }
            return null
        }
        val clean = relativePath.trim().trim('/')
        if (clean.isEmpty()) return doc

        for (segment in clean.split('/')) {
            if (segment.isEmpty()) continue
            val current = doc ?: return null
            val child = current.findFile(segment)
            if (child == null) {
                val currentUri = current.uri
                VeLog.w("MainActivity") { "resolveSafDocument: child '$segment' not found under $currentUri" }
                return null
            }
            doc = child
        }
        return doc
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        methodChannel?.invokeMethod("onTrimMemory", mapOf("level" to level))
    }

    /**
     * [registerReceiver] wrapper that supplies the SDK 33+ export flag where
     * it's required and falls back to the flag-less overload below it.
     * Pulled out because the four receivers registered in
     * [configureFlutterEngine] (chooser, USB permission, USB detach,
     * screen-off) had each grown an identical SDK_INT branch independently;
     * one of the four (chooser) was also missing the
     * `@Suppress("UnspecifiedRegisterReceiverFlag")` the other three carried
     * on their pre-Tiramisu path, which this fixes as a side effect.
     */
    private fun registerReceiverCompat(receiver: BroadcastReceiver?, filter: IntentFilter, exported: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, if (exported) RECEIVER_EXPORTED else RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        resizeExecutorPools()
        nativePlayerManager.setTextureRegistry(flutterEngine.renderer)
        vaultCameraPlugin = com.aeidolon.vaultexplorer.camera.VaultCameraPlugin(this, flutterEngine.dartExecutor.binaryMessenger, flutterEngine.renderer)
        quickCaptureScratchpadPlugin = com.aeidolon.vaultexplorer.camera.QuickCaptureScratchpadPlugin(this, flutterEngine.dartExecutor.binaryMessenger)

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
                    val isLocalStorage = call.argument<Boolean>("isLocalStorage") ?: false
                    val textureId = nativePlayerManager.initialize(volId, filePath, isLocalStorage)
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
                "getDeviceVolume" -> {
                    try {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val min = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            am.getStreamMinVolume(AudioManager.STREAM_MUSIC)
                        } else {
                            0
                        }
                        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                        val norm = if (max > min) (cur - min).toFloat() / (max - min).toFloat() else 0f
                        result.success(norm.toDouble())
                    } catch (e: Exception) {
                        result.success(1.0)
                    }
                }
                "setDeviceVolume" -> {
                    try {
                        val volume = call.argument<Number>("volume")?.toFloat() ?: 1.0f
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val min = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            am.getStreamMinVolume(AudioManager.STREAM_MUSIC)
                        } else {
                            0
                        }
                        val target = Math.round(min + volume.coerceIn(0f, 1f) * (max - min))
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                        result.success(null)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "setScreenBrightness" -> {
                    // Brightness is a per-window Activity property, not
                    // tied to the player engine itself, so this is handled
                    // directly here rather than via nativePlayerManager.
                    // A negative value clears the override (back to the
                    // system brightness) -- used when the media viewer
                    // screen itself is torn down.
                    val brightness = call.argument<Number>("brightness")?.toFloat() ?: -1f
                    val attributes = window.attributes
                    attributes.screenBrightness = if (brightness < 0f) {
                        WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    } else {
                        brightness.coerceIn(0.01f, 1.0f)
                    }
                    window.attributes = attributes
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
                "startScrubPreview" -> {
                    nativePlayerManager.startScrubPreview { available ->
                        result.success(mapOf("available" to available))
                    }
                }
                "getScrubPreviewFrame" -> {
                    val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                    val maxSize = call.argument<Number>("maxSize")?.toInt() ?: 200
                    val quality = call.argument<Number>("quality")?.toInt() ?: 55
                    nativePlayerManager.getScrubPreviewFrame(positionMs, maxSize, quality) { bytes ->
                        result.success(bytes)
                    }
                }
                "endScrubPreview" -> {
                    nativePlayerManager.endScrubPreview()
                    result.success(null)
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
        ExportProgressBridge.channel = channel
        HiddenVolumeProtectionBridge.channel = channel
        SplitJoinProgressBridge.channel = channel
        RepairLogBridge.channel = channel
        HashProgressBridge.channel = channel
        VaultForceLockedBridge.channel = channel
        VaultAutomationUnlockedBridge.channel = channel
        CopyProgressBridge.channel = channel
        VaultCameraStopRequestedBridge.channel = channel

        val disguiseChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DISGUISE_CHANNEL)
        ExternalOpenBridge.channel = disguiseChannel

        // ONLY VaultShareActivity should receive incoming share pushes
        if (this is VaultShareActivity) {
            IncomingShareBridge.channel = channel
            LocalIncomingShareBridge.channel = disguiseChannel
        } else {
            IncomingShareBridge.channel = null
            LocalIncomingShareBridge.channel = null
        }

        // ONLY VaultQuickCaptureActivity should receive Quick Capture pushes
        if (this is VaultQuickCaptureActivity) {
            QuickCaptureBridge.channel = channel
        } else {
            QuickCaptureBridge.channel = null
        }
        disguiseChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                DisguiseChannelMethods.GET_MODE -> disguiseModeHandlers.handleGetMode(call, result)
                DisguiseChannelMethods.SET_MODE -> disguiseModeHandlers.handleSetMode(call, result)
                DisguiseChannelMethods.CHECK_PENDING_LOCAL_SHARE_REQUEST ->
                    shareIntentHandlers.handleCheckPendingLocalShareRequest(call, result)
                DisguiseChannelMethods.TAKE_PENDING_LOCAL_SHARE_REQUEST ->
                    shareIntentHandlers.handleTakePendingLocalShareRequest(call, result)
                DisguiseChannelMethods.CANCEL_PENDING_LOCAL_SHARE_REQUEST ->
                    shareIntentHandlers.handleCancelPendingLocalShareRequest(call, result)
                DisguiseChannelMethods.RETURN_TO_SHARING_APP_LOCAL ->
                    shareIntentHandlers.handleReturnToSharingApp(call, result)
                DisguiseChannelMethods.IMPORT_SHARED_URIS_TO_LOCAL ->
                    localFileHandlers.handleImportSharedUrisToLocal(call, result)
                DisguiseChannelMethods.HANDOFF_LOCAL_SHARE_TO_VAULT ->
                    shareIntentHandlers.handleHandoffLocalShareToVault(call, result)
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
        registerReceiverCompat(usbPermissionReceiver, usbFilter, exported = true)

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
        registerReceiverCompat(usbDetachReceiver, detachFilter, exported = false)

         screenOffReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != Intent.ACTION_SCREEN_OFF) return
                if (VaultCameraRecordingService.isRunning) {
                    VeLog.i("MainActivity") { "screenOffReceiver: camera recording active, suppressing onScreenOff auto-lock" }
                    return
                }
                VeLog.i("MainActivity") { "screenOffReceiver: ACTION_SCREEN_OFF received, dispatching onScreenOff to Dart" }
                runOnUiThread {
                    methodChannel?.invokeMethod("onScreenOff", null)
                }
            }
        }
        val screenOffFilter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        registerReceiverCompat(screenOffReceiver, screenOffFilter, exported = false)

        registerReceiverCompat(chooserReceiver, filter, exported = true)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                ChannelMethods.SET_DEBUG_LOGGING -> {
                    VeLog.enabled = call.argument<Boolean>("enabled") == true
                    result.success(null)
                }
                ChannelMethods.SET_SECURE_SCREEN -> systemHandlers.handleSetSecureScreen(call, result)
                ChannelMethods.SET_RECENTS_SNAPSHOT_BLOCKED -> systemHandlers.handleSetRecentsSnapshotBlocked(call, result)
                ChannelMethods.NOTIFY_RESUMED_FRAME_PAINTED -> { privacyCurtain.reveal(); result.success(true) }
                ChannelMethods.SET_SENSITIVE_CLIPBOARD_TEXT -> systemHandlers.handleSetSensitiveClipboardText(call, result)
                ChannelMethods.CLEAR_SENSITIVE_CLIPBOARD_TEXT -> systemHandlers.handleClearSensitiveClipboardText(call, result)
                ChannelMethods.HAS_ALL_FILES_ACCESS -> systemHandlers.handleHasAllFilesAccess(call, result)
                ChannelMethods.REQUEST_ALL_FILES_ACCESS -> systemHandlers.handleRequestAllFilesAccess(call, result)
                ChannelMethods.HAS_OVERLAY_PERMISSION -> systemHandlers.handleHasOverlayPermission(call, result)
                ChannelMethods.REQUEST_OVERLAY_PERMISSION -> systemHandlers.handleRequestOverlayPermission(call, result)
                ChannelMethods.REQUEST_NOTIFICATION_PERMISSION -> systemHandlers.handleRequestNotificationPermission(call, result)
                ChannelMethods.OPEN_LOCAL_FILE_WITH_APP -> localFileHandlers.handleOpenLocalFileWithApp(call, result)
                ChannelMethods.GET_LOCAL_FILE_URI -> localFileHandlers.handleGetLocalFileUri(call, result)
                ChannelMethods.SHARE_LOCAL_FILE -> localFileHandlers.handleShareLocalFile(call, result)
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
                ChannelMethods.DETECTS_AS_PLAIN_DISK_IMAGE -> vaultUnlockHandlers.handleDetectsAsPlainDiskImage(call, result)
                ChannelMethods.PROBE_CONTAINER_FORMAT -> vaultUnlockHandlers.handleProbeContainerFormat(call, result)
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
                ChannelMethods.SET_DERIVED_KEY_EXPIRY -> derivedKeyHandlers.handleSetDerivedKeyExpiry(call, result)
                ChannelMethods.GET_DERIVED_KEY_EXPIRY -> derivedKeyHandlers.handleGetDerivedKeyExpiry(call, result)
                ChannelMethods.PURGE_EXPIRED_DERIVED_KEYS -> derivedKeyHandlers.handlePurgeExpiredDerivedKeys(call, result)
                ChannelMethods.HASH_PASSWORD -> derivedKeyHandlers.handleHashPassword(call, result)
                ChannelMethods.HASH_PASSWORD_SHA256 -> derivedKeyHandlers.handleHashPasswordSha256(call, result)
                ChannelMethods.AES_GCM_ENCRYPT -> derivedKeyHandlers.handleAesGcmEncrypt(call, result)
                ChannelMethods.AES_GCM_DECRYPT -> derivedKeyHandlers.handleAesGcmDecrypt(call, result)
                ChannelMethods.READ_SECURE -> secureStorageHandlers.handleRead(call, result)
                ChannelMethods.WRITE_SECURE -> secureStorageHandlers.handleWrite(call, result)
                ChannelMethods.DELETE_SECURE -> secureStorageHandlers.handleDelete(call, result)
                ChannelMethods.DELETE_ALL_SECURE -> secureStorageHandlers.handleDeleteAll(call, result)
                ChannelMethods.READ_ALL_SECURE -> secureStorageHandlers.handleReadAll(call, result)
                ChannelMethods.CONTAINS_KEY_SECURE -> secureStorageHandlers.handleContainsKey(call, result)
                ChannelMethods.GET_AUTOMATION_TOKEN -> automationSettingsHandlers.handleGetAutomationToken(call, result)
                ChannelMethods.REGENERATE_AUTOMATION_TOKEN -> automationSettingsHandlers.handleRegenerateAutomationToken(call, result)
                ChannelMethods.GET_AUTOMATION_VAULT_CONFIG -> automationSettingsHandlers.handleGetAutomationVaultConfig(call, result)
                ChannelMethods.SET_AUTOMATION_TIER -> automationSettingsHandlers.handleSetAutomationTier(call, result)
                ChannelMethods.SET_AUTOMATION_PASSWORD -> automationSettingsHandlers.handleSetAutomationPassword(call, result)
                ChannelMethods.GET_AUTOMATION_KEYFILES -> automationSettingsHandlers.handleGetAutomationKeyfiles(call, result)
                ChannelMethods.SET_AUTOMATION_KEYFILES -> automationSettingsHandlers.handleSetAutomationKeyfiles(call, result)
                ChannelMethods.GET_AUTOMATION_PIM -> automationSettingsHandlers.handleGetAutomationPim(call, result)
                ChannelMethods.SET_AUTOMATION_PIM -> automationSettingsHandlers.handleSetAutomationPim(call, result)
                ChannelMethods.SET_AUTOMATION_CAPTURE_ENABLED -> automationSettingsHandlers.handleSetAutomationCaptureEnabled(call, result)
                ChannelMethods.GET_VIDEO_THUMBNAIL -> thumbnailHandlers.handleGetVideoThumbnail(call, result)
                ChannelMethods.GET_IMAGE_THUMBNAIL -> thumbnailHandlers.handleGetImageThumbnail(call, result)
                ChannelMethods.GET_IMAGE_THUMBNAIL_WITH_SIZE -> thumbnailHandlers.handleGetImageThumbnailWithSize(call, result)
                ChannelMethods.GET_VIDEO_THUMBNAIL_WITH_SIZE -> thumbnailHandlers.handleGetVideoThumbnailWithSize(call, result)
                ChannelMethods.GET_APK_ICON -> thumbnailHandlers.handleGetApkIcon(call, result)
                ChannelMethods.ENCODE_IMAGE -> thumbnailHandlers.handleEncodeImage(call, result)
                ChannelMethods.SET_PLAYBACK_ACTIVE -> thumbnailHandlers.handleSetPlaybackActive(call, result)
                ChannelMethods.LOCK_CONTAINER -> vaultUnlockHandlers.handleLockContainer(call, result)
                ChannelMethods.SYNC_BACKGROUND_SERVICE -> backgroundServiceHandlers.handleSyncBackgroundService(call, result)
                ChannelMethods.UPDATE_BACKGROUND_SERVICE_PROGRESS -> backgroundServiceHandlers.handleUpdateProgress(call, result)
                ChannelMethods.START_BACKGROUND_RECORDING -> cameraRecordingServiceHandlers.handleStartBackgroundRecording(call, result)
                ChannelMethods.STOP_BACKGROUND_RECORDING -> cameraRecordingServiceHandlers.handleStopBackgroundRecording(call, result)
                ChannelMethods.UPDATE_CONTAINER_SETTINGS -> vaultUnlockHandlers.handleUpdateContainerSettings(call, result)
                ChannelMethods.GET_ACTIVE_CONTAINER_SESSIONS -> vaultUnlockHandlers.handleGetActiveContainerSessions(call, result)
                ChannelMethods.DECRYPT_FILE -> fileOperationHandlers.handleDecryptFile(call, result)
                ChannelMethods.GET_FILE_SIZE -> fileOperationHandlers.handleGetFileSize(call, result)
                ChannelMethods.GET_FOLDER_SIZE -> fileOperationHandlers.handleGetFolderSize(call, result)
                ChannelMethods.READ_FILE_CHUNK -> fileOperationHandlers.handleReadFileChunk(call, result)
                ChannelMethods.GET_MEDIA_FILE_SIZE -> fileOperationHandlers.handleGetMediaFileSize(call, result)
                ChannelMethods.READ_MEDIA_FILE_CHUNK -> fileOperationHandlers.handleReadMediaFileChunk(call, result)
                ChannelMethods.LIST_DIRECTORY -> fileOperationHandlers.handleListDirectory(call, result)
                ChannelMethods.CREATE_DIRECTORY -> fileOperationHandlers.handleCreateDirectory(call, result)
                ChannelMethods.RENAME_FILE -> fileOperationHandlers.handleRenameFile(call, result)
                ChannelMethods.COPY_FILE -> fileOperationHandlers.handleCopyFile(call, result)
                ChannelMethods.CANCEL_COPY -> fileOperationHandlers.handleCancelCopy(call, result)
                ChannelMethods.CLEAR_COPY_STATE -> fileOperationHandlers.handleClearCopyState(call, result)
                ChannelMethods.WRITE_BACK_FILE -> fileOperationHandlers.handleWriteBackFile(call, result)
                ChannelMethods.SET_LAST_MODIFIED_TIME -> fileOperationHandlers.handleSetLastModifiedTime(call, result)
                ChannelMethods.GET_SPACE_INFO -> fileOperationHandlers.handleGetSpaceInfo(call, result)
     ChannelMethods.SAF_LIST_DIRECTORY -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val dirPath = call.argument<String>("dirPath") ?: ""
                    val refresh = call.argument<Boolean>("refresh") ?: false
                    ioExecutor.execute {
                        val entries = safStorageManager.listDirectory(treeUri, dirPath, refresh)
                        val list = entries.map { entry ->
                            mapOf(
                                "name" to entry.name,
                                "isDir" to entry.isDir,
                                "size" to entry.size,
                                "lastModified" to entry.lastModified
                            )
                        }
                        runOnUiThread { result.success(list) }
                    }
                }
                ChannelMethods.SAF_CHECK_TREE_ACCESS -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    ioExecutor.execute {
                        val accessible = safStorageManager.isTreeAccessible(treeUri)
                        runOnUiThread { result.success(accessible) }
                    }
                }
                ChannelMethods.SAF_GET_FILE_SIZE -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val filePath = call.argument<String>("filePath") ?: ""
                    ioExecutor.execute {
                        val size = safStorageManager.getFileSize(treeUri, filePath)
                        runOnUiThread { result.success(size) }
                    }
                }
             ChannelMethods.SAF_READ_FILE_CHUNK -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val filePath = call.argument<String>("filePath") ?: ""
                    val offset = (call.argument<Number>("offset") ?: 0).toLong()
                    val length = call.argument<Int>("length") ?: 0
                    ioExecutor.execute {
                        try {
                            val bytes = safStorageManager.readFileChunk(treeUri, filePath, offset, length)
                            runOnUiThread { result.success(bytes) }
                        } catch (t: Throwable) {
                            VeLog.e("MainActivity", t) { "SAF_READ_FILE_CHUNK failed: ${t.message}" }
                            if (t is OutOfMemoryError) System.gc()
                            runOnUiThread { result.success(null) }
                        }
                    }
                }
                ChannelMethods.SAF_WRITE_FILE_CHUNK -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val filePath = call.argument<String>("filePath") ?: ""
                    val offset = (call.argument<Number>("offset") ?: 0).toLong()
                    val data = call.argument<ByteArray>("data") ?: byteArrayOf()
                    ioExecutor.execute {
                        val ok = safStorageManager.writeFileChunk(treeUri, filePath, offset, data)
                        runOnUiThread { result.success(ok) }
                    }
                }
                ChannelMethods.SAF_CREATE_FILE -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val filePath = call.argument<String>("filePath") ?: ""
                    val mimeType = call.argument<String>("mimeType")
                    ioExecutor.execute {
                        val ok = safStorageManager.createFile(treeUri, filePath, mimeType)
                        runOnUiThread { result.success(ok) }
                    }
                }
                ChannelMethods.SAF_CREATE_DIRECTORY -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val parentPath = call.argument<String>("parentPath") ?: ""
                    val dirName = call.argument<String>("dirName") ?: ""
                    ioExecutor.execute {
                        val ok = safStorageManager.createDirectory(treeUri, parentPath, dirName)
                        runOnUiThread { result.success(ok) }
                    }
                }
                ChannelMethods.SAF_RENAME_FILE -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val filePath = call.argument<String>("filePath") ?: ""
                    val newName = call.argument<String>("newName") ?: ""
                    ioExecutor.execute {
                        val ok = safStorageManager.renameFile(treeUri, filePath, newName)
                        runOnUiThread { result.success(ok) }
                    }
                }
                ChannelMethods.SAF_DELETE_FILE -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val filePath = call.argument<String>("filePath") ?: ""
                    ioExecutor.execute {
                        val ok = safStorageManager.deleteRecursively(treeUri, filePath)
                        runOnUiThread { result.success(ok) }
                    }
                }
                ChannelMethods.SAF_GET_SPACE_INFO -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    ioExecutor.execute {
                        val space = safStorageManager.getSpaceInfo(treeUri)
                        runOnUiThread { result.success(space) }
                    }
                }
                ChannelMethods.SAF_GET_THUMBNAIL -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val filePath = call.argument<String>("filePath") ?: ""
                    val targetSize = call.argument<Int>("targetSize") ?: 180
                    val quality = call.argument<Int>("quality") ?: 70
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    ioExecutor.execute {
                        val thumb = safStorageManager.getThumbnail(treeUri, filePath, targetSize, quality, isVideo)
                        runOnUiThread { result.success(thumb) }
                    }
                }
                ChannelMethods.SAF_OPEN_WITH_APP -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val filePath = call.argument<String>("filePath") ?: ""
                    val mimeType = call.argument<String>("mimeType")
                    val packageName = call.argument<String>("packageName")
                    val ok = safStorageManager.openWithApp(treeUri, filePath, mimeType, packageName)
                    result.success(ok)
                }
                ChannelMethods.SAF_SHARE_FILES -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val filePaths = call.argument<List<String>>("filePaths") ?: emptyList()
                    val ok = safStorageManager.shareFiles(treeUri, filePaths)
                    result.success(ok)
                }
                ChannelMethods.SAF_GET_DOCUMENT_URI -> {
                    val treeUri = Uri.parse(call.argument<String>("treeUri") ?: "")
                    val filePath = call.argument<String>("filePath") ?: ""
                    val docUri = safStorageManager.getDocumentUri(treeUri, filePath)
                    result.success(docUri?.toString())
                }
                ChannelMethods.SAF_COPY_FILE -> {
                    val srcTreeUri = call.argument<String>("srcTreeUri")?.let { Uri.parse(it) }
                    val srcPath = call.argument<String>("srcPath") ?: ""
                    val destTreeUri = call.argument<String>("destTreeUri")?.let { Uri.parse(it) }
                    val destPath = call.argument<String>("destPath") ?: ""
                    ioExecutor.execute {
                        val ok = safStorageManager.copyFile(srcTreeUri, srcPath, destTreeUri, destPath)
                        runOnUiThread { result.success(ok) }
                    }
                }
                ChannelMethods.GET_STORAGE_VOLUMES -> {
                    ioExecutor.execute {
                        val volumes = safStorageManager.getStorageVolumes()
                        runOnUiThread { result.success(volumes) }
                    }
                }
                ChannelMethods.GET_VAULT_INFO -> fileOperationHandlers.handleGetVaultInfo(call, result)
                ChannelMethods.DELETE_FILE -> fileOperationHandlers.handleDeleteFile(call, result)
                ChannelMethods.OPEN_WITH_APP -> systemHandlers.handleOpenWithApp(call, result)
                ChannelMethods.INSTALL_APK -> systemHandlers.handleInstallApk(call, result)
                ChannelMethods.SHARE_FILE -> systemHandlers.handleShareFile(call, result)
                ChannelMethods.SET_KEEP_SCREEN_ON -> systemHandlers.handleSetKeepScreenOn(call, result)
                ChannelMethods.LAUNCH_URL -> systemHandlers.handleLaunchUrl(call, result)
                ChannelMethods.GET_APP_VERSION -> systemHandlers.handleGetAppVersion(call, result)
                ChannelMethods.GET_ANDROID_SDK_INT -> systemHandlers.handleGetAndroidSdkInt(call, result)
                ChannelMethods.IMPORT_FILE -> importExportHandlers.handleImportFile(call, result)
                ChannelMethods.EXPORT_FILES_FOLDER -> importExportHandlers.handleExportFilesFolder(call, result)
                ChannelMethods.CANCEL_EXPORT -> importExportHandlers.handleCancelExport(call, result)
                ChannelMethods.IMPORT_FOLDER -> importExportHandlers.handleImportFolder(call, result)
                ChannelMethods.PICK_IMPORT_FILES -> importExportHandlers.handlePickImportFiles(call, result)
                ChannelMethods.PICK_IMPORT_FOLDER -> importExportHandlers.handlePickImportFolder(call, result)
                ChannelMethods.CANCEL_PICKED_IMPORT -> importExportHandlers.handleCancelPickedImport(call, result)
                ChannelMethods.EXPORT_FILE -> importExportHandlers.handleExportFile(call, result)
                ChannelMethods.EXPORT_APP_SETTINGS_FILE -> appSettingsFileHandlers.handleExportAppSettingsFile(call, result)
                ChannelMethods.IMPORT_APP_SETTINGS_FILE -> appSettingsFileHandlers.handleImportAppSettingsFile(call, result)
                ChannelMethods.EXPORT_LOG_FILE -> logExportHandlers.handleExportLogFile(call, result)
                ChannelMethods.SPLIT_CONTAINER -> splitJoinHandlers.handleSplitContainer(call, result)
                ChannelMethods.JOIN_CONTAINER -> splitJoinHandlers.handleJoinContainer(call, result)
                ChannelMethods.CANCEL_SPLIT_JOIN -> splitJoinHandlers.handleCancelSplitJoin(call, result)
                ChannelMethods.UNLOCK_SPLIT_CONTAINER -> splitContainerMountHandlers.handleUnlockSplitContainer(call, result)
                ChannelMethods.ENCRYPT_SINGLE_FILE -> singleFileCryptoHandlers.handleEncryptSingleFile(call, result)
                ChannelMethods.DECRYPT_SINGLE_FILE -> singleFileCryptoHandlers.handleDecryptSingleFile(call, result)
                ChannelMethods.COMPUTE_EXTERNAL_FILE_HASH -> hashVerifierHandlers.handleComputeExternalFileHash(call, result)
                ChannelMethods.CANCEL_HASH_COMPUTE -> hashVerifierHandlers.handleCancelHashCompute(call, result)
                ChannelMethods.READ_EXTERNAL_FILE_BYTES -> hashVerifierHandlers.handleReadExternalFileBytes(call, result)
                ChannelMethods.WRITE_EXTERNAL_FILE_BYTES -> hashVerifierHandlers.handleWriteExternalFileBytes(call, result)
                ChannelMethods.HASH_BYTES_SHA256 -> hashVerifierHandlers.handleHashBytesSha256(call, result)
                ChannelMethods.HASH_BYTES_MD5 -> hashVerifierHandlers.handleHashBytesMd5(call, result)
                ChannelMethods.BEGIN_HASH_SESSION -> hashVerifierHandlers.handleBeginHashSession(call, result)
                ChannelMethods.UPDATE_HASH_SESSION -> hashVerifierHandlers.handleUpdateHashSession(call, result)
                ChannelMethods.FINISH_HASH_SESSION -> hashVerifierHandlers.handleFinishHashSession(call, result)
                ChannelMethods.DISCARD_HASH_SESSION -> hashVerifierHandlers.handleDiscardHashSession(call, result)
                ChannelMethods.WRITE_FILE_CHUNK -> fileOperationHandlers.handleWriteFileChunk(call, result)
                ChannelMethods.BEGIN_BATCH_WRITE -> fileOperationHandlers.handleBeginBatchWrite(call, result)
                ChannelMethods.END_BATCH_WRITE -> fileOperationHandlers.handleEndBatchWrite(call, result)
                ChannelMethods.BEGIN_BATCH_DELETE -> fileOperationHandlers.handleBeginBatchDelete(call, result)
                ChannelMethods.END_BATCH_DELETE -> fileOperationHandlers.handleEndBatchDelete(call, result)
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
                ChannelMethods.REPAIR_FOLDER_VAULT -> repairHandlers.handleRepairFolderVault(call, result)
                ChannelMethods.ARCHIVE_SCAN_VAULT -> archiveHandlers.handleArchiveScanVault(call, result)
                ChannelMethods.ARCHIVE_EXTRACT_VAULT_ENTRY -> archiveHandlers.handleArchiveExtractVaultEntry(call, result)
                ChannelMethods.ARCHIVE_EXTRACT_VAULT_ALL -> archiveHandlers.handleArchiveExtractVaultAll(call, result)
                ChannelMethods.ARCHIVE_SCAN_LOCAL -> archiveHandlers.handleArchiveScanLocal(call, result)
                ChannelMethods.ARCHIVE_EXTRACT_LOCAL_ENTRY -> archiveHandlers.handleArchiveExtractLocalEntry(call, result)
                ChannelMethods.ARCHIVE_CREATE -> archiveHandlers.handleArchiveCreate(call, result)
                ChannelMethods.EXPORT_CONTAINER_HEADER -> headerBackupHandlers.handleExportContainerHeader(call, result)
                ChannelMethods.RESTORE_CONTAINER_HEADER_REGION ->
                    headerBackupHandlers.handleRestoreContainerHeaderRegion(call, result)
                ChannelMethods.RESOLVE_FOLDER_VAULT_CONFIG_FILE ->
                    headerBackupHandlers.handleResolveFolderVaultConfigFile(call, result)
                ChannelMethods.RESTORE_FOLDER_VAULT_CONFIG ->
                    headerBackupHandlers.handleRestoreFolderVaultConfig(call, result)
                ChannelMethods.PROFILE_CARRIERS -> compositeHandlers.handleProfileCarriers(call, result)
                ChannelMethods.CREATE_COMPOSITE_CONTAINER -> compositeHandlers.handleCreateCompositeContainer(call, result)
                ChannelMethods.UNLOCK_COMPOSITE_CONTAINER -> compositeHandlers.handleUnlockCompositeContainer(call, result)
                ChannelMethods.SET_SHARE_TARGET_ENABLED -> shareIntentHandlers.handleSetShareTargetEnabled(call, result)
                ChannelMethods.IS_SHARE_TARGET_ENABLED -> shareIntentHandlers.handleIsShareTargetEnabled(call, result)
                ChannelMethods.CHECK_PENDING_SHARE_REQUEST -> shareIntentHandlers.handleCheckPendingShareRequest(call, result)
                ChannelMethods.CANCEL_PENDING_SHARE_REQUEST -> shareIntentHandlers.handleCancelPendingShareRequest(call, result)
                ChannelMethods.CHECK_PENDING_QUICK_CAPTURE_REQUEST ->
                    quickCaptureSettingsHandlers.handleCheckPendingQuickCaptureRequest(call, result)
                ChannelMethods.GET_QUICK_CAPTURE_SETTINGS ->
                    quickCaptureSettingsHandlers.handleGetQuickCaptureSettings(call, result)
                ChannelMethods.SET_QUICK_CAPTURE_TILE_ENABLED ->
                    quickCaptureSettingsHandlers.handleSetQuickCaptureTileEnabled(call, result)
                ChannelMethods.REQUEST_PIN_QUICK_CAPTURE_SHORTCUT ->
                    quickCaptureSettingsHandlers.handleRequestPinQuickCaptureShortcut(call, result)
                ChannelMethods.RETURN_TO_SHARING_APP -> shareIntentHandlers.handleReturnToSharingApp(call, result)
                ChannelMethods.PREPARE_SHARE_IMPORT -> importExportHandlers.handlePrepareShareImport(call, result)
                ChannelMethods.GET_PANIC_SETTINGS -> panicSettingsHandlers.handleGetPanicSettings(call, result)
                ChannelMethods.SET_PANIC_TIER -> panicSettingsHandlers.handleSetPanicTier(call, result)
                ChannelMethods.SET_QUICK_TILE_ENABLED -> panicSettingsHandlers.handleSetQuickTileEnabled(call, result)
                ChannelMethods.GET_PANIC_KIT_STATUS -> panicSettingsHandlers.handleGetPanicKitStatus(call, result)
                ChannelMethods.SET_PANIC_KIT_ENABLED -> panicSettingsHandlers.handleSetPanicKitEnabled(call, result)
                ChannelMethods.SET_PANIC_KIT_PAIRING_ENFORCEMENT ->
                    panicSettingsHandlers.handleSetPanicKitPairingEnforcement(call, result)
                ChannelMethods.UNPAIR_PANIC_KIT -> panicSettingsHandlers.handleUnpairPanicKit(call, result)
                ChannelMethods.TRIGGER_PANIC -> panicSettingsHandlers.handleTriggerPanic(call, result)
                ChannelMethods.GET_PANIC_BOOT_TRIGGER_SETTINGS ->
                    panicSettingsHandlers.handleGetPanicBootTriggerSettings(call, result)
                ChannelMethods.SET_PANIC_BOOT_TRIGGER_TIER ->
                    panicSettingsHandlers.handleSetPanicBootTriggerTier(call, result)
                ChannelMethods.SET_PANIC_BOOT_TRIGGER_ARMED ->
                    panicSettingsHandlers.handleSetPanicBootTriggerArmed(call, result)
                else -> result.notImplemented()
            }
        }
    }
}