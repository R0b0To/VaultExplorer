import 'package:flutter/material.dart';
import '../../../theme.dart';
import 'directory_tile.dart';
import 'file_tile.dart';

/// Renders a modern inset list of directory entries by delegating each row
/// to [DirectoryTile] or [FileTile].

class FileListView extends StatefulWidget {
  final List<String> dirs;
  final List<String> files;
  final bool isSelectionMode;
  final bool isCompact;
  final Set<String> selectedItems;

  final ValueChanged<String> onDirTap;
  final ValueChanged<String> onFileTap;
  final ValueChanged<String> onItemLongPress;

  /// Called when the trailing "⋯" icon on a file tile is tapped.
  final ValueChanged<String>? onFileLongMenu;

  /// Active search query for text highlighting (null or empty = no highlight).
  final String? searchQuery;

  const FileListView({
    super.key,
    required this.dirs,
    required this.files,
    required this.isSelectionMode,
    this.isCompact = false,
    required this.selectedItems,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
    this.searchQuery,
  });

  @override
  State<FileListView> createState() => _FileListViewState();
}

class _FileListViewState extends State<FileListView> {
  double _baselineScale = 1.0;
  double _zoomLevel = 1.0;

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = _zoomLevel;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _zoomLevel = (_baselineScale * details.scale).clamp(0.75, 2.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.dirs.length + widget.files.length;

    return Column(
      children: [
        // Modern MD3 drops full-width dividers in favor of whitespace padding
        const SizedBox(height: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.textScalerOf(context).scale(1.0) * _zoomLevel,
                ),
              ),
              child: ListView.builder(
            // Increased safe padding for bottom sheets & floating clipboards
            padding: EdgeInsets.only(
              top: 0,
              bottom: AppSpacing.floatingStackClearance + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: total,
            itemBuilder: (_, index) {
              final isDir = index < widget.dirs.length;
              final rawItem = isDir ? widget.dirs[index] : widget.files[index - widget.dirs.length];
              final isSelected = widget.selectedItems.contains(rawItem);

              if (isDir) {
                return DirectoryTile(
                  key: ValueKey('dir:$rawItem'),
                  rawItem: rawItem,
                  isSelectionMode: widget.isSelectionMode,
                  isSelected: isSelected,
                  isCompact: widget.isCompact,
                  zoomLevel: _zoomLevel,
                  searchQuery: widget.searchQuery,
                  onTap: () => widget.onDirTap(rawItem),
                  onLongPress: () => widget.onItemLongPress(rawItem),
                );
              }
              return FileTile(
                key: ValueKey('file:$rawItem'),
                rawItem: rawItem,
                isSelectionMode: widget.isSelectionMode,
                isSelected: isSelected,
                isCompact: widget.isCompact,
                zoomLevel: _zoomLevel,
                searchQuery: widget.searchQuery,
                onTap: () => widget.onFileTap(rawItem),
                onLongPress: () => widget.onItemLongPress(rawItem),
                onLongMenu: widget.onFileLongMenu,
              );
            },
          ),
            ),
          ),
        ),
      ],
    );
  }
}