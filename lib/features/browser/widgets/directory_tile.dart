import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/widgets/tile_selection_style.dart';

class DirectoryTile extends StatelessWidget {
  final RawEntry entry;
  final bool isSelectionMode;
  final bool isSelected;
  final String? searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isCompact;
  final double zoomLevel;
  final List<FileDetailColumn> detailColumns;

  /// True when this folder is currently exposed as its own document-provider
  /// (SAF) root — shown with a distinct icon color so it stands out.
  final bool isDocumentProviderMounted;

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
    this.detailColumns = const [FileDetailColumn.date, FileDetailColumn.size],
    this.isDocumentProviderMounted = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = isDocumentProviderMounted ? cs.tertiary : cs.secondary;
    final iconBackground = isDocumentProviderMounted
        ? cs.tertiaryContainer.withValues(alpha: 0.4)
        : cs.secondaryContainer.withValues(alpha: 0.4);
    return FileRowShell(
      icon: Icons.folder_rounded,
      iconColor: iconColor,
      unselectedIconBackground: iconBackground,
      displayName: entry.name,
      searchQuery: searchQuery,
      entry: entry,
      detailColumns: detailColumns,
      trailing: isSelectionMode && isSelected
          ? const TileSelectionIndicator(selected: true)
          : null,
      isSelected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
      isCompact: isCompact,
      zoomLevel: zoomLevel,
    );
  }
}