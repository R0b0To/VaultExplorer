import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

import 'vault_engine_types.dart';

/// One vault found in app storage.
class AppStorageVault {
  const AppStorageVault({
    required this.uri,
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
  });

  final String uri;
  final String name;
  final bool isDirectory;

  /// -1 unless sizes were asked for (a large folder vault takes a moment to add up).
  final int sizeBytes;
}

/// Free space and contents of app storage (the app's private vault folder).
class AppStorageInfo {
  const AppStorageInfo({
    required this.rootUri,
    required this.availableBytes,
    required this.vaults,
  });

  final String rootUri;
  final int availableBytes;
  final List<AppStorageVault> vaults;
}

/// Result of a verified copy made by the native side.
typedef VaultCopyResult = ({String uri, int bytes, int files});

/// Result of the finishing step of a move.
typedef VaultFinalizeResult = ({
  bool sourceDeleted,
  bool automationReset,
  String? reason,
});

/// Vaults that live in the app's private storage, and moving a vault in or out of it.
///
/// Kept apart from `VaultLifecycleApi` on purpose: that interface is implemented by the desktop
/// engine and by many test fakes, none of which have app storage.
///
/// Failures of the relocation calls surface as [PlatformException] with one of these codes:
/// `VAULT_UNLOCKED`, `UNSUPPORTED_SOURCE`, `SPLIT_UNSUPPORTED`, `NOT_A_VAULT_FOLDER`,
/// `DESTINATION_NOT_EMPTY`, `ALREADY_IN_APP_STORAGE`, `NOT_IN_APP_STORAGE`, `SOURCE_MISSING`,
/// `INSUFFICIENT_SPACE` (details: `neededBytes`, `availableBytes`), `VERIFY_FAILED`, `CANCELLED`,
/// `NO_PICKER`, `IO_ERROR`. `VaultRelocationGateway` maps them to `RelocationFailure`.
class VaultStorageApi {
  final MethodChannel _channel;
  const VaultStorageApi(this._channel);

