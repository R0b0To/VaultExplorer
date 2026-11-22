// Turns the host paths a drag-and-drop delivered into the entries an import can use.
//
// Pure `dart:io` + `package:path` (no engine, no FFI), so it can be unit-tested with a temp directory.
// Used by `DesktopTransfers.prepareDropImport`.
import 'dart:io';

import 'package:path/path.dart' as p;

/// One dropped path that can be imported: a regular file or a folder (a symlink is followed to what
/// it points at, like the file pickers do).
typedef DroppedEntry = ({String path, bool isDir});

/// The importable part of a drop, and how many dropped paths had to be left out.
typedef DroppedImportSet = ({List<DroppedEntry> accepted, int skipped});

/// Filters [paths] down to what can be imported into the vault stored at [vaultHostPath].
///
/// A path is skipped when it
///   * is not absolute, is a duplicate of an earlier path, or has no usable name (a drive root);
///   * no longer exists, or is neither a file nor a folder (socket, pipe, broken link);
///   * IS the vault itself, or a folder that CONTAINS it. Importing a container (or a Cryptomator-style
///     vault folder) into its own volume reads what it is writing, so it is refused outright rather
///     than left to fail halfway.
///
/// [context] is only there so tests can exercise Windows rules on any host.
DroppedImportSet resolveDroppedPaths(
  Iterable<String> paths, {
  String? vaultHostPath,
  p.Context? context,
}) {
  final ctx = context ?? p.context;
  final accepted = <DroppedEntry>[];
  final seen = <String>{};
  var skipped = 0;

  for (final raw in paths) {
    if (raw.isEmpty || !ctx.isAbsolute(raw) || ctx.basename(raw).isEmpty) {
      skipped++;
      continue;
    }
    if (!seen.add(ctx.canonicalize(raw))) {
      skipped++;
      continue;
    }
    if (vaultHostPath != null &&
        vaultHostPath.isNotEmpty &&
        (ctx.equals(raw, vaultHostPath) || ctx.isWithin(raw, vaultHostPath))) {
      skipped++;
      continue;
    }
    final bool isDir;
    switch (FileSystemEntity.typeSync(raw)) {
      case FileSystemEntityType.file:
        isDir = false;
      case FileSystemEntityType.directory:
        isDir = true;
      default:
        skipped++;
        continue;
    }
    accepted.add((path: raw, isDir: isDir));
  }
  return (accepted: accepted, skipped: skipped);
}
