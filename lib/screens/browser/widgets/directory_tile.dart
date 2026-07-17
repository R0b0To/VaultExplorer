import 'package:flutter/material.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/raw_entry.dart';
import 'tile_selection_style.dart';

/// Row renderer for a single directory entry in [FileListView].
class DirectoryTile extends StatelessWidget {
  /// Raw wire-format entry, e.g. `"[DIR] Photos|0|1700000000"`.
  final String rawItem;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const DirectoryTile({
    super.key,
    required this.rawItem,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entry = RawEntry.parse(rawItem);

    return FileRowShell(
      icon: Icons.folder_rounded,
      iconColor: cs.secondary,
      unselectedIconBackground: cs.secondaryContainer.withValues(alpha: 0.4),
      displayName: entry.name,
      dateStr: formatEntryDate(entry.modifiedSecs),
      trailing: isSelectionMode && isSelected
          ? const Align(
              alignment: Alignment.centerRight,
              child: TileSelectionIndicator(selected: true),
            )
          : const SizedBox.shrink(),
      isSelected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}