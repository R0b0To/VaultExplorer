import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'package:vaultexplorer/core/utils/retry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';

part 'async_thumbnail_controller.g.dart';

typedef ThumbnailFetchFn = Future<Uint8List> Function(MountedContainer, String);
typedef ThumbnailSyncLookup = Uint8List? Function();

class AsyncThumbnailState {
  final Uint8List? bytes;
  final bool isLoading;
  final bool hasError;

  const AsyncThumbnailState({this.bytes, this.isLoading = true, this.hasError = false});

  AsyncThumbnailState _copy({Uint8List? bytes, bool? isLoading, bool? hasError}) {
    return AsyncThumbnailState(
      bytes: bytes ?? this.bytes,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
    );
  }
}

/// Family-scoped replacement for `_AsyncThumbnailState`'s manual
/// load/cancel/retry/debounce logic. Family key is (volId, mountedAt,
/// filePath, quality) -- identity-only, deliberately excluding [fetchFn]/
/// [syncLookup]/[cache]/[limiter], which can't be family arguments (fresh
/// closure identity on every parent rebuild would make Riverpod treat
/// every rebuild as a new family instance). Those are instead handed to
/// [ensureLoaded] imperatively by the widget's `initState`/
/// `didUpdateWidget` -- guarded by [_started] so only the first call per
/// provider instance actually does anything, mirroring the old
/// `initState`-runs-once contract this replaces.
///
/// Every call site keys the widget itself by content
/// (`ValueKey('img:$filePath')` etc., never by list position), so a
/// filePath change in practice always means Flutter tears down the old
/// Element and mounts a fresh one -- a new family instance, not this same
/// instance being redirected. The old `_loadingPath`/`targetPath`
/// staleness comparisons this replaces are therefore collapsed to a
/// single [ref.mounted] check throughout: there is no "this instance now
/// wants a different path" case to distinguish anymore, since a
/// different path is a different family instance entirely.
@riverpod
class AsyncThumbnailLoader extends _$AsyncThumbnailLoader {
  MountedContainer? _container;
  ThumbnailFetchFn? _fetchFn;
  ThumbnailSyncLookup? _syncLookup;
  LruCache<String, Future<Uint8List>>? _cache;
  PriorityTaskQueue? _limiter;
  Duration _debounce = const Duration(milliseconds: 100);
  TaskPriority _priority = TaskPriority.visible;
  bool _started = false;
  Completer<void>? _limiterCompleter;

  @override
  AsyncThumbnailState build(int volId, DateTime mountedAt, String filePath, ThumbnailQuality quality) {
    PlaybackThrottleController.isPlaybackActive.addListener(_onPlaybackActiveChanged);
    ref.onDispose(() {
      PlaybackThrottleController.isPlaybackActive.removeListener(_onPlaybackActiveChanged);
      _cancel();
    });
    return const AsyncThumbnailState();
  }

  void ensureLoaded({
    required MountedContainer container,
    required ThumbnailFetchFn fetchFn,
    required LruCache<String, Future<Uint8List>> cache,
    required PriorityTaskQueue limiter,
    ThumbnailSyncLookup? syncLookup,
    Duration debounce = const Duration(milliseconds: 100),
    TaskPriority priority = TaskPriority.visible,
  }) {
    if (_started) return;
    _started = true;
    _container = container;
    _fetchFn = fetchFn;
    _syncLookup = syncLookup;
    _cache = cache;
    _limiter = limiter;
    _debounce = debounce;
    _priority = priority;

    // This is called from `initState`/`didUpdateWidget`, which run while
    // the widget tree is still building -- writing `state` synchronously
    // from here (either branch below) trips Riverpod's
    // "modifying a provider during a widget life-cycle" assertion.
    // Deferring to a microtask (Riverpod's own suggested fix) lets the
    // current build finish first; `_load()`'s own first line does the
    // same kind of synchronous write, so it needs to start inside this
    // deferred callback too, not just be scheduled from it.
    scheduleMicrotask(() {
      if (!ref.mounted) return;
      final syncBytes = syncLookup?.call();
      if (syncBytes != null) {
        state = AsyncThumbnailState(bytes: syncBytes, isLoading: false);
      } else {
        _load();
      }
    });
  }

  void _onPlaybackActiveChanged() {
    if (PlaybackThrottleController.isPlaybackActive.value) return;
    if (!ref.mounted) return;
    if (state.bytes != null && state.bytes!.isNotEmpty && !state.hasError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.mounted) return;
      final container = _container;
      if (container == null) return;
      final cache = _cache;
      final cacheKey = '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:$filePath';
      cache?.remove(cacheKey);
      state = const AsyncThumbnailState();
      _load();
    });
  }

  void _cancel() {
    if (_limiterCompleter != null) {
      _limiter?.cancel(_limiterCompleter!);
      _limiterCompleter = null;
    }
  }

  Future<void> _load() async {
    final container = _container;
    final fetchFn = _fetchFn;
    final cache = _cache;
    final limiter = _limiter;
    if (container == null || fetchFn == null || cache == null || limiter == null) return;

    final cacheKey = '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:$filePath';
    var future = cache[cacheKey];

    if (future == null) {
      if (ref.mounted) state = state._copy(isLoading: true, hasError: false);

      await Future.delayed(_debounce);
      if (!ref.mounted) return;

      final syncBytes = _syncLookup?.call();
      if (syncBytes != null) {
        state = AsyncThumbnailState(bytes: syncBytes, isLoading: false);
        return;
      }

      future = cache[cacheKey];
      if (future == null) {
        future = _fetchWithQueue(container, filePath, fetchFn, limiter, _priority);
        cache[cacheKey] = future;
        final storedFuture = future;
        unawaited(
          storedFuture.then((_) => null, onError: (_) => null).whenComplete(() {
            if (cache[cacheKey] == storedFuture) cache.remove(cacheKey);
          }),
        );
      }
    }

    try {
      final data = await future;
      if (!ref.mounted) return;
      state = AsyncThumbnailState(bytes: data, isLoading: false);
    } catch (e) {
      if (!ref.mounted) return;
      final errStr = e.toString();
      final isCancellation = errStr.contains('Cancelled') || errStr.contains('cancelled');
      if (isCancellation) {
        // Dequeued/cancelled due to rapid scrolling, not a missing or
        // corrupt file. Retry after a brief delay if this instance is
        // still live.
        Future.delayed(const Duration(milliseconds: 150), () {
          if (ref.mounted) _load();
        });
      } else {
        state = state._copy(isLoading: false, hasError: true);
      }
    }
  }

  Future<Uint8List> _fetchWithQueue(
    MountedContainer container,
    String targetPath,
    ThumbnailFetchFn fetchFn,
    PriorityTaskQueue limiter,
    TaskPriority priority,
  ) async {
    final completer = Completer<void>();
    _limiterCompleter = completer;
    bool acquired = false;

    try {
      await limiter.acquire(completer, priority: priority);
      acquired = true;

      if (!ref.mounted) {
        throw Exception('Cancelled before processing');
      }

      return await retryWithBackoff<Uint8List>((attempt) {
        if (!ref.mounted) {
          throw Exception('Cancelled before retry attempt $attempt');
        }
        return fetchFn(container, targetPath);
      });
    } finally {
      if (_limiterCompleter == completer) _limiterCompleter = null;
      if (acquired) limiter.release(completer);
    }
  }
}