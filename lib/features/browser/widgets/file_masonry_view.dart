import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/widgets/highlighted_text.dart';
import 'dart:ui' as ui;

/// Pinterest-style, variable-height, multi-column file browser layout.
///
/// Shares its tap/selection/thumbnail plumbing with [FileGridView] — same
/// constructor shape, same [AsyncThumbnail]-backed image/video previews, same
/// [ThumbnailCacheService] read/write path — so it's a drop-in alternative
/// layout rather than a parallel implementation with its own bugs to track.
///
/// Tile heights are driven by each thumbnail's *actual* content shape —
/// portrait media renders tall, landscape media renders wide — rather than a
/// deterministic-but-arbitrary ratio pulled from a lookup table. The true
/// aspect ratio comes straight from native: `getImageThumbnailWithSize` /
/// `getVideoThumbnailWithSize` report the source frame's pre-downscale
/// width/height alongside the thumbnail bytes, values native already has in
/// hand while generating the thumbnail itself (see `handleGetImageThumbnail
/// WithSize` / `handleGetVideoThumbnailWithSize` in MainActivity.kt) — so
/// there's no extra decode anywhere, native or Dart, over the byte-only path
/// the grid view and viewer use.
///
/// A tile starts at a neutral 1:1 placeholder and reflows to its real ratio
/// the moment a size becomes known and [MediaAspectRatioCache] has recorded
/// it (see `_onSizeKnown`). The size comes from, in order of preference:
///  1. [ThumbnailCacheService] — a cache hit now carries the width/height
///     alongside the bytes (packed in by [ThumbnailCacheService.put] at
///     write time), so a cached thumbnail reports its ratio with no extra
///     decode, even across app restarts where [MediaAspectRatioCache]'s
///     in-memory entries are gone.
///  2. A fresh fetch — `getImageThumbnailWithSize` / `getVideoThumbnailWithSize`
///     report the source frame's pre-downscale width/height alongside the
///     thumbnail bytes, values native already has in hand while generating
///     the thumbnail itself (see `handleGetImageThumbnailWithSize` /
///     `handleGetVideoThumbnailWithSize` in MainActivity.kt).
///  3. A last-resort Dart-side JPEG decode ([_checkAndReportSizeFromBytes]),
///     only for cache entries written before size-tracking existed.
/// Once recorded, the ratio is cached for the session (keyed like
/// [ThumbnailCacheService]'s memory tier) so revisiting a directory or
/// scrolling back doesn't reshuffle heights or ask native again.
class FileMasonryView extends StatefulWidget {
  final MountedContainer container;
  final List<RawEntry> dirs;
  final List<RawEntry> files;
  final bool isSelectionMode;
  final Set<RawEntry> selectedItems;
  final String currentDirPath;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final bool showFileNames;
  final ValueChanged<RawEntry> onDirTap;
  final ValueChanged<RawEntry> onFileTap;
  final ValueChanged<RawEntry> onItemLongPress;
  final ValueChanged<RawEntry>? onFileLongMenu;
  final String? searchQuery;

  const FileMasonryView({
    super.key,
    required this.container,
    required this.dirs,
    required this.files,
    required this.isSelectionMode,
    required this.selectedItems,
    required this.currentDirPath,
    required this.thumbnailCacheMode,
    required this.thumbnailQuality,
    this.showFileNames = true,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
    this.searchQuery,
  });

  @override
  State<FileMasonryView> createState() => _FileMasonryViewState();
}

