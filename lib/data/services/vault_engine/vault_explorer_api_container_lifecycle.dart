part of 'vault_explorer_api.dart';

/// Container/vault creation, unlocking, and management -- VeraCrypt/LUKS
/// file and USB containers, Cryptomator/gocryptfs directory vaults, and the
/// USB device listing/permission calls those creation flows depend on.
/// Mirrors the native-side `ContainerEngine` router (see the Kotlin bridge
/// layer) on the Dart side of the platform channel.
mixin _ContainerLifecycleOps {
  // ── Container lifecycle ───────────────────────────────────────────────────

  /// [containerFormat]: 0 = VeraCrypt, 1 = LUKS1, 2 = LUKS2 (see
  /// [CreateFormat] in crypto_algorithms.dart) — matches the native
  /// ContainerFormat ordinal.
  ///
  /// [keyfilePaths]: for VeraCrypt, keyfiles mix ADDITIVELY into
  /// [password] (an empty password with keyfiles alone is valid, matching
  /// real VeraCrypt). For LUKS, a keyfile REPLACES [password] entirely
  /// (matching real `cryptsetup --key-file`) and only the first keyfile is
  /// used.
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

  /// Returns usable capacity in bytes (device capacity minus the MBR
  /// partition offset), or null on failure. Requires [deviceName] to
  /// already have USB permission granted.
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

  /// Changes the password (and optionally PIM) of a VeraCrypt container.
  /// For LUKS containers, password change is not supported in-app — the user
  /// should use `cryptsetup luksChangeKey` on a Linux machine.
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

  /// Opens a multi-select document picker for keyfiles. Returns an empty
  /// list if the user cancels.
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

  /// Opens a folder picker (ACTION_OPEN_DOCUMENT_TREE) for selecting a
  /// Cryptomator vault or directory vault.
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

  /// Unlocks a Cryptomator vault.
  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockCryptomatorVault(
    String filePath,
    String password, {
    String? displayName,
    bool documentProvider = false,
    bool readOnly = false,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>(ChannelMethods.unlockCryptomatorVault, {
          'filePath': filePath,
          'password': password,
          'displayName': displayName,
          'documentProvider': documentProvider,
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

  /// Creates a new Cryptomator vault in an empty folder.
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

  /// Opens a folder picker for selecting a Gocryptfs vault.
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

  /// Unlocks a Gocryptfs vault.
  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockGocryptfsVault(
    String filePath,
    String password, {
    String? displayName,
    bool documentProvider = false,
    bool readOnly = false,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>(ChannelMethods.unlockGocryptfsVault, {
          'filePath': filePath,
          'password': password,
          'displayName': displayName,
          'documentProvider': documentProvider,
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

  /// Creates a new Gocryptfs vault in an empty folder.
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

  /// Opens a folder picker for selecting a CryFS vault.
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

  /// Unlocks a CryFS vault.
  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockCryfsVault(
    String filePath,
    String password, {
    String? displayName,
    bool documentProvider = false,
    bool readOnly = false,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>(ChannelMethods.unlockCryfsVault, {
          'filePath': filePath,
          'password': password,
          'displayName': displayName,
          'documentProvider': documentProvider,
          'readOnly': readOnly,
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

  /// Creates a new CryFS vault in an empty folder.
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

  /// Must be called once after the final [writeFileChunk] call in a
  /// sequence for a given [fileName] on Cryptomator/gocryptfs/CryFS vaults.
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

  /// Asks native to abort the in-flight unlock for [volId].
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

  /// Checks whether the document/file at [filePath] can currently be resolved.
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

  /// Speculatively warms [filePath] for a subsequent [unlockContainer] call.
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
}