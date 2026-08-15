part of 'vault_explorer_api.dart';

mixin _HashOps {
  /// Streams an external/on-device file's bytes through
  /// HashVerifierHandlers.kt's `MessageDigest`s, one per entry in
  /// [algorithms] (see [HashAlgorithm.wireName]), computing all of them in
  /// a single read pass. Returns lowercase hex digests keyed by the same
  /// wire names. Vault-resident files use [beginHashSession] /
  /// [updateHashSession] / [finishHashSession] instead, since the vault
  /// read itself has to happen on the Dart side either way (see
  /// [HashVerifierService.computeHashes]) -- this method is for the case
  /// where Dart can't read the source at all (a `content://` Uri).
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

  /// Computes a plain SHA-256 digest of an in-memory byte buffer via the
  /// same `java.security.MessageDigest` primitive [computeExternalFileHash]
  /// uses for external files (see HashVerifierHandlers.kt) -- just applied
  /// to a buffer that's already fully in memory rather than a Uri that
  /// needs reading. Used by the Keyfile & Passphrase Generator to
  /// fingerprint a freshly generated keyfile, and by
  /// `DuplicateFinderService` for its 16 KB partial-header hash, without
  /// depending on a third-party Dart hashing package for something the
  /// platform already does natively. Returns a lowercase hex string.
  Future<String> hashBytesSha256(Uint8List bytes) async {
    final result = await _channel.invokeMethod<String>(
      ChannelMethods.hashBytesSha256,
      {'bytes': bytes},
    );
    return result ?? '';
  }

  /// Same shape as [hashBytesSha256], but MD5 -- used by
  /// `ThumbnailCacheService._encodeKey` to derive cache filenames/directory
  /// names from a URI or path string. Purely a cache-key derivation, not a
  /// security boundary, so it stays MD5 (changing algorithm would change
  /// every existing key and orphan the on-disk/in-container thumbnail
  /// cache on upgrade) rather than switching to SHA-256.
  ///
  /// Throws (rather than falling back to an empty string) if the platform
  /// call doesn't return a digest -- every `_encodeKey` call site is
  /// wrapped in a try/catch that treats a failed cache-key derivation as a
  /// cache miss/skip, which is correct; a *silent empty key* is not, since
  /// every container would collapse onto the same cache path instead of
  /// the operation just failing.
  Future<String> hashBytesMd5(Uint8List bytes) async {
    final result = await _channel.invokeMethod<String>(
      ChannelMethods.hashBytesMd5,
      {'bytes': bytes},
    );
    if (result == null || result.isEmpty) {
      throw StateError('hashBytesMd5 returned no digest');
    }
    return result;
  }

  /// Opens an incremental hash session under [opId]: one native
  /// `MessageDigest` per entry in [algorithms] (see
  /// HashVerifierHandlers.kt). Pair with [updateHashSession] fed in a
  /// loop from wherever the caller reads its own chunks (e.g.
  /// [readFileChunk] for a vault file) and [finishHashSession] to collect
  /// the result -- lets a caller that already has to read a file
  /// chunk-by-chunk on the Dart side still compute the digest natively,
  /// without a Dart hashing package and without the native side needing
  /// to know how to read that source itself. Call [discardHashSession]
  /// instead of [finishHashSession] on any exit path that isn't a
  /// completed read (cancelled, or a chunk read failed), so the
  /// half-finished digests aren't left behind on the native side.
  Future<void> beginHashSession(int opId, List<String> algorithms) async {
    await _channel.invokeMethod(
      ChannelMethods.beginHashSession,
      {'opId': opId, 'algorithms': algorithms},
    );
  }

  /// Feeds one chunk into every digest in the [opId] session opened by
  /// [beginHashSession].
  Future<void> updateHashSession(int opId, Uint8List bytes) async {
    await _channel.invokeMethod(
      ChannelMethods.updateHashSession,
      {'opId': opId, 'bytes': bytes},
    );
  }

  /// Finalizes and removes the [opId] session, returning lowercase hex
  /// digests keyed by wire name -- same shape [computeExternalFileHash]
  /// returns.
  Future<Map<String, String>> finishHashSession(int opId) async {
    final result = await _channel.invokeMethod(
      ChannelMethods.finishHashSession,
      {'opId': opId},
    );
    if (result == null) return {};
    return Map<String, String>.from(result as Map);
  }

  /// Drops the [opId] session without finalizing it. Swallows errors --
  /// this runs on cleanup paths (cancellation, a failed read) where the
  /// caller has already decided the operation didn't succeed, so a
  /// failure to discard shouldn't surface as a second error on top of
  /// that; it just means the native side holds onto a little memory for
  /// an abandoned session a bit longer.
  Future<void> discardHashSession(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.discardHashSession, {'opId': opId});
    } catch (e) {
      _logSwallowed('discardHashSession', e, expected: true);
    }
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
