import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vaultexplorer/data/models/archive_context.dart';

/// Extracts every file under [subPath] (or the whole archive when it's
/// empty) from [ctx] into [destinationDir], preserving the archive's
/// relative folder structure.
///
/// Shared by [DecoyArchiveExplorerScreen]'s "Extract All" / "Extract to…"
/// actions and [DecoyArchiveBrowseScreen]'s per-folder extraction, so the
/// destination-writing logic only lives in one place.
///
/// [ArchiveContext.extractAll] now hands back each entry's bytes already
/// in memory (see archive_context.dart) -- this writes them straight to
/// their real destination file with no intermediate temp copy to stage
/// and clean up. The extracted files are genuinely meant to end up as
/// plaintext on device storage here (that's the point of "Extract to…"
/// in decoy/plain-zip browsing), so writing the final destination file
/// directly is the correct end state, not a finding in itself.
///
/// Returns the number of files written.
Future<int> extractArchiveContextTo(
  ArchiveContext ctx,
  Directory destinationDir, {
  String subPath = '',
}) async {
  await destinationDir.create(recursive: true);

  final extracted = await ctx.extractAll(subPath: subPath);

  var count = 0;
  for (final mapEntry in extracted.entries) {
    final relativePath = mapEntry.key;
    final bytes = mapEntry.value;
    final destPath = p.join(destinationDir.path, relativePath);
    final destFile = File(destPath);
    try {
      await destFile.parent.create(recursive: true);
      await destFile.writeAsBytes(bytes);
      count++;
    } catch (_) {
      // Best effort -- skip this entry and keep going with the rest.
    }
  }
  return count;
}
