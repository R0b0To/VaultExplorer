import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/widgets/tile_selection_style.dart';

class FileTile extends StatelessWidget {
  final RawEntry entry;
  final bool isSelectionMode;
  final bool isSelected;
  final String? searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<RawEntry>? onLongMenu;
  final bool isCompact;
  final double zoomLevel;
  final List<FileDetailColumn> detailColumns;

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
    this.detailColumns = const [FileDetailColumn.date, FileDetailColumn.size],
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
    final displayIcon = vaultIcon ?? iconForFile(entry.name);
    final iconColor = vaultColor ?? colorForFile(entry.name);

    Widget? trailingWidget;
    if (isSelectionMode) {
      if (isSelected) {
        trailingWidget = const TileSelectionIndicator(selected: true);
      }
    } else if (onLongMenu != null) {
      trailingWidget = SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 20,
          color: cs.onSurfaceVariant,
          icon: const Icon(Icons.more_horiz_rounded),
          onPressed: () => onLongMenu!(entry),
        ),
      );
    }

    return FileRowShell(
      icon: displayIcon,
      iconColor: iconColor,
      unselectedIconBackground: cs.surfaceContainerHighest,
      displayName: displayName,
      searchQuery: searchQuery,
      entry: entry,
      detailColumns: detailColumns,
      trailing: trailingWidget,
      isSelected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
      isCompact: isCompact,
      zoomLevel: zoomLevel,
    );
  }
}