// What a drop on the dashboard means for the "add a vault" flow. Pure Dart so it can be unit-tested; the
// engine describes the dropped paths (`VaultLifecycleApi.probeDroppedPaths`) and this decides what to do.

/// One dropped path as the engine describes it. [format] is only meaningful for a folder: the wire name of
/// the folder-vault format it looks like (`cryptomator`, `gocryptfs`, `cryfs`), or `null` when the folder
/// is not a vault.
typedef DroppedPathInfo = ({
  String uri,
  String displayName,
  bool isDirectory,
  String? format,
});

sealed class DroppedSelection {
  const DroppedSelection();
}

/// One or more files: a container, or several files of one split / composite container -- the same as
/// multi-selecting in the file picker.
final class DroppedFiles extends DroppedSelection {
  final List<({String uri, String displayName})> files;
  const DroppedFiles(this.files);
}

/// A single folder: a folder vault, or (when [format] is null) a folder that turned out not to be one.
final class DroppedFolder extends DroppedSelection {
  final String uri;
  final String displayName;
  final String? format;
  const DroppedFolder({
    required this.uri,
    required this.displayName,
    required this.format,
  });
}

/// Nothing usable: nothing left to read, several folders, or files and a folder together.
final class DroppedUnsupported extends DroppedSelection {
  const DroppedUnsupported();
}

DroppedSelection planDroppedSelection(List<DroppedPathInfo> probed) {
  if (probed.isEmpty) return const DroppedUnsupported();
  if (probed.every((e) => !e.isDirectory)) {
    return DroppedFiles([
      for (final e in probed) (uri: e.uri, displayName: e.displayName),
    ]);
  }
  if (probed.length == 1) {
    final folder = probed.single;
    return DroppedFolder(
      uri: folder.uri,
      displayName: folder.displayName,
      format: folder.format,
    );
  }
  return const DroppedUnsupported();
}
