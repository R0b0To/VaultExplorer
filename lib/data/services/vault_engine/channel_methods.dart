/// Single source of truth for every MethodChannel method name.
///
/// Both [VaultExplorerApi] call-sites and [MainActivity]'s `when` block must
/// use these constants.  The Kotlin side mirrors them in the local
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

  static const String HAS_ALL_FILES_ACCESS = 'hasAllFilesAccess';
  static const String REQUEST_ALL_FILES_ACCESS = 'requestAllFilesAccess';

  // ── Cryptomator vaults ───────────────────────────────────────────────────
  /// Opens ACTION_OPEN_DOCUMENT_TREE (a folder picker, not a file picker —
  /// Cryptomator vaults are directory trees) and checks for
  /// masterkey.cryptomator before returning.
  static const pickCryptomatorVault = 'pickCryptomatorVault';
  static const unlockCryptomatorVault = 'unlockCryptomatorVault';
  static const createCryptomatorVault = 'createCryptomatorVault';
  /// Must be called once after the last writeFileChunk() in a sequence for
  /// a given path, to flush Cryptomator's buffered final chunk. No-op for
  /// VeraCrypt/LUKS volIds.
  static const finishWriteIfCryptomator = 'finishWriteIfCryptomator';

  static const pickGocryptfsVault = 'pickGocryptfsVault';
  static const unlockGocryptfsVault = 'unlockGocryptfsVault';
  static const createGocryptfsVault = 'createGocryptfsVault';

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
  static const getFileSize = 'getFileSize';
  static const getFolderSize ='getFolderSize'; // recursive directory byte total
  static const readFileChunk = 'readFileChunk';
  static const writeBackFile = 'writeBackFile';
  static const getSpaceInfo = 'getSpaceInfo';

  // Same native operation as getFileSize/readFileChunk above, but routed
  // to their own native thread pool (see MainActivity's fullResExecutor)
  // instead of the general-purpose ioExecutor. Use these specifically for
  // Media Viewer full-resolution reads (EncryptedImageWidget,
  // FullResImageCache) so a burst of swipe-driven reads can't queue up
  // behind -- or get queued up behind -- unrelated ioExecutor work like
  // bulk file copy/export, which shares getFileSize/readFileChunk and
  // already runs its own multi-file concurrency. Do not use these for
  // anything other than the Media Viewer's full-res image path.
  static const getMediaFileSize = 'getMediaFileSize';
  static const readMediaFileChunk = 'readMediaFileChunk';

  // ── Directory operations ─────────────────────────────────────────────────
  static const listDirectory = 'listDirectory';
  static const createDirectory = 'createDirectory';
  static const renameFile = 'renameFile';
  static const deleteFile = 'deleteFile';
  static const setLastModifiedTime = 'setLastModifiedTime';

  // ── Media ────────────────────────────────────────────────────────────────
  static const openWithApp = 'openWithApp';
  static const getVideoThumbnail = 'getVideoThumbnail';

  // ── Crypto ───────────────────────────────────────────────────────────────
  /// PBKDF2-SHA512 via the C++ mbedTLS layer.
  static const hashPassword = 'hashPassword';
  static const deriveDerivedKey = 'deriveDerivedKey';
  static const storeDerivedKey = 'storeDerivedKey';
  static const loadDerivedKey = 'loadDerivedKey';
  static const clearDerivedKey = 'clearDerivedKey';

  // ── Security & Privacy ───────────────────────────────────────────────────
  static const setSecureScreen = 'setSecureScreen';

  static const listUsbDevices = 'listUsbDevices';
  static const requestUsbPermission = 'requestUsbPermission';
  static const unlockUsbContainer = 'unlockUsbContainer';
  static const createUsbContainer = 'createUsbContainer';
  static const getUsbDeviceCapacity = 'getUsbDeviceCapacity';
  static const documentExists = 'documentExists';
  static const warmContainer = 'warmContainer';
}
