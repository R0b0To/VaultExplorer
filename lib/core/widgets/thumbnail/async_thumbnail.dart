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
    // Every current call site keys this widget by content
    // (ValueKey('img:$filePath') etc.), so in practice a filePath change
    // tears down the old Element and mounts a fresh one. The container is
    // the case that doesn't work that way: the same file at the same path
    // can arrive under a rebuilt [MountedContainer] (a fresh `mountedAt`
    // is enough), which is a different family instance -- with a fresh,
    // still-loading state -- behind an Element that Flutter happily
    // reuses. Without this the new instance is never armed and the tile
    // spins forever. (`build` re-arms too, so this is belt and braces;
    // it's kept explicit because the container is easy to overlook when
    // reading the family key.)
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.quality != widget.quality ||
        oldWidget.container.volId != widget.container.volId ||
        oldWidget.container.mountedAt != widget.container.mountedAt) {
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
    // Arming on every build, not just on mount. `ensureLoaded` is a no-op
    // for a provider instance that has already started, so this costs
    // nothing in the normal case -- but the provider is autoDispose and
    // family-keyed, so the instance behind this widget can be replaced
    // (disposed and recreated, or keyed differently) without the widget
    // itself being rebuilt from scratch. `initState` has already run by
    // then and `didUpdateWidget` may see no change it recognises, which
    // used to leave a brand-new instance sitting in its initial loading
    // state with nothing in flight and no way out. Re-arming here makes
    // that self-correcting: any instance this widget is currently
    // watching is, by construction, one that has been asked to load.
    _ensureLoaded();
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