class _FileMasonryViewState extends State<FileMasonryView> {
  Orientation? _lastOrientation;
  late int _columnCount;
  double _baselineScale = 1.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _lastOrientation = orientation;
      _columnCount = orientation == Orientation.landscape ? 4 : 2;
    }
  }

  int get _minColumns {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 2 : 1;
  }

  int get _maxColumns {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 6 : 3;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final scale = details.scale;
    final factor = scale / _baselineScale;
    if (factor > 1.35) {
      if (_columnCount > _minColumns) {
        setState(() {
          _columnCount--;
          _baselineScale = scale;
        });
      }
    } else if (factor < 0.75) {
      if (_columnCount < _maxColumns) {
        setState(() {
          _columnCount++;
          _baselineScale = scale;
        });
      }
    }
  }

  // Clamp real decoded ratios so a pathological source (e.g. a panorama or a
  // messaging-app strip crop) can't produce an unusably sliver-thin or
  // absurdly tall tile. Still wide/tall enough to read as clearly portrait
  // or landscape rather than looking clipped to a fixed shape.
  static const _minRatio = 0.5; // tall cap (2:1 portrait)
  static const _maxRatio = 2.2; // wide cap

  // Folders and files with no visual preview (plain icon tiles) always
  // render square — a varied height on an icon has no content to justify it
  // and just makes the columns harder to scan.
  static const _iconRatio = 1.0;

  /// Resolves the ratio a tile should render at *right now*.
  ///
  /// Real image/video files: prefer [MediaAspectRatioCache]'s decoded value
  /// (the file's true content shape). Until that resolves — nothing decoded
  /// yet for this session — fall back to a neutral square placeholder rather
  /// than a guessed shape, so a not-yet-loaded tile doesn't visually imply a
  /// wrong orientation before snapping to the real one.
  double _aspectRatioFor(RawEntry entry, String fullPath,
      {required bool hasVisualPreview}) {
    if (!hasVisualPreview) return _iconRatio;
    final decoded = MediaAspectRatioCache.get(widget.container, fullPath);
    if (decoded == null) return _iconRatio;
    return decoded.clamp(_minRatio, _maxRatio).toDouble();
  }

  /// Called by a tile's thumbnail the moment a *fresh* fetch (i.e. an actual
  /// native call, not a cache replay) reports the source frame's true
  /// width/height. Records the ratio, then triggers one rebuild so this tile
  /// (and the column packing around it) reflows from its placeholder square
  /// to its real shape. A no-op if the ratio didn't actually change (e.g.
  /// this path was already known from earlier in the session) to avoid
  /// pointless rebuild churn while a directory's thumbnails are still
  /// streaming in.
  void _onSizeKnown(String fullPath, int width, int height) {
    if (width <= 0 || height <= 0) return;
    final before = MediaAspectRatioCache.get(widget.container, fullPath);
    final ratio = width / height;
    if (before == ratio) return;
    MediaAspectRatioCache.put(widget.container, fullPath, width, height);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dirEntries = widget.dirs;
    final fileEntries = widget.files;
    final total = dirEntries.length + fileEntries.length;

    // Distribute items into [_columnCount] buckets, always appending to
    // whichever column currently has the least accumulated height — the
    // standard greedy masonry-packing heuristic. Accumulated height is
    // estimated from each tile's current aspect ratio (real once decoded,
    // a neutral square guess until then — see _aspectRatioFor); still keeps
    // columns visually balanced rather than a naive round-robin, and
    // self-corrects as real ratios come in and this rebuilds.
    final columns = List.generate(_columnCount, (_) => <Widget>[]);
    final columnHeights = List.filled(_columnCount, 0.0);
    const estimatedColumnWidth = 160.0; // relative unit; ratio is what matters

    for (var i = 0; i < total; i++) {
      final isDir = i < dirEntries.length;
      final entry = isDir ? dirEntries[i] : fileEntries[i - dirEntries.length];
      final fullPath = widget.currentDirPath.isEmpty
          ? entry.name
          : '${widget.currentDirPath}/${entry.name}';
      final hasVisualPreview = !isDir && _hasVisualPreview(entry.name);
      final ratio = _aspectRatioFor(entry, fullPath,
          hasVisualPreview: hasVisualPreview);
      final estimatedTileHeight = estimatedColumnWidth / ratio;

      var shortestColumn = 0;
      for (var c = 1; c < _columnCount; c++) {
        if (columnHeights[c] < columnHeights[shortestColumn]) {
          shortestColumn = c;
        }
      }

      final tile = Padding(
        key: ValueKey('${isDir ? 'dir' : 'file'}:${widget.currentDirPath}/${entry.name}'),
        padding: const EdgeInsets.only(bottom: 8),
        child: AspectRatio(
          aspectRatio: ratio,
          child: isDir
              ? _buildDirCell(context, entry)
              : _buildFileCell(context, entry, fullPath),
        ),
      );
      columns[shortestColumn].add(tile);
      columnHeights[shortestColumn] +=
          estimatedTileHeight + 8; // + the bottom padding above
    }

    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          10,
          12,
          10,
          AppSpacing.floatingStackClearance +
              MediaQuery.paddingOf(context).bottom,
        ),
        child: total == 0
            ? const SizedBox.shrink()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < _columnCount; c++) ...[
                    if (c > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Column(children: columns[c]),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  bool _hasVisualPreview(String fileName) {
    final ext = fileName.split('.').last;
    if (vaultIconForExt(ext) != null) return false;
    return MediaViewerConstants.isImage(fileName) ||
        MediaViewerConstants.isVideo(fileName);
  }

  Widget _buildDirCell(BuildContext context, RawEntry entry) {
    final isSelected = widget.selectedItems.contains(entry);
    final cs = Theme.of(context).colorScheme;
    return _MasonryCell(
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: widget.showFileNames,
      onTap: () => widget.onDirTap(entry),
      onLongPress: () => widget.onItemLongPress(entry),
      preview: Center(
        child: Icon(
          Icons.folder_rounded,
          size: AppIconSize.hero,
          color: isSelected ? cs.primary : cs.secondary,
        ),
      ),
      label: entry.name,
      searchQuery: widget.searchQuery,
    );
  }

  Widget _buildFileCell(BuildContext context, RawEntry entry, String fullPath) {
    final cleanName = entry.name;
    final isSelected = widget.selectedItems.contains(entry);
    String displayName = cleanName;
    final ext = cleanName.split('.').last;
    final vaultIcon = vaultIconForExt(ext);
    final vaultColor = vaultColorForExt(ext);
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
        child: Icon(vaultIcon, size: AppIconSize.feature, color: vaultColor),
      );
    } else if (isImg) {
      previewWidget = _EncryptedImageMasonryThumb(
        container: widget.container,
        filePath: fullPath,
        cacheMode: widget.thumbnailCacheMode,
        quality: widget.thumbnailQuality,
        onSizeKnown: (w, h) => _onSizeKnown(fullPath, w, h),
      );
    } else if (isVid) {
      previewWidget = _VideoMasonryThumb(
        container: widget.container,
        filePath: fullPath,
        cacheMode: widget.thumbnailCacheMode,
        quality: widget.thumbnailQuality,
        onSizeKnown: (w, h) => _onSizeKnown(fullPath, w, h),
      );
    } else {
      previewWidget = Center(
        child: Icon(
          iconForFile(cleanName),
          size: AppIconSize.feature,
          color: colorForFile(cleanName),
        ),
      );
    }
    return _MasonryCell(
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: widget.showFileNames,
      onTap: () => widget.onFileTap(entry),
      onLongPress: () => widget.onItemLongPress(entry),
      onMoreTap:
          widget.isSelectionMode ? null : () => widget.onFileLongMenu?.call(entry),
      preview: previewWidget,
      label: displayName,
      searchQuery: widget.searchQuery,
    );
  }
}

