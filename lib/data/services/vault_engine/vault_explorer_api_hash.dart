part of 'vault_explorer_api.dart';

mixin _HashOps {
  /// Streams an external/on-device file's bytes through
  /// HashVerifierHandlers.kt's `MessageDigest`s, one per entry in
  /// [algorithms] (see [HashAlgorithm.wireName]), computing all of them in
  /// a single read pass. Returns lowercase hex digests keyed by the same
  /// wire names. Vault-resident files never go through this -- they're
  /// hashed entirely in Dart, see [HashVerifierService.computeHashes].
  Future<Map<String, String>> computeExternalFileHash({
    required String uri,
    required List<String> algorithms,
    required int opId,
  }) async {
    final result = await _channel.invokeMethod(
      ChannelMethods.computeExternalFileHash,
      {
        'uri': uri,
        'algorithms': algorithms,
        'opId': opId,
      },
    );
    if (result == null) return {};
    return Map<String, String>.from(result as Map);
  }

  Future<void> cancelHashCompute(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelHashCompute, {'opId': opId});
    } catch (e) {
      _logSwallowed('cancelHashCompute', e, expected: true);
    }
  }

  /// Reads the full contents of a small external/on-device file -- used
  /// only for checksum manifest files (.sha256sum/.md5/...), which are
  /// tiny text files unlike the large media files [computeExternalFileHash]
  /// streams without ever buffering them whole.
  Future<Uint8List?> readExternalFileBytes(String uri) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.readExternalFileBytes,
      {'uri': uri},
    );
    return result;
  }
}
