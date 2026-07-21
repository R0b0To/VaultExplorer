import 'package:flutter/material.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/raw_entry.dart';
import 'tile_selection_style.dart';

/// Row renderer for a single directory entry in [FileListView].
class DirectoryTile extends StatelessWidget {
  /// Parsed directory entry. Parsing happens once at the directory-listing
  /// boundary (see [FileBrowserScreen._loadDirectoryContents]) rather than
  /// here on every rebuild.
  final RawEntry entry;
  final bool isSelectionMode;
  final bool isSelected;
  final String? searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isCompact;
  final double zoomLevel;

  const DirectoryTile({
    super.key,
    required this.entry,
    required this.isSelectionMode,
    required this.isSelected,
    this.searchQuery,
    required this.onTap,
    required this.onLongPress,
    this.isCompact = false,
    this.zoomLevel = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FileRowShell(
      icon: Icons.folder_rounded,
      iconColor: cs.secondary,
      unselectedIconBackground: cs.secondaryContainer.withValues(alpha: 0.4),
      displayName: entry.name,
      searchQuery: searchQuery,
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
      isCompact: isCompact,
      zoomLevel: zoomLevel,
    );
  }
}