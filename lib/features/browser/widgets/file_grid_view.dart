import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/widgets/highlighted_text.dart';

/// A dynamic gallery grid for the file browser supporting pinch-to-zoom.
class FileGridView extends StatefulWidget {
  final MountedContainer container;
  final List<RawEntry> dirs;
  final List<RawEntry> files;
  final bool isSelectionMode;
  final Set<RawEntry> selectedItems;
  final String currentDirPath;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final ValueChanged<RawEntry> onDirTap;
  final ValueChanged<RawEntry> onFileTap;
  final ValueChanged<RawEntry> onItemLongPress;
  final ValueChanged<RawEntry>? onFileLongMenu;

  /// Active search query for text highlighting (null or empty = no highlight).
  final String? searchQuery;

  const FileGridView({
    super.key,
    required this.container,
    required this.dirs,
    required this.files,
    required this.isSelectionMode,
    required this.selectedItems,
    required this.currentDirPath,
    required this.thumbnailCacheMode,
    required this.thumbnailQuality,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
    this.searchQuery,
  });

  @override
  State<FileGridView> createState() => _FileGridViewState();
}

class _FileGridViewState extends State<FileGridView> {
  Orientation? _lastOrientation;
  late int _crossAxisCount;
  double _baselineScale = 1.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _lastOrientation = orientation;
      _crossAxisCount = orientation == Orientation.landscape ? 5 : 3;
    }
  }

  int get _minColumns {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 3 : 1;
  }

  int get _maxColumns {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 7 : 4;
  }

  double _getAspectRatio(int columns) {
    switch (columns) {
      case 1:
        return 1.45;
      case 2:
        return 0.95;
      case 3:
        return 0.8;
      case 4:
        return 0.76;
      case 5:
        return 0.74;
      default:
        return 0.72;
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final scale = details.scale;
    final factor = scale / _baselineScale;

    if (factor > 1.35) {
      if (_crossAxisCount > _minColumns) {
        setState(() {
          _crossAxisCount--;
          _baselineScale = scale;
        });
      }
    } else if (factor < 0.75) {
      if (_crossAxisCount < _maxColumns) {
        setState(() {
          _crossAxisCount++;
          _baselineScale = scale;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.dirs.length + widget.files.length;

    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      child: GridView.builder(
        // Generous bottom padding for Edge-to-Edge compliance and FloatingActivityStack clearance
        padding: EdgeInsets.fromLTRB(
          10,
          12,
          10,
          AppSpacing.floatingStackClearance + MediaQuery.paddingOf(context).bottom,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: _getAspectRatio(_crossAxisCount),
        ),
        itemCount: total,
        itemBuilder: (context, index) {
          if (index < widget.dirs.length) {
            return _buildDirCell(context, widget.dirs[index]);
          }
          return _buildFileCell(
            context,
            widget.files[index - widget.dirs.length],
          );
        },
      ),
    );
  }

  Widget _buildDirCell(BuildContext context, RawEntry entry) {
    final isSelected = widget.selectedItems.contains(entry);
    final cs = Theme.of(context).colorScheme;

    return _GridCell(
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      onTap: () => widget.onDirTap(entry),
      onLongPress: () => widget.onItemLongPress(entry),
      preview: Center(
        child: Icon(
          Icons.folder_rounded,
          size: _crossAxisCount == 1 ? AppIconSize.hero + 16 : AppIconSize.hero,
          color: isSelected ? cs.primary : cs.secondary,
        ),
      ),
      label: entry.name,
      searchQuery: widget.searchQuery,
    );
  }

  Widget _buildFileCell(BuildContext context, RawEntry entry) {
    final cleanName = entry.name;
    final fullPath = widget.currentDirPath.isEmpty
        ? cleanName
        : '${widget.currentDirPath}/$cleanName';
    final isSelected = widget.selectedItems.contains(entry);

    String displayName = cleanName;
    final ext = cleanName.split('.').last;

    // Use the shared vault-type helpers from file_type_utils.dart.
    final vaultIcon = vaultIconForExt(ext);
    final vaultColor = vaultColorForExt(ext);

    // Strip the vault extension from the display name.
    if (vaultIcon != null) {
      final nameParts = cleanName.split('.');
      if (nameParts.length > 1) {
        nameParts.removeLast();
        displayName = nameParts.join('.');
      }
    }

    final isImg = MediaViewerConstants.isImage(cleanName);
    final isVid = MediaViewerConstants.isVideo(cleanName);

    Widget previewWidget;
    if (vaultIcon != null) {
      previewWidget = Center(
        child: Icon(
          vaultIcon,
          size: _crossAxisCount == 1 ? AppIconSize.hero : AppIconSize.feature,
          color: vaultColor,
        ),
      );
    } else if (isImg) {
      previewWidget = _EncryptedImageGridThumb(
        container: widget.container,
        filePath: fullPath,
        cacheMode: widget.thumbnailCacheMode,
        quality: widget.thumbnailQuality,
      );
    } else if (isVid) {
      previewWidget = _VideoThumb(
        container: widget.container,
        filePath: fullPath,
        cacheMode: widget.thumbnailCacheMode,
        quality: widget.thumbnailQuality,
      );
    } else {
      previewWidget = Center(
        child: Icon(
          iconForFile(cleanName),
          size: _crossAxisCount == 1 ? AppIconSize.hero : AppIconSize.feature,
          color: colorForFile(cleanName),
        ),
      );
    }

    return _GridCell(
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      onTap: () => widget.onFileTap(entry),
      onLongPress: () => widget.onItemLongPress(entry),
      onMoreTap: widget.isSelectionMode
          ? null
          : () => widget.onFileLongMenu?.call(entry),
      preview: previewWidget,
      label: displayName,
      searchQuery: widget.searchQuery,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic grid cell
// ─────────────────────────────────────────────────────────────────────────────

class _GridCell extends StatelessWidget {
  final Widget preview;
  final String label;
  final String? searchQuery;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onMoreTap;

  const _GridCell({
    required this.preview,
    required this.label,
    this.searchQuery,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias, // Ensures internal components match the Card's radii
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outlineVariant,
          width: isSelected ? 2.0 : 1.0, // MD3 active border is generally 2dp
        ),
      ),
      color: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.3)
          : cs.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  preview,
                  if (isSelected)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  if (isSelected)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _CheckBadge(
                          color: cs.primary,
                          onColor: cs.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              color: isSelected
                  ? Colors.transparent // Card color handles background
                  : cs.surfaceContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  HighlightedText(
                    text: label,
                    query: searchQuery,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  final Color color;
  final Color onColor;
  const _CheckBadge({required this.color, required this.onColor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Icon(Icons.check_rounded, size: AppIconSize.inline, color: onColor),
  );
}


// ─────────────────────────────────────────────────────────────────────────────
// Encrypted image thumbnail
// ─────────────────────────────────────────────────────────────────────────────

class _EncryptedImageGridThumb extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;

  const _EncryptedImageGridThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
  });

  static Future<Uint8List> _fetch(
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.get(
        container: container,
        filePath: path,
        mode: mode,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }

    Uint8List? thumbBytes = await vaultExplorerApi.getImageThumbnail(
      container,
      path,
      targetSize: quality.scaledSize(180), 
      quality: quality.jpegQuality,
    );

    if (thumbBytes == null || thumbBytes.isEmpty) {
      final size = await vaultExplorerApi.getFileSize(container, path);
      if (size <= 0) throw Exception('Empty file: $path');
      final raw = await vaultExplorerApi.readFileChunk(
        container,
        path,
        0,
        size,
      );
      if (raw == null || raw.isEmpty) throw Exception('Read failed: $path');
      if (raw.length < 200 * 1024) {
        ThumbnailCacheService.putInMemory(container, path, raw);
      }
      return raw;
    }

    ThumbnailCacheService.putInMemory(container, path, thumbBytes);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        ThumbnailCacheService.put(
          container: container,
          filePath: path,
          data: thumbBytes,
          mode: mode,
        ),
      );
    }

    return thumbBytes;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AsyncThumbnail(
      key: ValueKey('img:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.imageCache,
      limiter: ThumbnailConcurrency.imageLimiter,
      fetchFn: (c, p) => _fetch(c, p, cacheMode, quality),
      debounce: const Duration(milliseconds: 100),
      syncLookup: () => ThumbnailCacheService.getFromMemory(container, filePath),
      cacheHeight: quality.scaledSize(180),
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) => _errorPlaceholder(cs),
      ),
      loadingBuilder: (context) => Container(
        color: cs.surfaceContainerLow,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: cs.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
      errorBuilder: (context) => _errorPlaceholder(cs),
    );
  }

  Widget _errorPlaceholder(ColorScheme cs) => Container(
    color: cs.surfaceContainerLow,
    child: Center(
      child: Icon(Icons.broken_image_rounded, size: AppIconSize.feature, color: cs.outline),
    ),
  );
}
// ─────────────────────────────────────────────────────────────────────────────
// Video thumbnail
// ─────────────────────────────────────────────────────────────────────────────

class _VideoThumb extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;

  const _VideoThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
  });

  static Future<Uint8List> _fetch(
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.get(
        container: container,
        filePath: path,
        mode: mode,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final data = await vaultExplorerApi.getVideoThumbnail(
      container, 
      path, 
      quality: quality.jpegQuality,
      targetSize: quality.scaledSize(180),
    );
    if (data == null || data.isEmpty) return Uint8List(0);
   

    ThumbnailCacheService.putInMemory(container, path, data);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        ThumbnailCacheService.put(
          container: container,
          filePath: path,
          data: data,
          mode: mode,
        ),
      );
    }

    return data;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncThumbnail(
          key: ValueKey('vid:$filePath'),
          container: container,
          filePath: filePath,
          cache: ThumbnailConcurrency.videoCache,
          limiter: ThumbnailConcurrency.videoLimiter,
          fetchFn: (c, p) => _fetch(c, p, cacheMode, quality),
          debounce: const Duration(milliseconds: 150),
          syncLookup: () =>
              ThumbnailCacheService.getFromMemory(container, filePath),
          cacheHeight: quality.scaledSize(180),
          imageBuilder: (context, bytes, cacheHeight) => Image.memory(
            bytes,
            fit: BoxFit.cover,
            cacheHeight: cacheHeight,
            errorBuilder: (_, _, _) => _errorPlaceholder(cs),
          ),
          loadingBuilder: (context) => Container(
            color: cs.surfaceContainerLow,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: cs.primary.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          errorBuilder: (context) => _errorPlaceholder(cs),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Icons.play_circle_outline_rounded,
              size: AppIconSize.action,
              color: cs.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorPlaceholder(ColorScheme cs) => Container(
    color: cs.surfaceContainerLow,
    child: Center(
      child: Icon(Icons.broken_image_rounded, size: AppIconSize.feature, color: cs.outline),
    ),
  );
}
