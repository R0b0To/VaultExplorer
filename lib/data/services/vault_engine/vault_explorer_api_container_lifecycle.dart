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
        ChannelMethods.HAS_ALL_FILES_ACCESS,
      );
      return result ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<bool> requestAllFilesAccess() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        ChannelMethods.REQUEST_ALL_FILES_ACCESS,
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
  /// list if the user cancels. Any file type is a valid keyfile (VeraCrypt
  /// keyfile mixing just hashes the raw bytes — a photo, an mp3, a random
  /// binary blob are all equally valid), so this doesn't filter by
  /// extension or mime type.
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
  /// Cryptomator vault — vaults are directory trees (vault.cryptomator +
  /// masterkey.cryptomator + d/), not single files, so this is distinct from
  /// [pickContainer]. [looksLikeVault] is a quick heuristic (checks for
  /// masterkey.cryptomator) the caller can use to warn the user immediately
  /// if they picked an unrelated folder, before asking for a password.
  Future<({String uri, String displayName, bool looksLikeVault})?> pickCryptomatorVault() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.pickCryptomatorVault,
    );
    if (raw == null) return null;
    return (
      uri: raw['uri'] as String,
      displayName: raw['displayName'] as String,
      looksLikeVault: raw['looksLikeVault'] as bool? ?? false,
    );
  }

  /// Unlocks a Cryptomator vault. Result shape matches [unlockContainer]
  /// exactly (containerFormat: 'cryptomator') so callers can treat the two
  /// uniformly once unlocked. matchedCipherId/matchedHashId are always 255
  /// (not applicable — Cryptomator's cipher suite is fixed per vault format,
  /// not user-selectable).
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

  /// Creates a new Cryptomator vault (always vault format 8 / SIV_GCM) in
  /// an empty folder the user already granted tree access to via
  /// [pickCryptomatorVault]. The vault is left locked afterward — the
  /// caller should unlock it explicitly via [unlockCryptomatorVault], same
  /// as [createContainer] leaves VeraCrypt/LUKS containers locked.
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

  /// Opens a folder picker (ACTION_OPEN_DOCUMENT_TREE) for selecting a
  /// Gocryptfs vault — vaults are directory trees (gocryptfs.conf +
  /// gocryptfs.diriv), not single files, so this is distinct from
  /// [pickContainer]. [looksLikeVault] is a quick heuristic the caller can
  /// use to warn the user immediately if they picked an unrelated folder,
  /// before asking for a password.
  Future<({String uri, String displayName, bool looksLikeVault})?> pickGocryptfsVault() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.pickGocryptfsVault,
    );
    if (raw == null) return null;
    return (
      uri: raw['uri'] as String,
      displayName: raw['displayName'] as String,
      looksLikeVault: raw['looksLikeVault'] as bool? ?? false,
    );
  }

  /// Unlocks a Gocryptfs vault. Result shape matches [unlockContainer]
  /// exactly (containerFormat: 'gocryptfs') so callers can treat the two
  /// uniformly once unlocked. matchedCipherId/matchedHashId are always 255
  /// (not applicable — Gocryptfs's cipher suite is fixed per vault format,
  /// not user-selectable).
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

  /// Creates a new Gocryptfs vault in an empty folder the user already
  /// granted tree access to via [pickGocryptfsVault]. The vault is left
  /// locked afterward — the caller should unlock it explicitly via
  /// [unlockGocryptfsVault].
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

  /// Opens a folder picker (ACTION_OPEN_DOCUMENT_TREE) for selecting a
  /// CryFS vault — vaults are directory trees (cryfs.config plus a flat,
  /// sharded pool of block files), not single files, so this is distinct
  /// from [pickContainer]. [looksLikeVault] is a quick heuristic the caller
  /// can use to warn the user immediately if they picked an unrelated
  /// folder, before asking for a password.
  Future<({String uri, String displayName, bool looksLikeVault})?> pickCryfsVault() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.pickCryfsVault,
    );
    if (raw == null) return null;
    return (
      uri: raw['uri'] as String,
      displayName: raw['displayName'] as String,
      looksLikeVault: raw['looksLikeVault'] as bool? ?? false,
    );
  }

  /// Unlocks a CryFS vault. Result shape matches [unlockContainer] exactly
  /// (containerFormat: 'cryfs') so callers can treat the two uniformly
  /// once unlocked. matchedCipherId/matchedHashId are always 255 (not
  /// applicable — CryFS's cipher suite is fixed per vault config, not
  /// user-selectable here).
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

  /// Creates a new CryFS vault in an empty folder the user already granted
  /// tree access to via [pickCryfsVault]. The vault is left locked
  /// afterward — the caller should unlock it explicitly via
  /// [unlockCryfsVault].
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
  /// sequence for a given [fileName], to flush Cryptomator's buffered final
  /// (possibly partial) chunk and materialize the file. Safe to call
  /// unconditionally for any container — it's a no-op for VeraCrypt/LUKS.
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

  /// Asks native to abort the in-flight unlock for [volId] (see
  /// [addUnlockStartedListener] for how the caller learns [volId] before the
  /// original [unlockContainer]/[unlockUsbContainer] call has resolved).
  ///
  /// Fire-and-forget and best-effort: this doesn't itself throw or resolve
  /// the pending unlock — that call will still complete on its own shortly
  /// after, but with a `PlatformException(code: 'CANCELLED')` instead of a
  /// result, once native notices the request. Safe to call more than once,
  /// or after the unlock has already finished.
  Future<void> cancelUnlock(int volId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelUnlock, {'volId': volId});
    } catch (e) {
      // Best-effort — the pending unlock call resolves on its own regardless.
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

  /// Checks whether the document/file at [filePath] (a content:// SAF uri
  /// or a plain file:// path) can currently be resolved — without
  /// attempting to unlock it. Returns false for a container living on
  /// removable storage that's been disconnected or a file that was moved
  /// or deleted, and also false if a previously-granted content:// SAF
  /// permission was revoked (e.g. after removing and re-inserting an SD
  /// card resets the grant).
  Future<bool> documentExists(String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelMethods.documentExists,
        {'filePath': filePath},
      );
      return result ?? false;
    } catch (e) {
      // Treat a failed check as "unknown", not "missing" — let the normal
      // unlock attempt surface the real error rather than blocking access
      // to a container that might actually be fine.
      _logSwallowed('documentExists', e, expected: true);
      return true;
    }
  }

  /// Speculatively warms [filePath] for a subsequent [unlockContainer]
  /// call: opens it read-only, reads a small prefix, closes it again.
  /// Fire-and-forget — no fd is held open, so there's nothing to cancel or
  /// clean up if the user backs out. Purely a latency optimization; on SAF
  /// providers this overlaps the binder round trip (and, for cloud-backed
  /// providers, the network fetch) with the time the user spends typing
  /// their password instead of paying it after they tap "Unlock."
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
