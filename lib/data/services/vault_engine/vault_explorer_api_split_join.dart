part of 'vault_explorer_api.dart';

/// Container Splitter/Joiner (Tools tab). Splits/joins an unmounted
/// container file picked via [_ContainerLifecycleOps.pickContainer] --
/// never a mounted `volId` -- so unlike [_FileIoOps]'s methods this never
/// takes a [MountedContainer]; `sourceUri`/`firstPartUri` are raw picked
/// `content://` URIs and `destinationPath` is a raw filesystem path
/// resolved by [_ContainerLifecycleOps.pickExtractFolder].
///
/// [opId] follows the same convention as [_FileIoOps.importFiles]/
/// [_FileIoOps.importFolder] (the caller's `FileOperation.id`), and
/// progress streams back via [VaultExplorerApi.addSplitJoinProgressListener]
/// the same way import progress streams via `addImportProgressListener`
/// -- [ContainerToolService]'s implementation is the one place that turns
/// that opId-keyed event stream back into the plain
/// `void Function(int, int)` callback its own interface promises.
mixin _SplitJoinOps {
  /// [destinationTreeUri] is [_ContainerLifecycleOps.pickExtractFolder]'s
  /// `treeUri` for the same folder as [destinationPath] -- the raw path
  /// alone may not actually be writable (no "All files access" granted),
  /// in which case native falls back to a SAF write through the tree URI.
  /// Always pass it when available; it's only null for callers that
  /// somehow have a raw path without having gone through the folder
  /// picker.
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

  /// Joins the chunk sequence starting at [firstPartUri] (located by
  /// naming convention on the native side -- see `SplitJoinHandlers`'s doc
  /// comment for why this requires raw filesystem access to the picked
  /// file's folder) into one file at [destinationPath]. [destinationTreeUri]
  /// carries the same SAF-write fallback as [splitContainer]'s.
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

  /// Best-effort, fire-and-forget cancel for an in-flight split or join
  /// identified by [opId] -- mirrors [_FileIoOps.cancelImport]'s contract:
  /// the in-flight call still resolves on its own shortly after, but with
  /// a `PlatformException(code: 'CANCELLED')` instead of a result.
  Future<void> cancelSplitJoin(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelSplitJoin, {'opId': opId});
    } catch (e) {
      _logSwallowed('cancelSplitJoin', e, expected: true);
    }
  }
}
