import 'dart:io';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/widgets/highlighted_text.dart';
import 'package:vaultexplorer/features/browser/widgets/hold_range_select_container.dart';

/// Grid/masonry layout for the decoy's local storage explorer.
///
/// Visually mirrors `FileGridView`/`FileMasonryView` (same card chrome,
/// selection badge, and hold-range-select gesture container), but skips
/// their whole decrypt-then-thumbnail pipeline: real files are already
/// plaintext on disk, so an image preview is just `Image.file` -- no
/// `AsyncThumbnail`/`ThumbnailCacheService`/native decrypt round-trip
/// needed. Pass [masonry] to switch between a fixed-aspect grid and a
/// variable-height Pinterest-style layout.
class LocalMediaGridView extends StatefulWidget {
  final String currentDirPath;
  final List<RawEntry> items;
  final bool isSelectionMode;
  final Set<RawEntry> selectedItems;
  final bool masonry;
  final ValueChanged<RawEntry> onDirTap;
  final ValueChanged<RawEntry> onFileTap;
  final ValueChanged<RawEntry> onItemLongPress;
  final ValueChanged<Set<RawEntry>> onSelectionChanged;
  final String? searchQuery;

  const LocalMediaGridView({
    super.key,
    required this.currentDirPath,
    required this.items,
    required this.isSelectionMode,
    required this.selectedItems,
    required this.masonry,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    required this.onSelectionChanged,
    this.searchQuery,
  });

  @override
  State<LocalMediaGridView> createState() => _LocalMediaGridViewState();
}

class _LocalMediaGridViewState extends State<LocalMediaGridView> {
  int _crossAxisCount = 3;
  double _baselineScale = 1.0;

  static const int _minColumns = 1;
  static const int _maxColumns = 5;

  void _handleScaleStart(ScaleStartDetails details) => _baselineScale = 1.0;

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final factor = details.scale / _baselineScale;
    if (factor > 1.35 && _crossAxisCount > _minColumns) {
      setState(() {
        _crossAxisCount--;
        _baselineScale = details.scale;
      });
    } else if (factor < 0.75 && _crossAxisCount < _maxColumns) {
      setState(() {
        _crossAxisCount++;
        _baselineScale = details.scale;
      });
    }
  }

  double _aspectRatioFor(int columns) {
    switch (columns) {
      case 1:
        return 1.45;
      case 2:
        return 0.95;
      case 3:
        return 0.8;
      case 4:
        return 0.76;
      default:
        return 0.72;
    }
  }

  Widget _cellFor(int index) {
    final entry = widget.items[index];
    return HoldSelectableItem(
      index: index,
      entry: entry,
      child: _LocalCell(
        entry: entry,
        currentDirPath: widget.currentDirPath,
        isSelected: widget.selectedItems.contains(entry),
        searchQuery: widget.searchQuery,
        fixedAspect: !widget.masonry,
        onTap: () => entry.isDir ? widget.onDirTap(entry) : widget.onFileTap(entry),
        onLongPress: () => widget.onItemLongPress(entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = 24 + MediaQuery.paddingOf(context).bottom;
    return HoldRangeSelectContainer(
      items: widget.items,
      selectedItems: widget.selectedItems,
      isSelectionMode: widget.isSelectionMode,
      onSelectionChanged: widget.onSelectionChanged,
      onLongPressSelect: widget.onItemLongPress,
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      child: widget.masonry
          ? MasonryGridView.count(
              padding: EdgeInsets.fromLTRB(10, 12, 10, bottomInset),
              crossAxisCount: _crossAxisCount,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              itemCount: widget.items.length,
              itemBuilder: (context, index) => _cellFor(index),
            )
          : GridView.builder(
              padding: EdgeInsets.fromLTRB(10, 12, 10, bottomInset),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: _aspectRatioFor(_crossAxisCount),
              ),
              itemCount: widget.items.length,
              itemBuilder: (context, index) => _cellFor(index),
            ),
    );
  }
}

class _LocalCell extends StatelessWidget {
  final RawEntry entry;
  final String currentDirPath;
  final bool isSelected;
  final String? searchQuery;

  /// True in grid mode (fixed square-ish aspect, cropped preview); false
  /// in masonry mode (image keeps its natural aspect ratio, giving the
  /// staggered look).
  final bool fixedAspect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LocalCell({
    required this.entry,
    required this.currentDirPath,
    required this.isSelected,
    required this.searchQuery,
    required this.fixedAspect,
    required this.onTap,
    required this.onLongPress,
  });

  String get _fullPath => currentDirPath.isEmpty ? entry.name : p.join(currentDirPath, entry.name);

  Widget _brokenImage(ColorScheme cs) => Container(
        color: cs.surfaceContainerLow,
        child: Center(
          child: Icon(Icons.broken_image_rounded, size: AppIconSize.feature, color: cs.outline),
        ),
      );

  Widget _iconPreview(ColorScheme cs, IconData icon, Color color) {
    final block = Container(
      color: cs.surfaceContainerLow,
      child: Center(child: Icon(icon, size: AppIconSize.feature, color: color)),
    );
    // Icon previews have no natural size of their own, so in masonry mode
    // they need an explicit height -- otherwise every non-image cell would
    // collapse to zero height. Images are left unconstrained below so
    // they render at their real aspect ratio instead.
    return fixedAspect ? block : SizedBox(height: 130, child: block);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Widget preview;
    if (entry.isDir) {
      preview = _iconPreview(cs, Icons.folder_rounded, isSelected ? cs.primary : cs.secondary);
    } else if (MediaViewerConstants.isImage(entry.name)) {
      preview = Image.file(
        File(_fullPath),
        fit: fixedAspect ? BoxFit.cover : BoxFit.fitWidth,
        errorBuilder: (_, _, _) => _brokenImage(cs),
      );
    } else if (MediaViewerConstants.isVideo(entry.name)) {
      preview = _iconPreview(cs, Icons.movie_rounded, cs.outline);
    } else {
      preview = _iconPreview(cs, iconForFile(entry.name), colorForFile(entry.name));
    }

    final stack = Stack(
      fit: fixedAspect ? StackFit.expand : StackFit.loose,
      children: [
        preview,
        if (isSelected)
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12))),
          ),
        if (isSelected)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, size: AppIconSize.inline, color: cs.onPrimary),
            ),
          ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outlineVariant,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      color: isSelected ? cs.primaryContainer.withValues(alpha: 0.3) : cs.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: fixedAspect ? MainAxisSize.max : MainAxisSize.min,
          children: [
            fixedAspect ? Expanded(child: stack) : stack,
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              color: isSelected ? Colors.transparent : cs.surfaceContainer,
              child: HighlightedText(
                text: entry.name,
                query: searchQuery,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
