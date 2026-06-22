import 'package:flutter/material.dart';
import '../../../utils/format_utils.dart';
import 'directory_tile.dart';
import 'file_tile.dart';

/// Stateless renderer for a flat list of directory entries.
class FileListView extends StatelessWidget {
  final List<String> dirs;
  final List<String> files;
  final bool isSelectionMode;
  final Set<String> selectedItems;

  final ValueChanged<String> onDirTap;
  final ValueChanged<String> onFileTap;
  final ValueChanged<String> onItemLongPress;

  /// Called when the trailing "⋯" icon on a file tile is tapped.
  final ValueChanged<String>? onFileLongMenu;

  const FileListView({
    super.key,
    required this.dirs,
    required this.files,
    required this.isSelectionMode,
    required this.selectedItems,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
  });

  @override
  Widget build(BuildContext context) {
    final total = dirs.length + files.length;
    return ListView.builder(
      itemCount: total,
      itemBuilder: (_, index) {
        final isDir = index < dirs.length;
        final rawItem =
            isDir ? dirs[index] : files[index - dirs.length];
        final isSelected = selectedItems.contains(rawItem);

        if (isDir) {
          return DirectoryTile(
            key: ValueKey(rawItem),
            name: rawItem.replaceFirst('[DIR] ', ''),
            selectionMode: isSelectionMode,
            selected: isSelected,
            onTap: () => onDirTap(rawItem),
            onLongPress: () => onItemLongPress(rawItem),
          );
        }

        final parts = rawItem.split('|');
        final cleanName = parts.first;
        final fileSize =
            parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

        return FileTile(
          key: ValueKey(rawItem),
          name: cleanName,
          subtitle: formatBytes(fileSize),
          selectionMode: isSelectionMode,
          selected: isSelected,
          onTap: () => onFileTap(rawItem),
          onLongPress: () => onItemLongPress(rawItem),
          onMoreTap: isSelectionMode
              ? null
              : () => onFileLongMenu?.call(rawItem),
        );
      },
    );
  }
}