abstract final class ChannelMethods {
  static const pickContainer = 'pickContainer';
  static const pickKeyfiles = 'pickKeyfiles';
  static const pickCryptoFiles = 'pickCryptoFiles';
  static const pickArchiveFile = 'pickArchiveFile';
  static const pickExtractFolder = 'pickExtractFolder';
  static const createContainer = 'createContainer';
  static const unlockContainer = 'unlockContainer';
  static const lockContainer = 'lockContainer';
  static const syncBackgroundService = 'syncBackgroundService';
  static const startBackgroundRecording = 'startBackgroundRecording';
  static const stopBackgroundRecording = 'stopBackgroundRecording';
  static const updateBackgroundServiceProgress =
      'updateBackgroundServiceProgress';
  static const updateContainerSettings = 'updateContainerSettings';
  static const cancelUnlock = 'cancelUnlock';
  static const changeContainerPassword = 'changeContainerPassword';
  static const changeLuksContainerPassword = 'changeLuksContainerPassword';
  static const getAvifInfo = 'getAvifInfo';
  static const decodeAvifFrame = 'decodeAvifFrame';
  static const decodeAvif = 'decodeAvif';
  static const mountContainerFolder = 'mountContainerFolder';
  static const unmountContainerFolder = 'unmountContainerFolder';
  static const getMountedContainerFolders = 'getMountedContainerFolders';
  static const hasAllFilesAccess = 'hasAllFilesAccess';
  static const requestAllFilesAccess = 'requestAllFilesAccess';
  static const requestNotificationPermission = 'requestNotificationPermission';
  static const pickCryptomatorVault = 'pickCryptomatorVault';
  static const unlockCryptomatorVault = 'unlockCryptomatorVault';
  static const createCryptomatorVault = 'createCryptomatorVault';
  static const changeCryptomatorVaultPassword =
      'changeCryptomatorVaultPassword';
  static const pickGocryptfsVault = 'pickGocryptfsVault';
  static const unlockGocryptfsVault = 'unlockGocryptfsVault';
  static const createGocryptfsVault = 'createGocryptfsVault';
  static const changeGocryptfsVaultPassword = 'changeGocryptfsVaultPassword';
  static const isGocryptfsVault = 'isGocryptfsVault';
  static const pickCryfsVault = 'pickCryfsVault';
  static const unlockCryfsVault = 'unlockCryfsVault';
  static const createCryfsVault = 'createCryfsVault';
  static const changeCryfsVaultPassword = 'changeCryfsVaultPassword';
  static const isCryfsVault = 'isCryfsVault';
  static const decryptFile = 'decryptFile';
  static const exportFileToStorage = 'exportFileToStorage';
  static const exportFilesToFolder = 'exportFilesToFolder';
  static const importFile = 'importFile';
  static const importFolder = 'importFolder';
  static const pickImportFiles = 'pickImportFiles';
  static const pickImportFolder = 'pickImportFolder';
  static const cancelPickedImport = 'cancelPickedImport';
  static const exportAppSettingsFile = 'exportAppSettingsFile';
  static const importAppSettingsFile = 'importAppSettingsFile';
  static const cancelImport = 'cancelImport';
  static const cancelExport = 'cancelExport';
  static const deleteImportSources = 'deleteImportSources';
  static const getFileSize = 'getFileSize';
  static const getFolderSize = 'getFolderSize';
  static const readFileChunk = 'readFileChunk';
  static const writeFileChunk = 'writeFileChunk';

