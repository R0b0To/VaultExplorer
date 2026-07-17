import 'package:flutter/material.dart';
import '../../../theme.dart';
import 'directory_tile.dart';
import 'file_tile.dart';

/// Renders a modern inset list of directory entries by delegating each row
/// to [DirectoryTile] or [FileTile].

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

    return Column(
      children: [
        // Modern MD3 drops full-width dividers in favor of whitespace padding
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            // Increased safe padding for bottom sheets & floating clipboards
            padding: EdgeInsets.only(
              top: 0,
              bottom: AppSpacing.floatingStackClearance + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: total,
            itemBuilder: (_, index) {
              final isDir = index < dirs.length;
              final rawItem = isDir ? dirs[index] : files[index - dirs.length];
              final isSelected = selectedItems.contains(rawItem);

              if (isDir) {
                return DirectoryTile(
                  key: ValueKey('dir:$rawItem'),
                  rawItem: rawItem,
                  isSelectionMode: isSelectionMode,
                  isSelected: isSelected,
                  onTap: () => onDirTap(rawItem),
                  onLongPress: () => onItemLongPress(rawItem),
                );
              }
              return FileTile(
                key: ValueKey('file:$rawItem'),
                rawItem: rawItem,
                isSelectionMode: isSelectionMode,
                isSelected: isSelected,
                onTap: () => onFileTap(rawItem),
                onLongPress: () => onItemLongPress(rawItem),
                onLongMenu: onFileLongMenu,
              );
            },
          ),
        ),
      ],
    );
  }
}