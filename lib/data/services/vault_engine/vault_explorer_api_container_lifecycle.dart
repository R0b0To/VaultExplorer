part of 'vault_explorer_api.dart';

mixin _ContainerLifecycleOps {
  Future<bool> createContainer({
    required String displayName,
    required int sizeBytes,
    required String password,
    required int pim,
    required String fileSystem,
    int containerFormat = 0,
    required int cipherId,
    required int hashId,
    required List<String> keyfilePaths,
    bool createHiddenVolume = false,
    String? hiddenPassword,
    String? hiddenFileSystem,
    int? hiddenSizeBytes,
    List<String>? hiddenKeyfilePaths,
    int? hiddenPim,
    int? hiddenCipherId,
    int? hiddenHashId,
  }) async {
    try {
      final success = await _channel
          .invokeMethod<bool>(ChannelMethods.createContainer, {
        'displayName': displayName,
        'sizeBytes': sizeBytes,
        'password': password,
        'pim': pim,
        'fileSystem': fileSystem,
        'containerFormat': containerFormat,
        'cipherId': cipherId,
        'hashId': hashId,
        'keyfilePaths': keyfilePaths,
        'createHiddenVolume': createHiddenVolume,
        'hiddenPassword': hiddenPassword,
        'hiddenFileSystem': hiddenFileSystem,
        'hiddenSizeBytes': hiddenSizeBytes,
        'hiddenKeyfilePaths': hiddenKeyfilePaths ?? [],
        'hiddenPim': hiddenPim,
        'hiddenCipherId': hiddenCipherId,
        'hiddenHashId': hiddenHashId,
      });
      return success ?? false;
    } catch (e) {
      _logSwallowed('createContainer', e);
      return false;
    }
  }

  /// Queries `DeviceCapabilityProfiler` (Kotlin, ADR-019) once for the
  /// device's LOW/MEDIUM/HIGH tier plus the raw signals it was computed
  /// from. Native caches its own answer for the process lifetime, so this
  /// is cheap to call more than once, but callers (currently just
  /// `runDeferredStartupWork()`) should still only need to call it once.
  ///
  /// Falls back to `tier: 'MEDIUM'` on any channel failure so a caller
  /// that feeds this straight into `resizeForDevice()`/`resize()` gets the
  /// same defaults those primitives already ship with, rather than a
  /// null/crash path.
  Future<({String tier, int cores, int memoryClassMb, bool isLowRamDevice})>
      getDeviceCapabilityProfile() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        ChannelMethods.getDeviceCapabilityProfile,
      );
      return (
        tier: result?['tier'] as String? ?? 'MEDIUM',
        cores: result?['cores'] as int? ?? 4,
        memoryClassMb: result?['memoryClassMb'] as int? ?? 128,
        isLowRamDevice: result?['isLowRamDevice'] as bool? ?? false,
      );
    } catch (e) {
      _logSwallowed('getDeviceCapabilityProfile', e);
      return (tier: 'MEDIUM', cores: 4, memoryClassMb: 128, isLowRamDevice: false);
    }
  }

  Future<bool> hasAllFilesAccess() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        ChannelMethods.hasAllFilesAccess,
      );
      return result ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<bool> requestAllFilesAccess() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        ChannelMethods.requestAllFilesAccess,
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<int?> getUsbDeviceCapacity(String deviceName) async {
    try {
      final result = await _channel.invokeMethod<int>(
        ChannelMethods.getUsbDeviceCapacity,
        {'deviceName': deviceName},
      );
      return result;
    } on PlatformException catch (e) {
      _logSwallowed('getUsbDeviceCapacity', e);
      return null;
    }
  }

  Future<bool> createUsbContainer({
    required String deviceName,
    required int sizeBytes,
    required String password,
    required int pim,
    required String fileSystem,
    int containerFormat = 0,
    required int cipherId,
    required int hashId,
    required List<String> keyfilePaths,
    String partitionScheme = 'mbr',
    bool quickFormat = false,
    bool createHiddenVolume = false,
    String? hiddenPassword,
    String? hiddenFileSystem,
    int? hiddenSizeBytes,
    List<String>? hiddenKeyfilePaths,
    int? hiddenPim,
    int? hiddenCipherId,
    int? hiddenHashId,
  }) async {
    try {
      final success = await _channel
          .invokeMethod<bool>(ChannelMethods.createUsbContainer, {
        'deviceName': deviceName,
        'sizeBytes': sizeBytes,
        'password': password,
        'pim': pim,
        'fileSystem': fileSystem,
        'containerFormat': containerFormat,
        'cipherId': cipherId,
        'hashId': hashId,
        'keyfilePaths': keyfilePaths,
        'partitionScheme': partitionScheme,
        'quickFormat': quickFormat,
        'createHiddenVolume': createHiddenVolume,
        'hiddenPassword': hiddenPassword,
        'hiddenFileSystem': hiddenFileSystem,
        'hiddenSizeBytes': hiddenSizeBytes,
        'hiddenKeyfilePaths': hiddenKeyfilePaths ?? [],
        'hiddenPim': hiddenPim,
        'hiddenCipherId': hiddenCipherId,
        'hiddenHashId': hiddenHashId,
      });
      return success ?? false;
    } catch (e) {
      _logSwallowed('createUsbContainer', e);
      return false;
    }
  }

  Future<bool> changeContainerPassword({
    required String uri,
    required String oldPassword,
    required String newPassword,
    int oldPim = 0,
    int newPim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<String>? oldKeyfilePaths,
    List<String>? newKeyfilePaths,
  }) async {
    try {
      final success = await _channel
          .invokeMethod<bool>(ChannelMethods.changeContainerPassword, {
        'uri': uri,
        'oldPassword': oldPassword,
        'newPassword': newPassword,
        'oldPim': oldPim,
        'newPim': newPim,
        'cipherId': cipherId,
        'hashId': hashId,
        'oldKeyfilePaths': oldKeyfilePaths ?? [],
        'newKeyfilePaths': newKeyfilePaths ?? [],
      });
      return success ?? false;
    } catch (e) {
      _logSwallowed('changeContainerPassword', e);
      return false;
    }
  }

  Future<({String uri, String displayName})?> pickContainer() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.pickContainer,
    );
    if (raw == null) return null;
    return (
      uri: raw['uri'] as String,
      displayName: raw['displayName'] as String,
    );
  }

  /// Opens a SAF file picker filtered to `.zip` files, for the decoy
  /// Archive Explorer screen's "Open archive…" action. Returns the real
  /// filesystem path (not a content:// URI) plus a display name, or null
  /// if the user cancelled.
  ///
  /// [path] can still be null even on a non-cancelled pick, if the chosen
  /// document couldn't be resolved to a raw path (see
  /// `VaultPickerHandlers.handlePickArchiveFile`) -- callers should treat
  /// that the same as a failed open.
  Future<({String? path, String displayName})?> pickArchiveFile() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.pickArchiveFile,
    );
    if (raw == null) return null;
    return (
      path: raw['path'] as String?,
      displayName: raw['displayName'] as String,
    );
  }

  /// Opens a SAF folder picker (`ACTION_OPEN_DOCUMENT_TREE`) so the user
  /// can choose where an archive gets extracted to, instead of the
  /// default Download/Extracted location. Same raw-path contract as
  /// [pickArchiveFile].
  Future<({String? path, String displayName})?> pickExtractFolder() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.pickExtractFolder,
    );
    if (raw == null) return null;
    return (
      path: raw['path'] as String?,
      displayName: raw['displayName'] as String,
    );
  }

  Future<List<KeyfileRef>> pickKeyfiles() async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.pickKeyfiles,
    );
    if (raw == null) return [];
    return raw
        .cast<Map<Object?, Object?>>()
        .map((m) => (
              uri: m['uri'] as String,
              displayName: m['displayName'] as String,
            ))
        .toList();
  }

  Future<({String uri, String displayName, bool looksLikeVault, String? format})?> pickCryptomatorVault() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(ChannelMethods.pickCryptomatorVault);
      if (res == null) return null;
      return (
        uri: res['uri'] as String,
        displayName: res['displayName'] as String,
        looksLikeVault: res['looksLikeVault'] as bool? ?? false,
        format: res['format'] as String?,
      );
    } catch (e) {
      _logSwallowed('pickCryptomatorVault', e);
      return null;
    }
  }

  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockCryptomatorVault(
    String filePath,
    String password, {
    String? displayName,
    bool documentProvider = false,
    List<String> autoMountFolders = const [],
    bool readOnly = false,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>(ChannelMethods.unlockCryptomatorVault, {
          'filePath': filePath,
          'password': password,
          'displayName': displayName,
          'documentProvider': documentProvider,
          'autoMountFolders': autoMountFolders,
          'readOnly': readOnly,
        });
    if (raw == null) return null;
    
    final files = (raw['files'] as List<Object?>).cast<String>();
    
    return (
      volId: raw['volId'] as int,
      files: files,
      matchedCipherId: raw['matchedCipherId'] as int? ?? 255,
      matchedHashId: raw['matchedHashId'] as int? ?? 255,
      containerFormat: raw['containerFormat'] as String? ?? 'cryptomator',
    );
  }

  Future<bool> createCryptomatorVault(String folderUri, String password) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.createCryptomatorVault,
        {'filePath': folderUri, 'password': password},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('createCryptomatorVault', e);
      return false;
    }
  }

  Future<({String uri, String displayName, bool looksLikeVault, String? format})?> pickGocryptfsVault() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(ChannelMethods.pickGocryptfsVault);
      if (res == null) return null;
      return (
        uri: res['uri'] as String,
        displayName: res['displayName'] as String,
        looksLikeVault: res['looksLikeVault'] as bool? ?? false,
        format: res['format'] as String?,
      );
    } catch (e) {
      _logSwallowed('pickGocryptfsVault', e);
      return null;
    }
  }

  Future<bool> isGocryptfsVault(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelMethods.isGocryptfsVault,
        {'uri': uri},
      );
      return result ?? false;
    } catch (e) {
      _logSwallowed('isGocryptfsVault', e);
      return false;
    }
  }

  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockGocryptfsVault(
    String filePath,
    String password, {
    String? displayName,
    bool documentProvider = false,
    List<String> autoMountFolders = const [],
    bool readOnly = false,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>(ChannelMethods.unlockGocryptfsVault, {
          'filePath': filePath,
          'password': password,
          'displayName': displayName,
          'documentProvider': documentProvider,
          'autoMountFolders': autoMountFolders,
          'readOnly': readOnly,
        });
    if (raw == null) return null;
    
    final files = (raw['files'] as List<Object?>).cast<String>();
    
    return (
      volId: raw['volId'] as int,
      files: files,
      matchedCipherId: raw['matchedCipherId'] as int? ?? 255,
      matchedHashId: raw['matchedHashId'] as int? ?? 255,
      containerFormat: raw['containerFormat'] as String? ?? 'gocryptfs',
    );
  }

  Future<bool> createGocryptfsVault(String folderUri, String password) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.createGocryptfsVault,
        {'filePath': folderUri, 'password': password},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('createGocryptfsVault', e);
      return false;
    }
  }

  Future<({String uri, String displayName, bool looksLikeVault, String? format})?> pickCryfsVault() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(ChannelMethods.pickCryfsVault);
      if (res == null) return null;
      return (
        uri: res['uri'] as String,
        displayName: res['displayName'] as String,
        looksLikeVault: res['looksLikeVault'] as bool? ?? false,
        format: res['format'] as String?,
      );
    } catch (e) {
      _logSwallowed('pickCryfsVault', e);
      return null;
    }
  }

  Future<bool> isCryfsVault(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelMethods.isCryfsVault,
        {'uri': uri},
      );
      return result ?? false;
    } catch (e) {
      _logSwallowed('isCryfsVault', e);
      return false;
    }
  }

  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockCryfsVault(
    String filePath,
    String password, {
    String? displayName,
    bool documentProvider = false,
    List<String> autoMountFolders = const [],
    bool readOnly = false,
    Uint8List? preservedKey,
    bool cacheDerivedKey = false,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>(ChannelMethods.unlockCryfsVault, {
          'filePath': filePath,
          'password': password,
          'displayName': displayName,
          'documentProvider': documentProvider,
          'autoMountFolders': autoMountFolders,
          'readOnly': readOnly,
          if (preservedKey != null) 'preservedKey': base64Encode(preservedKey),
          'cacheDerivedKey': cacheDerivedKey,
        });
    if (raw == null) return null;
    
    final files = (raw['files'] as List<Object?>).cast<String>();
    
    return (
      volId: raw['volId'] as int,
      files: files,
      matchedCipherId: raw['matchedCipherId'] as int? ?? 255,
      matchedHashId: raw['matchedHashId'] as int? ?? 255,
      containerFormat: raw['containerFormat'] as String? ?? 'cryfs',
    );
  }

  Future<bool> createCryfsVault(String folderUri, String password) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.createCryfsVault,
        {'filePath': folderUri, 'password': password},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('createCryfsVault', e);
      return false;
    }
  }

  Future<bool> finishWriteIfCryptomator(
    MountedContainer container,
    String fileName,
  ) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.finishWriteIfCryptomator,
        {'volId': container.volId, 'path': fileName},
      );
      return success ?? true;
    } catch (e) {
      _logSwallowed('finishWriteIfCryptomator', e);
      return true;
    }
  }

  Future<void> cancelUnlock(int volId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelUnlock, {'volId': volId});
    } catch (e) {
      _logSwallowed('cancelUnlock', e, expected: true);
    }
  }

  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockContainer(
    String filePath,
    String password,
    int pim, {
    String? displayName,
    bool documentProvider = false,
    List<String> autoMountFolders = const [],
    int? cipherId,
    int? hashId,
    Uint8List? preservedKey,
    bool cacheDerivedKey = false,
    List<String>? keyfilePaths,
    bool readOnly = false,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>(ChannelMethods.unlockContainer, {
          'filePath': filePath,
          'password': password,
          'pim': pim,
          'displayName': displayName,
          'documentProvider': documentProvider,
          'autoMountFolders': autoMountFolders,
          'cipherId': cipherId ?? 255,
          'hashId': hashId ?? 255,
          if (preservedKey != null) 'preservedKey': base64Encode(preservedKey),
          'cacheDerivedKey': cacheDerivedKey,
          if (keyfilePaths != null && keyfilePaths.isNotEmpty)
            'keyfilePaths': keyfilePaths,
          'readOnly': readOnly,
        });

    if (raw == null) return null;

    final volId = raw['volId'] as int;
    final files = (raw['files'] as List<Object?>).cast<String>();

    return (
      volId: volId,
      files: files,
      matchedCipherId: raw['matchedCipherId'] as int? ?? 255,
      matchedHashId: raw['matchedHashId'] as int? ?? 255,
      containerFormat: raw['containerFormat'] as String? ?? 'veracrypt',
    );
  }

  Future<bool> documentExists(String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelMethods.documentExists,
        {'filePath': filePath},
      );
      return result ?? false;
    } catch (e) {
      _logSwallowed('documentExists', e, expected: true);
      return true;
    }
  }

  void warmContainer(String filePath) {
    _channel
        .invokeMethod(ChannelMethods.warmContainer, {'filePath': filePath})
        .catchError((e) => _logSwallowed('warmContainer', e, expected: true));
  }

  Future<List<UsbDeviceInfo>> listUsbDevices() async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.listUsbDevices,
    );
    if (raw == null) return [];

    return raw
        .cast<Map<Object?, Object?>>()
        .map((m) => UsbDeviceInfo(
              deviceName: m['deviceName'] as String,
              productName: m['productName'] as String,
              hasPermission: m['hasPermission'] as bool,
            ))
        .toList();
  }

  Future<bool> requestUsbPermission(String deviceName) async {
    try {
      final granted = await _channel.invokeMethod<bool>(
        ChannelMethods.requestUsbPermission,
        {'deviceName': deviceName},
      );
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockUsbContainer(
    String deviceName,
    String password,
    int pim, {
    String? displayName,
    bool documentProvider = false,
    List<String> autoMountFolders = const [],
    int? cipherId,
    int? hashId,
    Uint8List? preservedKey,
    bool cacheDerivedKey = false,
    List<String>? keyfilePaths,
    bool readOnly = false,
  }) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.unlockUsbContainer,
      {
        'deviceName': deviceName,
        'password': password,
        'pim': pim,
        'displayName': displayName,
        'documentProvider': documentProvider,
        'autoMountFolders': autoMountFolders,
        'cipherId': cipherId ?? 255,
        'hashId': hashId ?? 255,
        if (preservedKey != null) 'preservedKey': base64Encode(preservedKey),
        'cacheDerivedKey': cacheDerivedKey,
        if (keyfilePaths != null && keyfilePaths.isNotEmpty)
          'keyfilePaths': keyfilePaths,
        'readOnly': readOnly,
      },
    );

    if (raw == null) return null;

    final volId = raw['volId'] as int;
    final files = (raw['files'] as List<Object?>).cast<String>();

    return (
      volId: volId,
      files: files,
      matchedCipherId: raw['matchedCipherId'] as int? ?? 255,
      matchedHashId: raw['matchedHashId'] as int? ?? 255,
      containerFormat: raw['containerFormat'] as String? ?? 'veracrypt',
    );
  }

  Future<bool> lockContainer(String filePath) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.lockContainer,
      {'filePath': filePath},
    );
    return result ?? false;
  }

  Future<bool> updateContainerSettings(
    String filePath,
    String displayName,
    bool documentProvider,
  ) async {
    final result = await _channel
        .invokeMethod<bool>(ChannelMethods.updateContainerSettings, {
          'filePath': filePath,
          'displayName': displayName,
          'documentProvider': documentProvider,
        });
    return result ?? false;
  }

  /// Exposes [path] (relative to the container root) as its own SAF root.
  /// Requires the container to already be unlocked.
  Future<bool> mountContainerFolder(
    String filePath,
    String path, {
    String? displayName,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelMethods.mountContainerFolder,
        {'filePath': filePath, 'path': path, 'displayName': displayName},
      );
      return result ?? false;
    } catch (e) {
      _logSwallowed('mountContainerFolder', e);
      return false;
    }
  }

  /// Removes the SAF root created by [mountContainerFolder]. The container
  /// itself stays unlocked.
  Future<bool> unmountContainerFolder(String filePath, String path) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelMethods.unmountContainerFolder,
        {'filePath': filePath, 'path': path},
      );
      return result ?? false;
    } catch (e) {
      _logSwallowed('unmountContainerFolder', e);
      return false;
    }
  }

  /// Paths (relative to the container root) currently exposed as their own
  /// SAF root for this container's active session.
  Future<List<String>> getMountedContainerFolders(String filePath) async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        ChannelMethods.getMountedContainerFolders,
        {'filePath': filePath},
      );
      return (result ?? const []).cast<String>();
    } catch (e) {
      _logSwallowed('getMountedContainerFolders', e);
      return const [];
    }
  }
}