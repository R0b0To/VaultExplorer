/// Single source of truth for every MethodChannel method name.
///
/// Both [VaultExplorerApi] call-sites and [MainActivity]'s `when` block must
/// use these constants. The Kotlin side mirrors them in the local
/// [ChannelMethods] object inside [MainActivity].
abstract final class ChannelMethods {
  // ── Container lifecycle ──────────────────────────────────────────────────
  static const pickContainer = 'pickContainer';
  static const pickKeyfiles = 'pickKeyfiles';
  static const createContainer = 'createContainer';
  static const unlockContainer = 'unlockContainer';
  static const lockContainer = 'lockContainer';
  static const updateContainerSettings = 'updateContainerSettings';
  static const cancelUnlock = 'cancelUnlock';
  static const changeContainerPassword = 'changeContainerPassword';

  // Exposes/unmounts a single folder inside an unlocked container as its
  // own SAF root, independent of the container-wide documentProvider flag.
  static const mountContainerFolder = 'mountContainerFolder';
  static const unmountContainerFolder = 'unmountContainerFolder';
  static const getMountedContainerFolders = 'getMountedContainerFolders';

  static const hasAllFilesAccess = 'hasAllFilesAccess';
  static const requestAllFilesAccess = 'requestAllFilesAccess';
  
  // ── Cryptomator / Folder Vaults ──────────────────────────────────────────
  /// Opens ACTION_OPEN_DOCUMENT_TREE (a folder picker, not a file picker)
  /// and checks for masterkey.cryptomator, gocryptfs.conf, or cryfs.config.
  static const pickCryptomatorVault = 'pickCryptomatorVault';
  static const unlockCryptomatorVault = 'unlockCryptomatorVault';
  static const createCryptomatorVault = 'createCryptomatorVault';
  static const finishWriteIfCryptomator = 'finishWriteIfCryptomator';

  static const pickGocryptfsVault = 'pickGocryptfsVault';
  static const unlockGocryptfsVault = 'unlockGocryptfsVault';
  static const createGocryptfsVault = 'createGocryptfsVault';
  static const isGocryptfsVault = 'isGocryptfsVault';

  static const pickCryfsVault = 'pickCryfsVault';
  static const unlockCryfsVault = 'unlockCryfsVault';
  static const createCryfsVault = 'createCryfsVault';
  static const isCryfsVault = 'isCryfsVault';

  // ── File I/O ─────────────────────────────────────────────────────────────
  static const decryptFile = 'decryptFile';
  static const exportFileToStorage = 'exportFileToStorage';
  static const exportFilesToFolder = 'exportFilesToFolder';
  static const importFile = 'importFile';
  static const importFolder = 'importFolder';
  static const cancelImport = 'cancelImport';
  // Deletes the source files/folder from device storage that were picked
  // during the import identified by opId. Native keeps the picked URIs
  // in memory (keyed by opId) until this is called or the op is superseded.
  static const deleteImportSources = 'deleteImportSources';
  static const getFileSize = 'getFileSize';
  static const getFolderSize = 'getFolderSize'; // recursive directory byte total
  static const readFileChunk = 'readFileChunk';
  static const writeFileChunk = 'writeFileChunk';
  static const writeBackFile = 'writeBackFile';
  static const getSpaceInfo = 'getSpaceInfo';

  // Routed to fullResExecutor on native side for Media Viewer image reads
  static const getMediaFileSize = 'getMediaFileSize';
  static const readMediaFileChunk = 'readMediaFileChunk';

  // ── Directory operations ─────────────────────────────────────────────────
  static const listDirectory = 'listDirectory';
  static const createDirectory = 'createDirectory';
  static const renameFile = 'renameFile';
  static const deleteFile = 'deleteFile';
  static const setLastModifiedTime = 'setLastModifiedTime';

  // ── Media & Thumbnails ───────────────────────────────────────────────────
  static const openWithApp = 'openWithApp';
  static const getVideoThumbnail = 'getVideoThumbnail';
  static const getImageThumbnail = 'getImageThumbnail';
  // Same output as getImageThumbnail / getVideoThumbnail, plus the source
  // frame's pre-downscale width/height — see ThumbnailWithSize.
  static const getImageThumbnailWithSize = 'getImageThumbnailWithSize';
  static const getVideoThumbnailWithSize = 'getVideoThumbnailWithSize';
  static const setPlaybackActive = 'setPlaybackActive';


  // ── Crypto ───────────────────────────────────────────────────────────────
  static const hashPassword = 'hashPassword';
  static const deriveDerivedKey = 'deriveDerivedKey';
  static const storeDerivedKey = 'storeDerivedKey';
  static const loadDerivedKey = 'loadDerivedKey';
  static const clearDerivedKey = 'clearDerivedKey';

  // ── Security & Privacy ───────────────────────────────────────────────────
  static const setSecureScreen = 'setSecureScreen';

  // ── USB Drive Support ────────────────────────────────────────────────────
  static const listUsbDevices = 'listUsbDevices';
  static const requestUsbPermission = 'requestUsbPermission';
  static const unlockUsbContainer = 'unlockUsbContainer';
  static const createUsbContainer = 'createUsbContainer';
  static const getUsbDeviceCapacity = 'getUsbDeviceCapacity';

  // ── System Utilities ─────────────────────────────────────────────────────
  static const documentExists = 'documentExists';
  static const warmContainer = 'warmContainer';

  // VaultExplorerApi.initMethodCallHandler and CacheCoordinator.
  static const onTrimMemory = 'onTrimMemory';

  // ── Device capability profiling ────────────────────────────────
  static const getDeviceCapabilityProfile = 'getDeviceCapabilityProfile';
}