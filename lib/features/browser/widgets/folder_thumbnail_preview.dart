import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

class FolderThumbnailPreview extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String folderPath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final Widget child;

  final double? iconSize;
  final double? previewSize;

  static const int maxScan = 30;
  static const Duration scanDebounce = Duration(milliseconds: 350);

  // Caches only positive hits so newly populated folders can be scanned
  static final Map<String, Uint8List> _sessionCache = {};
  static const int _maxSessionCacheEntries = 300;

  static void clearSessionCache() => _sessionCache.clear();
  static void invalidate(String containerUri, String folderPath) {
    _sessionCache.remove('$containerUri:$folderPath');
  }

  const FolderThumbnailPreview({
    super.key,
    required this.container,
    required this.folderPath,
    required this.cacheMode,
    required this.quality,
    required this.child,
    this.iconSize,
    this.previewSize,
  });

  @override
  ConsumerState<FolderThumbnailPreview> createState() =>
      _FolderThumbnailPreviewState();
}

class _FolderThumbnailPreviewState
    extends ConsumerState<FolderThumbnailPreview> {
  Uint8List? _previewBytes;
  int _token = 0;
  Timer? _debounce;

  String get _cacheKey => '${widget.container.uri}:${widget.folderPath}';

  double get _resolvedIconSize {
    if (widget.iconSize != null) return widget.iconSize!;
    final c = widget.child;
    if (c is Icon && c.size != null) return c.size!;
    return 48.0;
  }

  @override
  void initState() {
    super.initState();
    if (FolderThumbnailPreview._sessionCache.containsKey(_cacheKey)) {
      _previewBytes = FolderThumbnailPreview._sessionCache[_cacheKey];
    } else {
      _scheduleScan();
    }
  }

  @override
  void didUpdateWidget(covariant FolderThumbnailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folderPath != widget.folderPath ||
        oldWidget.container.uri != widget.container.uri ||
        oldWidget.container.mountedAt != widget.container.mountedAt ||
        oldWidget.cacheMode != widget.cacheMode ||
        oldWidget.quality != widget.quality) {
      _debounce?.cancel();
      if (FolderThumbnailPreview._sessionCache.containsKey(_cacheKey)) {
        _previewBytes = FolderThumbnailPreview._sessionCache[_cacheKey];
      } else {
        _previewBytes = null;
        _scheduleScan();
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _token++;
    super.dispose();
  }

  void _scheduleScan() {
    if (widget.cacheMode == ThumbnailCacheMode.disabled) return;
    _debounce?.cancel();
    _debounce = Timer(FolderThumbnailPreview.scanDebounce, _scan);
  }

  static void _storeCache(String key, Uint8List bytes) {
    if (FolderThumbnailPreview._sessionCache.length >=
        FolderThumbnailPreview._maxSessionCacheEntries) {
      FolderThumbnailPreview._sessionCache.remove(
        FolderThumbnailPreview._sessionCache.keys.first,
      );
    }
    FolderThumbnailPreview._sessionCache[key] = bytes;
  }

  Future<void> _scan() async {
    final token = ++_token;
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);

    List<String>? raw;
    try {
      raw = await fileIoApi.listDirectory(widget.container, widget.folderPath);
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != _token || raw == null || raw.isEmpty) return;

    final candidates = <String>[];
    for (final line in raw) {
      if (line.startsWith('System:')) continue;
      final RawEntry entry;
      try {
        entry = RawEntry.parse(line);
      } catch (_) {
        continue;
      }
      if (entry.isDir || entry.isPlaceholder) continue;
      if (!MediaViewerConstants.isImage(entry.name) &&
          !MediaViewerConstants.isVideo(entry.name)) {
        continue;
      }
      candidates.add(
        widget.folderPath.isEmpty
            ? entry.name
            : '${widget.folderPath}/${entry.name}',
      );
      if (candidates.length >= FolderThumbnailPreview.maxScan) break;
    }

    if (candidates.isEmpty) return;

    // 1. Check if any candidate has a pre-cached thumbnail
    Uint8List? hit;
    for (final path in candidates) {
      final bytes = await thumbnailCache.fetch(
        container: widget.container,
        filePath: path,
        mode: widget.cacheMode,
        quality: widget.quality,
      );
      if (!mounted || token != _token) return;
      if (bytes != null && bytes.isNotEmpty) {
        hit = bytes;
        break;
      }
    }

    // 2. If no cached thumbnail exists yet, generate 1 thumbnail for the first image
    // throttled through imageLimiter at background priority so it never preempts
    // on-screen file thumbnails or main UI work.
    if (hit == null && candidates.isNotEmpty) {
      final firstPath = candidates.first;
      if (MediaViewerConstants.isImage(firstPath)) {
        final completer = Completer<void>();
        bool acquired = false;
        try {
          await ThumbnailConcurrency.imageLimiter.acquire(
            completer,
            priority: TaskPriority.background,
          );
          acquired = true;
          if (!mounted || token != _token) return;

          hit = await fileIoApi.getImageThumbnail(
            widget.container,
            firstPath,
            targetSize: widget.quality.scaledSize(180),
            quality: widget.quality.jpegQuality,
          );
          if (hit != null && hit.isNotEmpty) {
            thumbnailCache.cacheInMemory(
              widget.container,
              firstPath,
              hit,
              widget.quality,
            );
            if (widget.cacheMode != ThumbnailCacheMode.disabled) {
              unawaited(thumbnailCache.store(
                container: widget.container,
                filePath: firstPath,
                data: hit,
                mode: widget.cacheMode,
                quality: widget.quality,
              ));
            }
          }
        } catch (_) {
        } finally {
          if (acquired) {
            ThumbnailConcurrency.imageLimiter.release(completer);
          }
        }
      }
    }

    if (!mounted || token != _token) return;

    if (hit != null && hit.isNotEmpty) {
      _storeCache(_cacheKey, hit);
      setState(() => _previewBytes = hit);
    }
  }

  Widget _buildBadge(BuildContext context, Uint8List bytes, double size) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size * 0.14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular((size * 0.14) - 0.8),
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cacheMode == ThumbnailCacheMode.disabled) {
      return Center(child: widget.child);
    }

    final iconSize = _resolvedIconSize;
    final badgeSize = widget.previewSize ?? (iconSize * 0.8);
    final bytes = _previewBytes;

    return Center(
      child: SizedBox(
        width: iconSize,
        height: iconSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(child: widget.child),
            Positioned(
              left: iconSize * 0.5,
              top: iconSize * 0.5,
              width: badgeSize,
              height: badgeSize,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: bytes != null
                    ? _buildBadge(context, bytes, badgeSize)
                    : const SizedBox.shrink(key: ValueKey('empty_badge')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}