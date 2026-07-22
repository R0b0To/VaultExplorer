import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/widgets/tile_selection_style.dart';

/// Row renderer for a single file entry in [FileListView].
class FileTile extends StatelessWidget {
  /// Parsed file entry. Parsing happens once at the directory-listing
  /// boundary (see [FileBrowserScreen._loadDirectoryContents]) rather than
  /// here on every rebuild.
  final RawEntry entry;
  final bool isSelectionMode;
  final bool isSelected;
  final String? searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<RawEntry>? onLongMenu;
  final bool isCompact;
  final double zoomLevel;

  const FileTile({
    super.key,
    required this.entry,
    required this.isSelectionMode,
    required this.isSelected,
    this.searchQuery,
    required this.onTap,
    required this.onLongPress,
    this.onLongMenu,
    this.isCompact = false,
    this.zoomLevel = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String displayName = entry.name;
    final ext = displayName.split('.').last;
    final vaultIcon = vaultIconForExt(ext);
    final vaultColor = vaultColorForExt(ext);

    if (vaultIcon != null) {
      final parts = displayName.split('.');
      if (parts.length > 1) {
        parts.removeLast();
        displayName = parts.join('.');
      }
    }

    final sizeStr = vaultIcon != null ? '' : formatBytes(entry.sizeBytes);
    final displayIcon = vaultIcon ?? iconForFile(entry.name);
    final iconColor = vaultColor ?? colorForFile(entry.name);

    return FileRowShell(
      icon: displayIcon,
      iconColor: iconColor,
      unselectedIconBackground: cs.surfaceContainerHighest,
      displayName: displayName,
      searchQuery: searchQuery,
      dateStr: formatEntryDate(entry.modifiedSecs),
      trailing: _buildTrailing(context, sizeStr),
      isSelected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
      isCompact: isCompact,
      zoomLevel: zoomLevel,
    );
  }

  Widget _buildTrailing(BuildContext context, String sizeStr) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final sizeWidget = Text(
      sizeStr,
      textAlign: TextAlign.right,
      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (isSelectionMode) {
      return Align(
        alignment: Alignment.centerRight,
        child: isSelected
            ? const TileSelectionIndicator(selected: true)
            : (isCompact ? const SizedBox.shrink() : sizeWidget),
      );
    }

    if (onLongMenu != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!isCompact)
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: sizeWidget),
            ),
          const SizedBox(width: 4),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 20,
              color: cs.onSurfaceVariant,
              icon: const Icon(Icons.more_horiz_rounded), // Standard MD3 kebab
              onPressed: () => onLongMenu!(entry),
            ),
          ),
        ],
      );
    }

    return isCompact
        ? const SizedBox.shrink()
        : Align(alignment: Alignment.centerRight, child: sizeWidget);
  }
}