  /// Commits a buffered [writeFileChunk] sequence for whichever
  /// container-backed engine is mounted (Cryptomator, gocryptfs, or
  /// CryFS). Safe to call unconditionally after any writeFileChunk()
  /// sequence -- a documented no-op for VeraCrypt/LUKS/BitLocker.
  static const finishWrite = 'finishWrite';
  static const beginBatchWrite = 'beginBatchWrite';
  static const endBatchWrite = 'endBatchWrite';
  static const beginBatchDelete = 'beginBatchDelete';
  static const endBatchDelete = 'endBatchDelete';
  static const writeBackFile = 'writeBackFile';
  static const getSpaceInfo = 'getSpaceInfo';
  static const getVaultInfo = 'getVaultInfo';
  static const getMediaFileSize = 'getMediaFileSize';
  static const readMediaFileChunk = 'readMediaFileChunk';
  static const splitContainer = 'splitContainer';
  static const joinContainer = 'joinContainer';
  static const cancelSplitJoin = 'cancelSplitJoin';
  static const unlockSplitContainer = 'unlockSplitContainer';
  static const encryptSingleFile = 'encryptSingleFile';
  static const decryptSingleFile = 'decryptSingleFile';
  static const computeExternalFileHash = 'computeExternalFileHash';
  static const cancelHashCompute = 'cancelHashCompute';
  static const readExternalFileBytes = 'readExternalFileBytes';
  static const writeExternalFileBytes = 'writeExternalFileBytes';
  static const hashBytesSha256 = 'hashBytesSha256';
  static const hashBytesMd5 = 'hashBytesMd5';
  static const beginHashSession = 'beginHashSession';
  static const updateHashSession = 'updateHashSession';
  static const finishHashSession = 'finishHashSession';
  static const discardHashSession = 'discardHashSession';
  static const listDirectory = 'listDirectory';
  static const createDirectory = 'createDirectory';
  static const renameFile = 'renameFile';
  static const copyFile = 'copyFile';
  static const cancelCopy = 'cancelCopy';
  static const clearCopyState = 'clearCopyState';
  static const deleteFile = 'deleteFile';
  static const setLastModifiedTime = 'setLastModifiedTime';
  static const openWithApp = 'openWithApp';
  static const getVideoThumbnail = 'getVideoThumbnail';
  static const getImageThumbnail = 'getImageThumbnail';
  static const getImageThumbnailWithSize = 'getImageThumbnailWithSize';
  static const getVideoThumbnailWithSize = 'getVideoThumbnailWithSize';
  static const setPlaybackActive = 'setPlaybackActive';
  static const hashPassword = 'hashPassword';
  static const hashPasswordSha256 = 'hashPasswordSha256';
  static const deriveDerivedKey = 'deriveDerivedKey';
  static const storeDerivedKey = 'storeDerivedKey';
  static const loadDerivedKey = 'loadDerivedKey';
  static const clearDerivedKey = 'clearDerivedKey';
  static const aesGcmEncrypt = 'aesGcmEncrypt';
  static const aesGcmDecrypt = 'aesGcmDecrypt';
  static const readSecure = 'readSecure';
  static const writeSecure = 'writeSecure';
  static const deleteSecure = 'deleteSecure';
  static const deleteAllSecure = 'deleteAllSecure';
  static const readAllSecure = 'readAllSecure';
  static const containsKeySecure = 'containsKeySecure';
  static const getAutomationToken = 'getAutomationToken';
  static const regenerateAutomationToken = 'regenerateAutomationToken';
  static const getAutomationVaultConfig = 'getAutomationVaultConfig';
  static const setAutomationTier = 'setAutomationTier';
  static const setAutomationPassword = 'setAutomationPassword';
  static const getAutomationKeyfiles = 'getAutomationKeyfiles';
  static const setAutomationKeyfiles = 'setAutomationKeyfiles';
  static const getAutomationPim = 'getAutomationPim';
  static const setAutomationPim = 'setAutomationPim';
  static const setAutomationCaptureEnabled = 'setAutomationCaptureEnabled';
  static const getActiveContainerSessions = 'getActiveContainerSessions';
  static const setSecureScreen = 'setSecureScreen';
  static const setRecentsSnapshotBlocked = 'setRecentsSnapshotBlocked';
  static const notifyResumedFramePainted = 'notifyResumedFramePainted';
  static const setSensitiveClipboardText = 'setSensitiveClipboardText';
  static const clearSensitiveClipboardText = 'clearSensitiveClipboardText';
  static const setKeepScreenOn = 'setKeepScreenOn';
  static const setDebugLogging = 'setDebugLogging';
  static const launchUrl = 'launchUrl';
  static const getAppVersion = 'getAppVersion';
  static const getAndroidSdkInt = 'getAndroidSdkInt';
  static const listUsbDevices = 'listUsbDevices';
  static const requestUsbPermission = 'requestUsbPermission';
  static const unlockUsbContainer = 'unlockUsbContainer';
  static const createUsbContainer = 'createUsbContainer';
  static const getUsbDeviceCapacity = 'getUsbDeviceCapacity';
  static const documentExists = 'documentExists';
  static const warmContainer = 'warmContainer';
  static const onTrimMemory = 'onTrimMemory';
  static const getDeviceCapabilityProfile = 'getDeviceCapabilityProfile';

  // Native PDF viewer (android.graphics.pdf.PdfRenderer).
  static const openPdf = 'openPdf';
  static const getPdfPageSize = 'getPdfPageSize';
  static const renderPdfPage = 'renderPdfPage';
  static const closePdf = 'closePdf';

  // Hybrid PDF viewer -- Jetpack androidx.pdf.PdfViewerFragment, falling
  // back to the openPdf/renderPdfPage path above.
  static const isJetpackPdfViewerSupported = 'isJetpackPdfViewerSupported';
  static const registerJetpackPdfSession = 'registerJetpackPdfSession';
  static const revokeJetpackPdfSession = 'revokeJetpackPdfSession';
  static const printPdf = 'printPdf';

  // Check & Repair tool.
  static const diagnoseUnmountedContainerFile = 'diagnoseUnmountedContainerFile';
  static const diagnoseMountedVolumeFilesystem =
      'diagnoseMountedVolumeFilesystem';
  static const restoreBackupHeaderUnmounted = 'restoreBackupHeaderUnmounted';
  static const runMountedVolumeFilesystemCheck =
      'runMountedVolumeFilesystemCheck';
  static const pickFolderVaultForRepair = 'pickFolderVaultForRepair';
  static const checkFolderVault = 'checkFolderVault';
  static const repairFolderVault = 'repairFolderVault';
}