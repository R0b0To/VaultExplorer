part of 'vault_explorer_api.dart';

/// §5.1/§5.2/§5.3: cloud account/vault discovery and remote-chunked unlock,
/// backed by `CloudMountHandlers.kt` on the native side. Every method here
/// degrades gracefully when VaultSync Bridge isn't installed --
/// [checkCloudBridgeAvailable] is the one call that's meant to be probed
/// first and never throws for that case; the others simply return empty
/// results if called anyway, matching `VaultCloudBridgeClient`'s own
/// null-service short-circuiting on the Kotlin side.
mixin _CloudBridgeOps {
  Future<({bool available, String? version, String? reason})>
  checkCloudBridgeAvailable() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.checkCloudBridgeAvailable,
    );
    return (
      available: raw?['available'] as bool? ?? false,
      version: raw?['version'] as String?,
      reason: raw?['reason'] as String?,
    );
  }

  Future<List<CloudAccount>> listCloudAccounts() async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.listCloudAccounts,
    );
    if (raw == null) return const [];
    return raw
        .cast<Map<Object?, Object?>>()
        .map(CloudAccount._fromChannel)
        .toList();
  }

  Future<List<RemoteVault>> discoverRemoteVaults(
    String accountId, {
    String remoteDirectory = '/',
  }) async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.discoverRemoteVaults,
      {'accountId': accountId, 'remoteDirectory': remoteDirectory},
    );
    if (raw == null) return const [];
    return raw
        .cast<Map<Object?, Object?>>()
        .map(RemoteVault._fromChannel)
        .toList();
  }

  Future<List<RemoteFolder>> listRemoteFolders(
    String accountId, {
    String remoteDirectory = '/',
  }) async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.listRemoteFolders,
      {'accountId': accountId, 'remoteDirectory': remoteDirectory},
    );
    if (raw == null) return const [];
    return raw
        .cast<Map<Object?, Object?>>()
        .map(RemoteFolder._fromChannel)
        .toList();
  }

  /// Mounts [vault] directly from the cloud, without a full local copy --
  /// see IVaultCloudBridgeService.aidl's header comment. Returns the same
  /// shape [_ContainerLifecycleOps.unlockContainer] does, plus a synthetic
  /// `filePath` (a `cloud://accountId/remoteVaultPath` URI) the caller
  /// should treat exactly like a real file path from then on -- passing it
  /// to `lockContainer`, `updateContainerSettings`, etc. all just work
  /// (see `CloudMountHandlers.kt`'s doc comment).
  Future<
    ({
      int volId,
      String filePath,
      List<String> files,
      int matchedCipherId,
      int matchedHashId,
      String containerFormat,
    })?
  >
  unlockRemoteChunkedVault(
    RemoteVault vault,
    String password,
    int pim, {
    String? displayName,
    bool documentProvider = false,
    List<String> autoMountFolders = const [],
    int? cipherId,
    int? hashId,
    List<String>? keyfilePaths,
    bool readOnly = false,
  }) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.unlockRemoteChunkedVault,
      {
        'accountId': vault.accountId,
        'remoteVaultPath': vault.remotePath,
        'totalSizeBytes': vault.totalSizeBytes,
        'chunkSizeNumBytes': vault.chunkSizeNumBytes,
        'password': password,
        'pim': pim,
        'displayName': displayName ?? vault.displayName,
        'documentProvider': documentProvider,
        'autoMountFolders': autoMountFolders,
        'cipherId': cipherId ?? 255,
        'hashId': hashId ?? 255,
        'cacheDerivedKey': false,
        if (keyfilePaths != null && keyfilePaths.isNotEmpty)
          'keyfilePaths': keyfilePaths,
        'readOnly': readOnly,
      },
    );
    if (raw == null) return null;

    return (
      volId: raw['volId'] as int,
      filePath: raw['filePath'] as String,
      files: (raw['files'] as List<Object?>).cast<String>(),
      matchedCipherId: raw['matchedCipherId'] as int? ?? 255,
      matchedHashId: raw['matchedHashId'] as int? ?? 255,
      containerFormat: raw['containerFormat'] as String? ?? 'veracrypt',
    );
  }
}

/// Mirrors `CloudAccountDescriptor` (vaultsync-syncapi).
class CloudAccount {
  final String accountId;
  final String providerId;
  final String displayLabel;

  const CloudAccount({
    required this.accountId,
    required this.providerId,
    required this.displayLabel,
  });

  static CloudAccount _fromChannel(Map<Object?, Object?> raw) => CloudAccount(
    accountId: raw['accountId'] as String,
    providerId: raw['providerId'] as String,
    displayLabel: raw['displayLabel'] as String,
  );
}

/// Mirrors `RemoteVaultDescriptor` (vaultsync-syncapi).
class RemoteVault {
  final String accountId;
  final String remotePath;
  final String displayName;
  final String format;
  final int totalSizeBytes;
  final int chunkSizeNumBytes;
  final String? folderUri;

  const RemoteVault({
    required this.accountId,
    required this.remotePath,
    required this.displayName,
    required this.format,
    required this.totalSizeBytes,
    required this.chunkSizeNumBytes,
    this.folderUri,
  });

  static RemoteVault _fromChannel(Map<Object?, Object?> raw) => RemoteVault(
    accountId: raw['accountId'] as String,
    remotePath: raw['remotePath'] as String,
    displayName: raw['displayName'] as String,
    format: raw['format'] as String,
    totalSizeBytes: raw['totalSizeBytes'] as int,
    chunkSizeNumBytes: raw['chunkSizeNumBytes'] as int,
    folderUri: raw['folderUri'] as String?,
  );
}

/// A directory that can be opened through VaultSync Bridge's SAF provider.
class RemoteFolder {
  final String accountId;
  final String remotePath;
  final String displayName;
  final String folderUri;

  const RemoteFolder({
    required this.accountId,
    required this.remotePath,
    required this.displayName,
    required this.folderUri,
  });

  static RemoteFolder _fromChannel(Map<Object?, Object?> raw) => RemoteFolder(
    accountId: raw['accountId'] as String,
    remotePath: raw['remotePath'] as String,
    displayName: raw['displayName'] as String,
    folderUri: raw['folderUri'] as String,
  );
}
