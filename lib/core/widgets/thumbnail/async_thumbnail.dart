import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport, RenderBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'package:vaultexplorer/core/utils/perf_trace.dart';
import 'package:vaultexplorer/core/widgets/scroll_speed_scope.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'async_thumbnail_controller.dart';

export 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
export 'async_thumbnail_controller.dart'
    show ThumbnailFetchFn, ThumbnailSyncLookup;

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
    this.debounce = const Duration(milliseconds: 30),
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
  bool _tickerEnabled = true;

  /// The scrollable this tile is in is moving too fast to read (see
  /// [ScrollSpeedScope]): a tile that has not asked for its thumbnail yet
  /// waits, which costs nothing, instead of creating a loader that its own
  /// disposal cancels a few frames later.
  bool _scrollIsFast = false;

  /// This tile has asked for its thumbnail at least once. From then on it is
  /// served normally, fast scroll or not.
  bool _armed = false;

  bool get _mayLoad => _tickerEnabled && (!_scrollIsFast || _armed);

  // The family key is rebuilt (an allocation plus hashing a DateTime, a path
  // and an enum) every time it is asked for, and `build` asks for it several
  // times. It only changes when the tile is pointed at a different file,
  // container or quality (see [didUpdateWidget]), so keep it.
  AsyncThumbnailLoaderProvider? _providerCache;

  AsyncThumbnailLoaderProvider get _provider =>
      _providerCache ??= asyncThumbnailLoaderProvider(
        widget.container.volId,
        widget.container.mountedAt,
        widget.filePath,
        widget.quality,
      );

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _scrollIsFast = ScrollSpeedScope.isFastOf(context);
    if (_mayLoad) _ensureLoaded();
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
      _providerCache = null;
      _armed = false;
      if (_mayLoad) _ensureLoaded();
    }
  }

  void _ensureLoaded() {
    if (!_tickerEnabled) return;
    _armed = true;
    ref
        .read(_provider.notifier)
        .ensureLoaded(
          container: widget.container,
          fetchFn: widget.fetchFn,
          cache: widget.cache,
          limiter: widget.limiter,
          syncLookup: widget.syncLookup,
          debounce: _debounceFor(widget.debounce),
          priority: widget.priority,
          priorityResolver: _resolvePriority,
        );
  }

  /// A third of what the call site asked for (30 ms becomes 10 ms), unless it
  /// is already short.
  ///
  /// The debounce exists so a tile that is built and gone within a frame or
  /// two never reaches the queue. Fast scrolling is already handled by the
  /// scroll-speed gate in [build], so the full wait only added latency to
  /// every tile that stays on screen: about a third of the time a cached
  /// thumbnail took to appear.
  static Duration _debounceFor(Duration requested) =>
      requested <= const Duration(milliseconds: 12)
      ? requested
      : Duration(microseconds: requested.inMicroseconds ~/ 3);

  /// Which queue tier this tile's request waits in, decided when it is about
  /// to join the queue (after the debounce, when the tile has been laid out).
  ///
  /// A tile on screen, or within a quarter of a screen of it, is
  /// [TaskPriority.visible]. One that exists only because the grid builds
  /// ahead of the viewport is [TaskPriority.adjacent], so thumbnails the user
  /// is looking at are always served before ones they have not scrolled to.
  /// Before this, every tile shared one tier, and a tile built far ahead of
  /// the screen -- being newest -- was served *first*.
  ///
  /// Anything unexpected (no scrollable, not laid out, an exception) keeps the
  /// caller's own priority, i.e. the previous behaviour.
  TaskPriority _resolvePriority() {
    final base = widget.priority;
    if (base != TaskPriority.visible || !mounted) return base;
    try {
      final object = context.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) {
        return base;
      }
      final viewport = RenderAbstractViewport.maybeOf(object);
      final scrollable = Scrollable.maybeOf(context);
      if (viewport == null || scrollable == null) return base;
      final position = scrollable.position;
      if (!position.hasPixels || !position.hasViewportDimension) return base;

      final direction = scrollable.axisDirection;
      final vertical =
          direction == AxisDirection.down || direction == AxisDirection.up;
      final extent = vertical ? object.size.height : object.size.width;
      // Scroll offset at which this tile's leading edge meets the viewport's.
      final start = viewport.getOffsetToReveal(object, 0.0).offset;
      final end = start + extent;
      final margin = position.viewportDimension * 0.25;
      final from = position.pixels - margin;
      final to = position.pixels + position.viewportDimension + margin;
      return (end > from && start < to)
          ? TaskPriority.visible
          : TaskPriority.adjacent;
    } catch (_) {
      return base;
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfT0 = PerfTrace.begin();
    final built = _buildTile(context);
    PerfTrace.end('ui.thumb.build', perfT0);
    return built;
  }

  Widget _buildTile(BuildContext context) {
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _scrollIsFast = ScrollSpeedScope.isFastOf(context);
    if (!_tickerEnabled) {
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }
    if (_scrollIsFast && !_armed) {
      // Too fast to read. A thumbnail that is already in memory is still shown
      // (it is free); anything else waits until the scroll slows down, which
      // rebuilds this tile (see ScrollSpeedScope).
      final hit = widget.syncLookup?.call();
      if (hit != null && hit.isNotEmpty) {
        return widget.imageBuilder(context, hit, widget.cacheHeight);
      }
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }
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
      // A tile re-entering the viewport gets a fresh provider instance whose
      // state starts as "loading" until the deferred microtask in
      // ensureLoaded runs. If the bytes are already in the memory cache,
      // paint them now instead of flashing a placeholder for a frame.
      final hit = widget.syncLookup?.call();
      if (hit != null && hit.isNotEmpty) {
        return widget.imageBuilder(context, hit, widget.cacheHeight);
      }
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }
    if (state.hasError || state.bytes == null || state.bytes!.isEmpty) {
      return widget.errorBuilder?.call(context) ?? const SizedBox.shrink();
    }
    return widget.imageBuilder(context, state.bytes!, widget.cacheHeight);
  }
}
