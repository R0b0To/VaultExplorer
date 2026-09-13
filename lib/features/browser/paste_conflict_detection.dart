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
/// A name match is *not* automatically a conflict: pasting a **cut**
/// item back onto its own current location (same container, same path)
/// is a no-op, not a collision -- the file never actually moves, so
/// there's nothing to resolve. [isCrossContainer], [isCutOperation], and
/// each item's own [ClipboardItem.path] factor into the check.
///
/// Crucially, that same exemption must *not* apply to a **copy**: pasting
/// a copied item back into its own folder does collide with itself (the
/// destination already has an entry with that exact name), so it needs
/// the same conflict dialog as any other same-name collision. Conflating
/// the two is what let a same-folder copy silently skip the dialog.
///
/// Getting this wrong in either direction is a real correctness bug, not
/// just a UX nuisance: too eager, and cutting a file and pasting it back
/// into its own folder with the sheet cancelled becomes impossible; too
/// lax, and a genuine same-name collision -- including a same-folder copy
/// -- silently overwrites without ever asking.
List<ConflictEntry> detectPasteConflicts({
  required List<ClipboardItem> items,
  required Set<String> existingNamesLower,
  required Set<String> existingDirsLower,
  required bool isCrossContainer,
  required bool isCutOperation,
  required String currentDirPath,
}) {
  final conflicts = <ConflictEntry>[];
  for (final item in items) {
    final fileName = item.name;
    if (!existingNamesLower.contains(fileName.toLowerCase())) continue;
    final wouldBeSamePath = isCutOperation &&
        !isCrossContainer &&
        item.path == joinPath(fileName, currentDirPath);
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