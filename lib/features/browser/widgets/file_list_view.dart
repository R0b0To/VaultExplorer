import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/file_tile.dart';

/// Renders a modern inset list of directory entries by delegating each row
/// to [DirectoryTile] or [FileTile].

class FileListView extends StatefulWidget {
  final List<RawEntry> dirs;
  final List<RawEntry> files;
  final bool isSelectionMode;
  final bool isCompact;
  final Set<RawEntry> selectedItems;

  final ValueChanged<RawEntry> onDirTap;
  final ValueChanged<RawEntry> onFileTap;
  final ValueChanged<RawEntry> onItemLongPress;

  /// Called when the trailing "⋯" icon on a file tile is tapped.
  final ValueChanged<RawEntry>? onFileLongMenu;

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
              final entry = isDir ? widget.dirs[index] : widget.files[index - widget.dirs.length];
              final isSelected = widget.selectedItems.contains(entry);

              if (isDir) {
                return DirectoryTile(
                  key: ValueKey('dir:${entry.raw}'),
                  entry: entry,
                  isSelectionMode: widget.isSelectionMode,
                  isSelected: isSelected,
                  isCompact: widget.isCompact,
                  zoomLevel: _zoomLevel,
                  searchQuery: widget.searchQuery,
                  onTap: () => widget.onDirTap(entry),
                  onLongPress: () => widget.onItemLongPress(entry),
                );
              }
              return FileTile(
                key: ValueKey('file:${entry.raw}'),
                entry: entry,
                isSelectionMode: widget.isSelectionMode,
                isSelected: isSelected,
                isCompact: widget.isCompact,
                zoomLevel: _zoomLevel,
                searchQuery: widget.searchQuery,
                onTap: () => widget.onFileTap(entry),
                onLongPress: () => widget.onItemLongPress(entry),
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
