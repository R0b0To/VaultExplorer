import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';

import 'file_browser_predicates.dart';

/// Which of [items] being pasted into [currentDirPath] collide with a
/// name already present there, extracted from `_FileBrowserScreenState._paste()`
/// (see the top-of-file comment on file_browser_predicates.dart for why
/// this kind of logic gets pulled out into its own file).
///
/// [existingNamesLower]/[existingDirsLower] are the destination
/// directory's current entries, already lowercased by the caller (name
/// matching here is case-insensitive, matching how the underlying
/// filesystems this app supports treat names).
///
/// A name match is *not* automatically a conflict: pasting a
/// non-cut-and-move item back onto its own current location (same
/// container, same path) is a no-op, not a collision, so [isCrossContainer]
/// and each item's own [ClipboardItem.path] factor into the check too.
/// Getting this wrong in either direction is a real correctness bug, not
/// just a UX nuisance: too eager, and copying a file within its own folder
/// with the sheet cancelled becomes impossible; too lax, and a genuine
/// same-name collision from a different source silently overwrites without
/// ever asking.
List<ConflictEntry> detectPasteConflicts({
  required List<ClipboardItem> items,
  required Set<String> existingNamesLower,
  required Set<String> existingDirsLower,
  required bool isCrossContainer,
  required String currentDirPath,
}) {
  final conflicts = <ConflictEntry>[];
  for (final item in items) {
    final fileName = item.name;
    if (!existingNamesLower.contains(fileName.toLowerCase())) continue;
    final wouldBeSamePath = !isCrossContainer && item.path == joinPath(fileName, currentDirPath);
    if (wouldBeSamePath) continue;
    conflicts.add(
      ConflictEntry(
        item: item,
        destIsDir: existingDirsLower.contains(fileName.toLowerCase()),
      ),
    );
  }
  return conflicts;
}
