import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';
import 'vault_engine_types.dart';

class VaultCompositeApi {
  final MethodChannel _channel;
  const VaultCompositeApi(this._channel);

  /// Analyzes a pool of carrier files, calculating format-aware safe capacity budgets.
  Future<CapacityProfile?> profileCarriers({
    required List<String> carrierUris,
    int safetyMarginPct = 90,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        ChannelMethods.profileCarriers,
        {
          'carrierUris': carrierUris,
          'safetyMarginPct': safetyMarginPct,
        },
      );
      if (raw == null) return null;

      final totalAllocatable = (raw['totalAllocatableBytes'] as num?)?.toInt() ?? 0;
      final rawCarriers = (raw['carriers'] as List<dynamic>?) ?? [];

      final carriers = rawCarriers.map((elem) {
        final m = elem as Map<dynamic, dynamic>;
        return (
          fileIndex: (m['fileIndex'] as num?)?.toInt() ?? 0,
          path: m['path'] as String? ?? '',
          detectedFormat: m['detectedFormat'] as String? ?? 'generic',
          fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
          payloadOffset: (m['payloadOffset'] as num?)?.toInt() ?? 0,
          allocatableBytes: (m['allocatableBytes'] as num?)?.toInt() ?? 0,
          tier: CarrierTier.fromId((m['tier'] as num?)?.toInt() ?? 2),
        );
      }).toList();

      return (
        totalAllocatableBytes: totalAllocatable,
        carriers: carriers,
      );
    } catch (e) {
      logSwallowed('profileCarriers', e);
      return null;
    }
  }

  /// Creates a distributed container across the given carrier files.
  Future<bool> createCompositeContainer({
    required List<String> carrierUris,
    required List<int> payloadOffsets,
    required List<int> extentLengths,
    required String password,
    int pim = 0,
    String fileSystem = 'fat',
    int containerFormat = 0,
    int cipherId = 255,
    int hashId = 255,
    List<String>? keyfilePaths,
    bool quickFormat = false,
    String operationId = '',
  }) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.createCompositeContainer,
        {
          'carrierUris': carrierUris,
          'payloadOffsets': payloadOffsets,
          'extentLengths': extentLengths,
          'password': password,
          'pim': pim,
          'fileSystem': fileSystem,
          'containerFormat': containerFormat,
          'cipherId': cipherId,
          'hashId': hashId,
          'keyfilePaths': keyfilePaths ?? [],
          'quickFormat': quickFormat,
          'operationId': operationId,
        },
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('createCompositeContainer', e);
      return false;
    }
  }

  /// Unlocks a distributed container across carrier files on the fly.
  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?>
      unlockCompositeContainer({
    required List<String> carrierUris,
    List<int>? payloadOffsets,
    List<int>? extentLengths,
    required String password,
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<String>? keyfilePaths,
    bool readOnly = false,
    String? displayName,
    bool documentProvider = false,
    List<String> autoMountFolders = const [],
  }) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.unlockCompositeContainer,
      {
        'carrierUris': carrierUris,
        if (payloadOffsets != null) 'payloadOffsets': payloadOffsets,
        if (extentLengths != null) 'extentLengths': extentLengths,
        'password': password,
        'pim': pim,
        'cipherId': cipherId,
        'hashId': hashId,
        if (keyfilePaths != null && keyfilePaths.isNotEmpty)
          'keyfilePaths': keyfilePaths,
        'readOnly': readOnly,
        'displayName': displayName,
        'documentProvider': documentProvider,
        'autoMountFolders': autoMountFolders,
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
}