class _MasonryCell extends StatelessWidget {
  final Widget preview;
  final String label;
  final String? searchQuery;
  final bool isSelected;
  final bool isSelectionMode;
  final bool showFileName;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onMoreTap;

  const _MasonryCell({
    required this.preview,
    required this.label,
    this.searchQuery,
    required this.isSelected,
    required this.isSelectionMode,
    this.showFileName = true,
    required this.onTap,
    required this.onLongPress,
    this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outlineVariant,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      color: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.3)
          : cs.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
                  child: _CheckBadge(color: cs.primary, onColor: cs.onPrimary),
                ),
              ),
            if (showFileName)
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.65),
                      ],
                    ),
                  ),
                  child: HighlightedText(
                    text: label,
                    query: searchQuery,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
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
        child:
            Icon(Icons.check_rounded, size: AppIconSize.inline, color: onColor),
      );
}

class _EncryptedImageMasonryThumb extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final void Function(int width, int height) onSizeKnown;

  const _EncryptedImageMasonryThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.onSizeKnown,
  });

  static Future<void> _checkAndReportSizeFromBytes(
    MountedContainer container,
    String path,
    Uint8List bytes,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (bytes.isEmpty) return;
    if (MediaAspectRatioCache.get(container, path) == null) {
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        onSizeKnown(frame.image.width, frame.image.height);
        frame.image.dispose();
        codec.dispose();
      } catch (_) {}
    }
  }

  static Future<Uint8List> _fetch(
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.getWithSize(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.$1.isNotEmpty) {
        final (bytes, width, height) = cached;
        if (width != null && height != null) {
          onSizeKnown(width, height);
        } else {
          // Legacy entry cached before size tracking existed — fall back to
          // reading it off the JPEG bytes this once. The next _fetch for
          // this path (after the current write, below, or after this file's
          // cache entry naturally expires) will carry a size and skip this.
          await _checkAndReportSizeFromBytes(container, path, bytes, onSizeKnown);
        }
        return bytes;
      }
    }
    final thumb = await vaultExplorerApi.getImageThumbnailWithSize(
      container,
      path,
      targetSize: quality.scaledSize(180),
      quality: quality.jpegQuality,
    );
    final thumbBytes = thumb?.bytes;
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
        ThumbnailCacheService.putInMemory(container, path, raw, quality);
        await _checkAndReportSizeFromBytes(container, path, raw, onSizeKnown);
      }
      return raw;
    }
    onSizeKnown(thumb!.width, thumb.height);
    ThumbnailCacheService.putInMemory(
      container, path, thumbBytes, quality, thumb.width, thumb.height,
    );
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        ThumbnailCacheService.put(
          container: container,
          filePath: path,
          data: thumbBytes,
          mode: mode,
          quality: quality,
          width: thumb.width,
          height: thumb.height,
        ),
      );
    }
    return thumbBytes;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final syncEntry = ThumbnailCacheService.getWithSizeFromMemory(container, filePath, quality);
    final syncBytes = syncEntry?.$1;
    if (syncEntry != null && syncEntry.$1.isNotEmpty) {
      final (bytes, width, height) = syncEntry;
      if (width != null && height != null) {
        onSizeKnown(width, height);
      } else {
        _checkAndReportSizeFromBytes(container, filePath, bytes, onSizeKnown);
      }
    }
    return AsyncThumbnail(
      key: ValueKey('img:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.imageCache,
      limiter: ThumbnailConcurrency.imageLimiter,
      fetchFn: (c, p) => _fetch(c, p, cacheMode, quality, onSizeKnown),
      debounce: const Duration(milliseconds: 100),
      syncLookup: () => syncBytes,
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
          child: Icon(Icons.broken_image_rounded,
              size: AppIconSize.feature, color: cs.outline),
        ),
      );
}

