import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'async_thumbnail_controller.dart';

export 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
export 'async_thumbnail_controller.dart' show ThumbnailFetchFn, ThumbnailSyncLookup;

/// Generic async thumbnail loader.
///
/// A thin shell over [asyncThumbnailLoaderProvider] -- the actual
/// load/cancel/retry/debounce state lives in that family-scoped Notifier
/// now, keyed by (container.volId, container.mountedAt, filePath,
/// quality). [quality] is a new required field (every existing caller
/// already has one available) needed purely to build that key; it plays
/// no other role here. See the controller file's doc comment for why the
/// family key can't include [fetchFn]/[syncLookup]/[cache]/[limiter]
/// directly, and why `initState`/`didUpdateWidget` calling
/// `ensureLoaded()` replaces this class's old manual state entirely.
class AsyncThumbnail extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailQuality quality;
  final LruCache<String, Future<Uint8List>> cache;
  final PriorityTaskQueue limiter;
  final ThumbnailFetchFn fetchFn;
  final Duration debounce;
  final ThumbnailSyncLookup? syncLookup;
  final int? cacheHeight;

  final TaskPriority priority;
  final Widget Function(BuildContext context, Uint8List bytes, int? cacheHeight)
  imageBuilder;
  final WidgetBuilder? loadingBuilder;
  final WidgetBuilder? errorBuilder;

  const AsyncThumbnail({
    super.key,
    required this.container,
    required this.filePath,
    required this.quality,
    required this.cache,
    required this.limiter,
    required this.fetchFn,
    required this.imageBuilder,
    this.debounce = const Duration(milliseconds: 100),
    this.syncLookup,
    this.cacheHeight,
    this.priority = TaskPriority.visible,
    this.loadingBuilder,
    this.errorBuilder,
  });

  @override
  ConsumerState<AsyncThumbnail> createState() => _AsyncThumbnailState();
}

class _AsyncThumbnailState extends ConsumerState<AsyncThumbnail> {
  AsyncThumbnailLoaderProvider get _provider => asyncThumbnailLoaderProvider(
        widget.container.volId,
        widget.container.mountedAt,
        widget.filePath,
        widget.quality,
      );

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(AsyncThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Defensive: every current call site keys this widget by content
    // (ValueKey('img:$filePath') etc.), so in practice a filePath change
    // tears down the old Element and mounts a fresh one -- this path
    // isn't expected to run. Kept so an in-place filePath/quality swap
    // (were a future caller to omit a content-based key) still starts the
    // new family instance's load rather than showing a stale/blank tile.
    if (oldWidget.filePath != widget.filePath || oldWidget.quality != widget.quality) {
      _ensureLoaded();
    }
  }

  void _ensureLoaded() {
    ref.read(_provider.notifier).ensureLoaded(
          container: widget.container,
          fetchFn: widget.fetchFn,
          cache: widget.cache,
          limiter: widget.limiter,
          syncLookup: widget.syncLookup,
          debounce: widget.debounce,
          priority: widget.priority,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    if (state.isLoading) {
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }
    if (state.hasError || state.bytes == null || state.bytes!.isEmpty) {
      return widget.errorBuilder?.call(context) ?? const SizedBox.shrink();
    }
    return widget.imageBuilder(context, state.bytes!, widget.cacheHeight);
  }
}