// Extracted from vault_explorer_api_split_join.dart (old mixin) as part of the Riverpod migration, Phase 2.
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

import 'vault_engine_types.dart';

class VaultSplitJoinApi {
  final MethodChannel _channel;
  const VaultSplitJoinApi(this._channel);

  Future<void> splitContainer({
    required String sourceUri,
    required String destinationPath,
    String? destinationTreeUri,
    required int chunkSizeBytes,
    required int opId,
  }) async {
    await _channel.invokeMethod(ChannelMethods.splitContainer, {
      'sourceUri': sourceUri,
      'destinationPath': destinationPath,
      'destinationTreeUri': destinationTreeUri,
      'chunkSizeBytes': chunkSizeBytes,
      'opId': opId,
    });
  }

  Future<void> joinContainer({
    required String firstPartUri,
    required String destinationPath,
    String? destinationTreeUri,
    required int opId,
  }) async {
    await _channel.invokeMethod(ChannelMethods.joinContainer, {
      'firstPartUri': firstPartUri,
      'destinationPath': destinationPath,
      'destinationTreeUri': destinationTreeUri,
      'opId': opId,
    });
  }

  Future<void> encryptSingleFile({
    required String sourceUri,
    required int cipherIndex,
    required String passphrase,
    List<String> keyfilePaths = const [],
    bool deleteOriginalAfter = false,
    String? destinationPath,
    String? destinationTreeUri,
    required int opId,
  }) async {
    await _channel.invokeMethod(ChannelMethods.encryptSingleFile, {
      'sourceUri': sourceUri,
      'cipherIndex': cipherIndex,
      'passphrase': passphrase,
      'keyfilePaths': keyfilePaths,
      'deleteOriginalAfter': deleteOriginalAfter,
      'destinationPath': destinationPath,
      'destinationTreeUri': destinationTreeUri,
      'opId': opId,
    });
  }

  Future<void> decryptSingleFile({
    required String sourceUri,
    required String passphrase,
    List<String> keyfilePaths = const [],
    String? destinationPath,
    String? destinationTreeUri,
    required int opId,
  }) async {
    await _channel.invokeMethod(ChannelMethods.decryptSingleFile, {
      'sourceUri': sourceUri,
      'passphrase': passphrase,
      'keyfilePaths': keyfilePaths,
      'destinationPath': destinationPath,
      'destinationTreeUri': destinationTreeUri,
      'opId': opId,
    });
  }

  Future<void> cancelSplitJoin(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelSplitJoin, {'opId': opId});
    } catch (e) {
      logSwallowed('cancelSplitJoin', e, expected: true);
    }
  }
}