import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vaultexplorer/data/models/archive_context.dart';

/// Extracts every file under [subPath] (or the whole archive when it's
/// empty) from [ctx] into [destinationDir], preserving the archive's
/// relative folder structure.
///
/// Shared by [DecoyArchiveExplorerScreen]'s "Extract All" / "Extract to…"
/// actions and [DecoyArchiveBrowseScreen]'s per-folder extraction, so the
/// temp-file bookkeeping (extract-to-temp, copy, always delete the temp
/// copy even on a failed copy) only lives in one place.
///
/// Returns the number of files written.
Future<int> extractArchiveContextTo(
  ArchiveContext ctx,
  Directory destinationDir, {
  String subPath = '',
}) async {
  await destinationDir.create(recursive: true);

  // ArchiveContext.extractAll() spills every matching entry to its own
  // temp dir first (see archive_context.dart) -- we then copy each one to
  // its real destination and clean up the temp copy regardless of whether
  // the copy succeeded.
  final extracted = await ctx.extractAll(subPath: subPath);

  var count = 0;
  for (final mapEntry in extracted.entries) {
    final relativePath = mapEntry.key;
    final tempPath = mapEntry.value;
    final destPath = p.join(destinationDir.path, relativePath);
    final destFile = File(destPath);
    try {
      await destFile.parent.create(recursive: true);
      await File(tempPath).copy(destPath);
      count++;
    } finally {
      try {
        await File(tempPath).delete();
      } catch (_) {}
    }
  }
  return count;
}