  Future<AppStorageInfo> getAppStorageInfo({bool includeSizes = false}) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      ChannelMethods.getAppStorageInfo,
      {'includeSizes': includeSizes},
    );
    final vaults = <AppStorageVault>[];
    for (final raw in (result?['vaults'] as List<Object?>? ?? const [])) {
      final m = (raw as Map).cast<String, Object?>();
      vaults.add(
        AppStorageVault(
          uri: m['uri'] as String? ?? '',
          name: m['name'] as String? ?? '',
          isDirectory: m['isDirectory'] as bool? ?? false,
          sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? -1,
        ),
      );
    }
    return AppStorageInfo(
      rootUri: result?['rootUri'] as String? ?? '',
      availableBytes: (result?['availableBytes'] as num?)?.toInt() ?? 0,
      vaults: vaults,
    );
  }

  /// Creates a container file in app storage. Same arguments and result as `createContainer`, minus the
  /// file picker: the file is named after [displayName] inside the app's private vault folder.
  Future<({bool success, String? uri})> createAppStorageContainer({
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
    Uint8List? userEntropy,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        ChannelMethods.createAppStorageContainer,
        {
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
          'userEntropy': userEntropy,
        },
      );
      final success = result?['success'] as bool? ?? false;
      return (success: success, uri: success ? (result?['uri'] as String?) : null);
    } on PlatformException catch (e) {
      // As for createContainer: only INSUFFICIENT_SPACE carries details the UI can use.
      if (e.code == 'INSUFFICIENT_SPACE') rethrow;
      logSwallowed('createAppStorageContainer', e);
      return (success: false, uri: null);
    } catch (e) {
      logSwallowed('createAppStorageContainer', e);
      return (success: false, uri: null);
    }
  }

  /// Creates a Cryptomator (`cryptomator`), gocryptfs (`gocryptfs`) or CryFS (`cryfs`) vault in app storage
  /// and returns its URI, or null if it could not be created. The other arguments are those of the matching
  /// per-format create call.
  Future<String?> createAppStorageFolderVault({
    required String format,
    required String displayName,
    required String password,
    String cipher = '',
    Uint8List? userEntropy,
    bool deterministicNames = false,
    int longNameMax = 0,
    int blockSize = 0,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        ChannelMethods.createAppStorageFolderVault,
        {
          'format': format,
          'displayName': displayName,
          'password': password,
          'cipher': cipher,
          'userEntropy': userEntropy,
          'deterministicNames': deterministicNames,
          'longNameMax': longNameMax,
          'blockSize': blockSize,
        },
      );
      final success = result?['success'] as bool? ?? false;
      return success ? (result?['uri'] as String?) : null;
    } on PlatformException catch (e) {
      if (e.code == 'INSUFFICIENT_SPACE') rethrow;
      logSwallowed('createAppStorageFolderVault', e);
      return null;
    } catch (e) {
      logSwallowed('createAppStorageFolderVault', e);
      return null;
    }
  }

  /// Copies the vault at [sourceUri] into app storage and verifies the copy. The original is untouched.
  /// Throws [PlatformException] (see the class doc for codes).
  Future<VaultCopyResult> relocateToAppStorage({
    required String sourceUri,
    required bool isFolderVault,
    required String displayName,
    required int opId,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      ChannelMethods.relocateToAppStorage,
      {
        'sourceUri': sourceUri,
        'isFolderVault': isFolderVault,
        'displayName': displayName,
        'opId': opId,
      },
    );
    return _copyResult(result);
  }

  /// Asks where to put the vault, copies it there from app storage and verifies the copy. Null if the user
  /// dismissed the picker. The original is untouched.
  Future<VaultCopyResult?> relocateFromAppStorage({
    required String sourceUri,
    required bool isFolderVault,
    required String displayName,
    required int opId,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      ChannelMethods.relocateFromAppStorage,
      {
        'sourceUri': sourceUri,
        'isFolderVault': isFolderVault,
        'displayName': displayName,
        'opId': opId,
      },
    );
    if (result?['success'] != true) return null;
    return _copyResult(result);
  }

  Future<VaultFinalizeResult> finalizeRelocation({
    required String oldUri,
    required String newUri,
    required bool isFolderVault,
    required bool deleteSource,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      ChannelMethods.finalizeRelocation,
      {
        'oldUri': oldUri,
        'newUri': newUri,
        'isFolderVault': isFolderVault,
        'deleteSource': deleteSource,
      },
    );
    return (
      sourceDeleted: result?['sourceDeleted'] as bool? ?? false,
      automationReset: result?['automationReset'] as bool? ?? false,
      reason: result?['reason'] as String?,
    );
  }

  /// Removes a copy made by a relocation whose switch-over failed. Returns whether it was removed.
  Future<bool> discardRelocationCopy({required String uri, required bool isFolderVault}) async {
    final ok = await _channel.invokeMethod<bool>(
      ChannelMethods.discardRelocationCopy,
      {'uri': uri, 'isFolderVault': isFolderVault},
    );
    return ok ?? false;
  }

  /// Permanently deletes a vault from app storage. Returns whether it is gone.
  /// Throws [PlatformException] `VAULT_UNLOCKED` while the vault is unlocked.
  Future<bool> deleteAppStorageVault(String uri) async {
    final ok = await _channel.invokeMethod<bool>(
      ChannelMethods.deleteAppStorageVault,
      {'uri': uri},
    );
    return ok ?? false;
  }

  VaultCopyResult _copyResult(Map<String, Object?>? result) => (
    uri: result?['uri'] as String? ?? '',
    bytes: (result?['bytes'] as num?)?.toInt() ?? 0,
    files: (result?['files'] as num?)?.toInt() ?? 0,
  );
}
