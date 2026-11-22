// Which engine-channel methods the desktop host does NOT answer, and why.
//
// `DesktopEngineHost` answers a method in one of four ways: a `case` in its switch, a primitive handled by
// `DesktopCrypto`, an entry in its `_androidOnlyDefaults` table (a harmless value), or -- for everything
// else -- `null`. Before this file existed, "answers null" covered three very different situations and
// nothing told them apart:
//
//   * the feature is Android-only and has no desktop equivalent        -> [desktopAndroidOnlyMethods]
//   * the feature should exist on desktop and is planned, not done yet -> [desktopPendingMethods]
//   * somebody simply forgot                                           -> the coverage test fails
//
// test/core/engine/desktop/desktop_method_coverage_test.dart diffs `ChannelMethods` against the host, the
// crypto handler, the defaults table and these two sets. A new channel method therefore has to be put
// somewhere on purpose, and a method that gets implemented has to leave its set here (the test fails if a
// method is both handled and listed), so these lists can only shrink as the desktop port progresses.
//
// The phase numbers refer to "VaultExplorer -- Desktop Migration & Agnostic-Layer Implementation Plan".

/// Methods that belong to an Android-only feature. Desktop never implements them; the host answers `null`
/// (callers either treat that as "not available" or are never reached because the feature is hidden).
const Set<String> desktopAndroidOnlyMethods = {
  // Automation API (Tasker / MacroDroid broadcast receiver).
  'getAutomationKeyfiles',
  'getAutomationPermissionStatus',
  'getAutomationPim',
  'getAutomationToken',
  'getAutomationVaultConfig',
  'regenerateAutomationToken',
  'requestAutomationPermission',
  'setAutomationCaptureEnabled',
  'setAutomationKeyfiles',
  'setAutomationPassword',
  'setAutomationPim',
  'setAutomationTier',

  // Panic, PanicKit and the emergency tile.
  'getPanicBootTriggerSettings',
  'getPanicKitStatus',
  'getPanicSettings',
  'setPanicBootTriggerArmed',
  'setPanicBootTriggerTier',
  'setPanicKitEnabled',
  'setPanicKitPairingEnforcement',
  'setPanicTier',
  'setQuickTileEnabled',
  'triggerPanic',
  'unpairPanicKit',

  // Quick Capture (Quick Settings tile / pinned shortcut) and background camera recording.
  'getQuickCaptureSettings',
  'requestPinQuickCaptureShortcut',
  'setQuickCaptureTileEnabled',
  'startBackgroundRecording',
  'stopBackgroundRecording',

  // Android share sheet integration.
  'cancelPendingShareRequest',
  'prepareShareImport',
  'returnToSharingApp',
  'shareFile',
  'shareLocalFile',

  // USB OTG mass storage.
  'createUsbContainer',
  'getUsbDeviceCapacity',
  'listUsbDevices',
  'requestUsbPermission',
  'unlockUsbContainer',

  // Storage Access Framework and document providers.
  'safCanListDirectory',
  'safCheckTreeAccess',
  'safCopyFile',
  'safCopyVaultFile',
  'safCreateDirectory',
  'safCreateFile',
  'safDeleteFile',
  'safGetDocumentUri',
  'safGetFileSize',
  'safGetRealPath',
  'safGetSpaceInfo',
  'safListDirectory',
  'safMoveFile',
  'safOpenWithApp',
  'safReadFileChunk',
  'safRenameFile',
  'safShareFiles',
  'safWriteFileChunk',

  // Android system integration.
  'exportLogFile', // the in-app Logcat viewer's export
  'getApkIcon',
  'installApk',
  'onTrimMemory',
  // Android's MediaStore index. A null answer is the documented "walk the folders instead" signal
  // (category_media_index_api.dart), which is exactly what desktop needs.
  'queryCategoryIndex',
  // Keystore-backed biometric sentinel key. On desktop BiometricKeyStatus.fromWire(null) maps to `error`,
  // which never sets `requiresRevert`, so desktop cannot trigger a credential reset.
  'biometricKeyStatus',

  // The Jetpack (androidx.pdf) viewer fragment. Desktop's PDF viewer is a separate item (Phase 6.1).
  'isJetpackPdfViewerSupported',
  'printPdf',
  'registerJetpackPdfSession',
  'revokeJetpackPdfSession',
};

/// Methods that SHOULD work on desktop and are planned, grouped by the phase that delivers them.
/// Each one answers `null` today; when a phase lands, move its methods out of this set.
const Set<String> desktopPendingMethods = {
  // Phase 1a, second half -- creating archives. Browsing, extracting, staging and the pickers are done
  // (ve_archive_* in ffi/ve_archive.cpp, desktop_archive.dart).
  'archiveCreate',

  // Phase 1b -- Check & Repair and header backup.
  'checkFolderVault',
  'diagnoseMountedVolumeFilesystem',
  'diagnoseUnmountedContainerFile',
  'exportContainerHeader',
  'pickFolderVaultForRepair',
  'repairFolderVault',
  'resolveFolderVaultConfigFile',
  'restoreBackupHeaderUnmounted',
  'restoreContainerHeaderRegion',
  'restoreFolderVaultConfig',
  'runMountedVolumeFilesystemCheck',

  // Phase 1c -- container expansion and hidden volumes.
  'analyzeHiddenVolumeHost',
  'createHiddenVolumeInExisting',
  'expandBitLockerContainer',
  'expandLuksContainer',
  'expandVeraCryptContainer',
  'growBitLockerFileSystem',
  'growLuksFileSystem',
  'growVeraCryptFileSystem',

  // Phase 1d -- composite and split containers.
  'createCompositeContainer',
  'profileCarriers',
  'unlockCompositeContainer',
  'unlockSplitContainer',

  // Phase 4.4 -- AVIF (libavif / libgav1 are gated off for desktop builds).
  'decodeAvif',
  'decodeAvifFrame',
  'getAvifInfo',

  // Phase 6.1 -- PDF viewer.
  'closePdf',
  'getPdfPageSize',
  'openPdf',
  'renderPdfPage',

  // Phase 6.2 -- comic (.cbz) and e-book (.epub) readers.
  'bookClose',
  'bookCover',
  'bookOpen',
  'bookReadEntry',

  // Phase 6.3 -- images.
  'probeImageDimensions',

  // Phase 6.4 -- audio and video editing.
  'audioEditExport',
  'audioEditProbe',
  'audioEditWaveform',
  'cancelAudioEdit',
  'cancelVideoEdit',
  'videoEditExport',
  'videoEditProbe',
};