class _VideoMasonryThumb extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final void Function(int width, int height) onSizeKnown;

  const _VideoMasonryThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.onSizeKnown,
  });

  static Future<void> _checkAndReportSizeFromBytes(
    MountedContainer container,
    String path,
    Uint8List bytes,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (bytes.isEmpty) return;
    if (MediaAspectRatioCache.get(container, path) == null) {
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        onSizeKnown(frame.image.width, frame.image.height);
        frame.image.dispose();
        codec.dispose();
      } catch (_) {}
    }
  }

  static Future<Uint8List> _fetch(
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.getWithSize(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.$1.isNotEmpty) {
        final (bytes, width, height) = cached;
        if (width != null && height != null) {
          onSizeKnown(width, height);
        } else {
          await _checkAndReportSizeFromBytes(container, path, bytes, onSizeKnown);
        }
        return bytes;
      }
    }
    final thumb = await vaultExplorerApi.getVideoThumbnailWithSize(
      container,
      path,
      quality: quality.jpegQuality,
      targetSize: quality.scaledSize(180),
    );
    final data = thumb?.bytes;
    if (data == null || data.isEmpty) return Uint8List(0);
    onSizeKnown(thumb!.width, thumb.height);
    ThumbnailCacheService.putInMemory(
      container, path, data, quality, thumb.width, thumb.height,
    );
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        ThumbnailCacheService.put(
          container: container,
          filePath: path,
          data: data,
          mode: mode,
          quality: quality,
          width: thumb.width,
          height: thumb.height,
        ),
      );
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final syncEntry = ThumbnailCacheService.getWithSizeFromMemory(container, filePath, quality);
    final syncBytes = syncEntry?.$1;
    if (syncEntry != null && syncEntry.$1.isNotEmpty) {
      final (bytes, width, height) = syncEntry;
      if (width != null && height != null) {
        onSizeKnown(width, height);
      } else {
        _checkAndReportSizeFromBytes(container, filePath, bytes, onSizeKnown);
      }
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncThumbnail(
          key: ValueKey('vid:$filePath'),
          container: container,
          filePath: filePath,
          cache: ThumbnailConcurrency.videoCache,
          limiter: ThumbnailConcurrency.videoLimiter,
          fetchFn: (c, p) => _fetch(c, p, cacheMode, quality, onSizeKnown),
          debounce: const Duration(milliseconds: 150),
          syncLookup: () => syncBytes,
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
          alignment: Alignment.topRight,
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
          child: Icon(Icons.broken_image_rounded,
              size: AppIconSize.feature, color: cs.outline),
        ),
      );
}