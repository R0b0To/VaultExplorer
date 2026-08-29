// Extracted from vault_explorer_api_container_lifecycle.dart (old
// _ContainerLifecycleOps mixin) as part of the Riverpod migration, Phase 2.
// The two permission-await calls that used to go through
// VaultExplorerApi's static completers now go through the injected
// VaultEngineEvents instance (see lib/core/api/vault_engine_events.dart).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';
import 'package:vaultexplorer/features/camera/active_recording_registry.dart';

import 'vault_engine_events.dart';
import 'vault_engine_types.dart';

class VaultLifecycleApi {
  final MethodChannel _channel;
  final VaultEngineEvents _events;
  const VaultLifecycleApi(this._channel, this._events);

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
    } on PlatformException catch (e) {
      // Most native failures here are swallowed below (the caller only
      // needs a bool). INSUFFICIENT_SPACE is the one exception: it carries
      // neededBytes/availableBytes in `details` that only the UI can turn
      // into a useful message, so let it propagate instead of flattening
      // it to `false`.
      if (e.code == 'INSUFFICIENT_SPACE') rethrow;
      logSwallowed('createContainer', e);
      return false;
    } catch (e) {
      logSwallowed('createContainer', e);
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
      logSwallowed('getDeviceCapabilityProfile', e);
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

  /// Requests broad storage access, appropriate to the running Android
  /// version:
  /// - API 30+ (R): opens system Settings for the user to grant All Files
  ///   Access manually -- there's no synchronous callback for this, so the
  ///   returned bool only reflects whether the Settings screen was opened.
  ///   Callers should re-check [hasAllFilesAccess] on resume.
  /// - API 26-29 (O-Q): fires the standard runtime permission dialog and
  ///   waits for the user's answer, returning the actual grant result --
  ///   unless [openSettings] is true, in which case this opens Settings
  ///   instead (needed to *revoke* an already-granted permission, since
  ///   apps can't drop their own runtime grants programmatically).
  /// - Below API 26: no-op, returns true (nothing to request).
  Future<bool> requestAllFilesAccess({bool openSettings = false}) async {
    final sdkInt = await getAndroidSdkInt();
    if (sdkInt >= 30 || openSettings) {
      try {
        final bool? result = await _channel.invokeMethod<bool>(
          ChannelMethods.requestAllFilesAccess,
          {'openSettings': openSettings},
        );
        return result ?? false;
      } catch (e) {
        return false;
      }
    }
    if (sdkInt >= 26) {
      final resultFuture = _events.awaitStoragePermissionResult();
      try {
        await _channel.invokeMethod<bool>(ChannelMethods.requestAllFilesAccess);
      } catch (e) {
        return false;
      }
      try {
        return await resultFuture.timeout(const Duration(seconds: 60));
      } on TimeoutException {
        // The user backgrounded the app / dismissed the dialog without it
        // resolving -- don't hang forever.
        return false;
      }
    }
    return true;
  }

  /// Requests `POST_NOTIFICATIONS`, needed on API 33+ before the "keep
  /// vaults running in background" foreground service's ongoing
  /// notification can actually be shown -- see
  /// SystemPermissionHandlers.handleRequestNotificationPermission for why
  /// this is always safe to call, even when already granted or on a
  /// version where the permission doesn't apply. Below API 33 this is a
  /// no-op that returns true without touching the channel.
  Future<bool> requestNotificationPermission() async {
    final sdkInt = await getAndroidSdkInt();
    if (sdkInt < 33) return true;
    final resultFuture = _events.awaitNotificationPermissionResult();
    try {
      await _channel.invokeMethod<bool>(
        ChannelMethods.requestNotificationPermission,
      );
    } catch (e) {
      return false;
    }
    try {
      return await resultFuture.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      // The user backgrounded the app / dismissed the dialog without it
      // resolving -- don't hang forever.
      return false;
    }
  }

  /// Android API level (`Build.VERSION.SDK_INT`) of the running device.
  ///
  /// Used to hide settings that don't apply on older Android versions
  /// (e.g. Material You needs API 31+, the "fast storage access" /
  /// All Files Access toggle needs API 30+). Falls back to a high number
  /// on any channel failure so callers default to *showing* the option
  /// rather than hiding something that might actually be relevant.
  Future<int> getAndroidSdkInt() async {
    try {
      final int? result = await _channel.invokeMethod<int>(
        ChannelMethods.getAndroidSdkInt,
      );
      return result ?? 34;
    } catch (e) {
      logSwallowed('getAndroidSdkInt', e);
      return 34;
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
      logSwallowed('getUsbDeviceCapacity', e);
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
      logSwallowed('createUsbContainer', e);
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
      logSwallowed('changeContainerPassword', e);
      return false;
    }
  }

  /// Unlike [changeContainerPassword], failures are NOT swallowed to
  /// `false` -- a wrong [oldPassword] surfaces as a `PlatformException`
  /// with code `AUTH_FAIL` (message pre-formatted for display), matching
  /// the folder-vault change-password methods' error contract (see
  /// [changeCryptomatorVaultPassword]'s doc comment), since LUKS's native
  /// layer distinguishes wrong-password from other failures and that's
  /// worth surfacing rather than a generic message. No PIM/cipherId/
  /// hashId params: LUKS has neither concept.
  Future<bool> changeLuksContainerPassword({
    required String uri,
    required String oldPassword,
    required String newPassword,
    List<String>? oldKeyfilePaths,
    List<String>? newKeyfilePaths,
  }) async {
    final success = await _channel
        .invokeMethod<bool>(ChannelMethods.changeLuksContainerPassword, {
      'uri': uri,
      'oldPassword': oldPassword,
      'newPassword': newPassword,
      'oldKeyfilePaths': oldKeyfilePaths ?? [],
      'newKeyfilePaths': newKeyfilePaths ?? [],
    });
    return success ?? false;
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
  /// [pickArchiveFile], plus [treeUri]: the raw `path` is only a
  /// best-effort guess (native returns one even without "All files
  /// access" granted), so callers that *write* into this folder --
  /// [_SplitJoinOps.splitContainer]/[_SplitJoinOps.joinContainer] in
  /// particular -- pass [treeUri] along too, letting the native side fall
  /// back to a SAF write when the raw path isn't actually writable. See
  /// `SplitJoinHandlers.kt`'s `resolveDestFolder` doc comment.
  Future<({String? path, String displayName, String? treeUri})?> pickExtractFolder() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.pickExtractFolder,
    );
    if (raw == null) return null;
    return (
      path: raw['path'] as String?,
      displayName: raw['displayName'] as String,
      treeUri: raw['treeUri'] as String?,
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

  /// Multi-select `ACTION_OPEN_DOCUMENT` picker for the standalone
  /// encrypt/decrypt file tool's batch mode -- same native shape as
  /// [pickKeyfiles] (list of uri/displayName pairs), just a separate
  /// channel method so the two pickers' intents can diverge later (e.g.
  /// filtering decrypt's picker to a specific extension) without one
  /// affecting the other.
  Future<List<KeyfileRef>> pickCryptoFiles() async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.pickCryptoFiles,
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
      logSwallowed('pickCryptomatorVault', e);
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
      logSwallowed('createCryptomatorVault', e);
      return false;
    }
  }

  /// Rewraps a Cryptomator vault's masterkey under [newPassword]. Unlike
  /// [createCryptomatorVault], failures are deliberately NOT swallowed to
  /// `false` -- a wrong [oldPassword] surfaces as a `PlatformException`
  /// with code `AUTH_FAIL` (message pre-formatted for display), matching
  /// [unlockCryptomatorVault]'s error contract, so callers can show the
  /// specific reason rather than a generic failure message.
  Future<bool> changeCryptomatorVaultPassword(
    String folderUri,
    String oldPassword,
    String newPassword,
  ) async {
    final success = await _channel.invokeMethod<bool>(
      ChannelMethods.changeCryptomatorVaultPassword,
      {'filePath': folderUri, 'oldPassword': oldPassword, 'newPassword': newPassword},
    );
    return success ?? false;
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
      logSwallowed('pickGocryptfsVault', e);
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
      logSwallowed('isGocryptfsVault', e);
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

  /// [cipher]: 'aes-256-gcm' (default, GCMIV128) or 'xchacha20-poly1305'
  /// (gocryptfs v2.2+, XChaCha20Poly1305) -- selects the FeatureFlags this
  /// new vault's gocryptfs.conf is written with. Unrecognized values fall
  /// back to 'aes-256-gcm' on the native side.
  Future<bool> createGocryptfsVault(
    String folderUri,
    String password, {
    String cipher = 'aes-256-gcm',
  }) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.createGocryptfsVault,
        {'filePath': folderUri, 'password': password, 'cipher': cipher},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('createGocryptfsVault', e);
      return false;
    }
  }

  /// Rewraps a gocryptfs vault's masterkey under [newPassword]. See
  /// [changeCryptomatorVaultPassword]'s doc comment for the error contract
  /// (errors propagate rather than collapsing to `false`).
  Future<bool> changeGocryptfsVaultPassword(
    String folderUri,
    String oldPassword,
    String newPassword,
  ) async {
    final success = await _channel.invokeMethod<bool>(
      ChannelMethods.changeGocryptfsVaultPassword,
      {'filePath': folderUri, 'oldPassword': oldPassword, 'newPassword': newPassword},
    );
    return success ?? false;
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
      logSwallowed('pickCryfsVault', e);
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
      logSwallowed('isCryfsVault', e);
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

  /// [cipher]: 'xchacha20-poly1305' (default for CryFS 1.0.x/0.11.x) or
  /// 'aes-256-gcm' (CryFS 0.10.x default, still supported). Unrecognized
  /// values fall back to 'xchacha20-poly1305' on the native side.
  ///
  /// [blockSize]: on-disk block size in bytes, mirroring CryFS CLI's
  /// `--blocksize` option. Defaults to 32768 (32 KiB), CryFS's own default.
  /// Non-positive values fall back to the default on the native side.
  Future<bool> createCryfsVault(
    String folderUri,
    String password, {
    String cipher = 'xchacha20-poly1305',
    int blockSize = 32 * 1024,
  }) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.createCryfsVault,
        {
          'filePath': folderUri,
          'password': password,
          'cipher': cipher,
          'blockSize': blockSize,
        },
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('createCryfsVault', e);
      return false;
    }
  }

  /// Rewraps a CryFS vault's config under [newPassword]. See
  /// [changeCryptomatorVaultPassword]'s doc comment for the error contract
  /// (errors propagate rather than collapsing to `false`).
  Future<bool> changeCryfsVaultPassword(
    String folderUri,
    String oldPassword,
    String newPassword,
  ) async {
    final success = await _channel.invokeMethod<bool>(
      ChannelMethods.changeCryfsVaultPassword,
      {'filePath': folderUri, 'oldPassword': oldPassword, 'newPassword': newPassword},
    );
    return success ?? false;
  }

  /// Commits a buffered [VaultExplorerApi.writeFileChunk] sequence for
  /// [fileName]. Despite the old name this method used to have, it is not
  /// Cryptomator-specific: it commits for whichever container-backed
  /// engine is mounted (Cryptomator, gocryptfs, or CryFS) and is a
  /// documented no-op for VeraCrypt/LUKS/BitLocker, so it's safe to call
  /// unconditionally after any writeFileChunk() sequence completes.
  Future<bool> finishWrite(
    MountedContainer container,
    String fileName,
  ) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.finishWrite,
        {'volId': container.volId, 'path': fileName},
      );
      return success ?? true;
    } catch (e) {
      logSwallowed('finishWrite', e);
      return true;
    }
  }

  Future<void> cancelUnlock(int volId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelUnlock, {'volId': volId});
    } catch (e) {
      logSwallowed('cancelUnlock', e, expected: true);
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
    bool protectHiddenVolume = false,
    String? hiddenVolumePassword,
    int hiddenVolumePim = 0,
    int? hiddenVolumeCipherId,
    int? hiddenVolumeHashId,
    List<String>? hiddenVolumeKeyfilePaths,
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
          'protectHiddenVolume': protectHiddenVolume,
          if (protectHiddenVolume) ...{
            'hiddenVolumePassword': hiddenVolumePassword ?? '',
            'hiddenVolumePim': hiddenVolumePim,
            'hiddenVolumeCipherId': hiddenVolumeCipherId ?? 255,
            'hiddenVolumeHashId': hiddenVolumeHashId ?? 255,
            if (hiddenVolumeKeyfilePaths != null &&
                hiddenVolumeKeyfilePaths.isNotEmpty)
              'hiddenVolumeKeyfilePaths': hiddenVolumeKeyfilePaths,
          },
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

  /// Mounts a split container directly from its first on-disk part
  /// (`<name>.001`/`<name>.part1`), without ever joining the sequence back
  /// into a single file first -- see `SplitContainerMountHandlers` (Kotlin)
  /// for how the parts get exposed as one seekable file under the hood.
  /// Args otherwise mirror [unlockContainer] (password/pim/hidden-volume/
  /// keyfiles all work the same way); [firstPartUri] replaces [filePath] as
  /// the source identifier since there's no single backing file. [partCount]
  /// in the result is purely informational (how many `.NNN`/`.partN` files
  /// were found and mounted), for UI that wants to show it.
  Future<
    ({
      int volId,
      List<String> files,
      int matchedCipherId,
      int matchedHashId,
      String containerFormat,
      int partCount,
    })?
  >
  unlockSplitContainer(
    String firstPartUri,
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
    bool protectHiddenVolume = false,
    String? hiddenVolumePassword,
    int hiddenVolumePim = 0,
    int? hiddenVolumeCipherId,
    int? hiddenVolumeHashId,
    List<String>? hiddenVolumeKeyfilePaths,
  }) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.unlockSplitContainer,
      {
        'firstPartUri': firstPartUri,
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
        'protectHiddenVolume': protectHiddenVolume,
        if (protectHiddenVolume) ...{
          'hiddenVolumePassword': hiddenVolumePassword ?? '',
          'hiddenVolumePim': hiddenVolumePim,
          'hiddenVolumeCipherId': hiddenVolumeCipherId ?? 255,
          'hiddenVolumeHashId': hiddenVolumeHashId ?? 255,
          if (hiddenVolumeKeyfilePaths != null &&
              hiddenVolumeKeyfilePaths.isNotEmpty)
            'hiddenVolumeKeyfilePaths': hiddenVolumeKeyfilePaths,
        },
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
      partCount: raw['partCount'] as int? ?? 1,
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
      logSwallowed('documentExists', e, expected: true);
      return true;
    }
  }

  void warmContainer(String filePath) {
    _channel
        .invokeMethod(ChannelMethods.warmContainer, {'filePath': filePath})
        .catchError((e) => logSwallowed('warmContainer', e, expected: true));
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
    bool protectHiddenVolume = false,
    String? hiddenVolumePassword,
    int hiddenVolumePim = 0,
    int? hiddenVolumeCipherId,
    int? hiddenVolumeHashId,
    List<String>? hiddenVolumeKeyfilePaths,
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
        'protectHiddenVolume': protectHiddenVolume,
        if (protectHiddenVolume) ...{
          'hiddenVolumePassword': hiddenVolumePassword ?? '',
          'hiddenVolumePim': hiddenVolumePim,
          'hiddenVolumeCipherId': hiddenVolumeCipherId ?? 255,
          'hiddenVolumeHashId': hiddenVolumeHashId ?? 255,
          if (hiddenVolumeKeyfilePaths != null &&
              hiddenVolumeKeyfilePaths.isNotEmpty)
            'hiddenVolumeKeyfilePaths': hiddenVolumeKeyfilePaths,
        },
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
    // If a video is currently being recorded into this container (whether
    // the camera screen is in the foreground or the recording is
    // continuing in the background via VaultCameraRecordingService),
    // finish and save it first. Otherwise the encoder gets torn down
    // mid-write the moment this locks/unmounts the container out from
    // under it -- see ActiveRecordingRegistry for why this is the one
    // place that check belongs, rather than in every individual caller.
    await ActiveRecordingRegistry.instance.stopIfActive(filePath);
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.lockContainer,
      {'filePath': filePath},
    );
    return result ?? false;
  }

  /// Starts or stops the "keep vaults running in background" foreground
  /// service. Native re-derives whether anything is actually unlocked
  /// itself, so it's safe (and cheap) to call this every time [enabled]
  /// or the set of mounted containers changes -- see
  /// BackgroundServiceHandlers.kt.
  Future<void> syncBackgroundService({required bool enabled}) async {
    try {
      await _channel.invokeMethod(
        ChannelMethods.syncBackgroundService,
        {'enabled': enabled},
      );
    } catch (e) {
      logSwallowed('syncBackgroundService', e);
    }
  }

  Future<void> updateBackgroundServiceProgress({
    required bool hasActive,
    String? title,
    String? text,
    int? progress,
    int max = 1000,
    bool indeterminate = false,
  }) async {
    try {
      await _channel.invokeMethod(
        ChannelMethods.updateBackgroundServiceProgress,
        {
          'hasActive': hasActive,
          if (title != null) 'title': title,
          if (text != null) 'text': text,
          if (progress != null) 'progress': progress,
          'max': max,
          'indeterminate': indeterminate,
        },
      );
    } catch (e) {
      logSwallowed('updateBackgroundServiceProgress', e);
    }
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
      logSwallowed('mountContainerFolder', e);
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
      logSwallowed('unmountContainerFolder', e);
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
      logSwallowed('getMountedContainerFolders', e);
      return const [];
    }
  }
}