import 'package:flutter/material.dart';
import '../../../utils/format_utils.dart';
import 'directory_tile.dart';
import 'file_tile.dart';

/// Stateless renderer for a flat list of directory entries.
///
/// Receives pre-sorted [dirs] and [files] lists and delegates every
/// tap / long-press event back to the parent via callbacks — it owns
/// no business logic.
class FileListView extends StatelessWidget {
  final List<String> dirs;
  final List<String> files;
  final bool isSelectionMode;
  final Set<String> selectedItems;

  /// Called with the raw [DIR] entry string when a directory row is tapped.
  final ValueChanged<String> onDirTap;

  /// Called with the raw `name|size` entry string when a file row is tapped.
  final ValueChanged<String> onFileTap;

  /// Called for both dirs and files on long-press.
  final ValueChanged<String> onItemLongPress;

  const FileListView({
    Key? key,
    required this.dirs,
    required this.files,
    required this.isSelectionMode,
    required this.selectedItems,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: dirs.length + files.length,
      itemBuilder: (_, index) {
        final isDir = index < dirs.length;
        final rawItem = isDir ? dirs[index] : files[index - dirs.length];
        final isSelected = selectedItems.contains(rawItem);

        if (isDir) {
          final cleanName = rawItem.replaceFirst('[DIR] ', '');
          return DirectoryTile(
            key: ValueKey(rawItem),
            name: cleanName,
            selectionMode: isSelectionMode,
            selected: isSelected,
            onTap: () => onDirTap(rawItem),
            onLongPress: () => onItemLongPress(rawItem),
          );
        }

        final parts = rawItem.split('|');
        final cleanName = parts.first;
        final fileSize = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

        return FileTile(
          key: ValueKey(rawItem),
          name: cleanName,
          subtitle: formatBytes(fileSize),
          selectionMode: isSelectionMode,
          selected: isSelected,
          onTap: () => onFileTap(rawItem),
          onLongPress: () => onItemLongPress(rawItem),
        );
      },
    );
  }
}