import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';

// Barrel export: this file used to also define ConcurrencyLimiter and
// ThumbnailConcurrency directly. They now live in thumbnail_concurrency.dart
// — re-exported here (along with the unawaited() helper) so existing
// imports of 'async_thumbnail.dart' keep working unchanged.
export 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';

typedef ThumbnailFetchFn = Future<Uint8List> Function(MountedContainer, String);
typedef ThumbnailSyncLookup = Uint8List? Function();

/// Generic async thumbnail loader.
///
/// Handles the full lifecycle shared by every thumbnail-bearing surface in
/// the app:
///  - a synchronous fast path via [syncLookup] (e.g. an in-memory cache hit)
///  - de-duplicating concurrent requests for the same file via [cache],
///    an [LruCache] of in-flight `Future`s keyed by container + path
///  - a scroll [debounce] that bails out before firing the real fetch if the
///    tile has already been scrolled past
///  - a [limiter] gate (LIFO + cancellable) so fast flings don't burn queue
///    turns on tiles the user never stops on
///
/// Visuals are fully delegated to the caller via [imageBuilder],
/// [loadingBuilder], and [errorBuilder], so each surface can keep its own
/// styling while sharing all of the above machinery.
class AsyncThumbnail extends StatefulWidget {
  final MountedContainer container;
  final String filePath;
  final LruCache<String, Future<Uint8List>> cache;
  final ConcurrencyLimiter limiter;
  final ThumbnailFetchFn fetchFn;
  final Duration debounce;
  final ThumbnailSyncLookup? syncLookup;
  final int? cacheHeight;
  final Widget Function(BuildContext context, Uint8List bytes, int? cacheHeight)
  imageBuilder;
  final WidgetBuilder? loadingBuilder;
  final WidgetBuilder? errorBuilder;

  const AsyncThumbnail({
    super.key,
    required this.container,
    required this.filePath,
    required this.cache,
    required this.limiter,
    required this.fetchFn,
    required this.imageBuilder,
    this.debounce = const Duration(milliseconds: 100),
    this.syncLookup,
    this.cacheHeight,
    this.loadingBuilder,
    this.errorBuilder,
  });

  @override
  State<AsyncThumbnail> createState() => _AsyncThumbnailState();
}

class _AsyncThumbnailState extends State<AsyncThumbnail> {
  Uint8List? _bytes;
  bool _isLoading = true;
  bool _hasError = false;

  Completer<void>? _limiterCompleter;
  String? _loadingPath;

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    final syncBytes = widget.syncLookup?.call();
    if (syncBytes != null) {
      _bytes = syncBytes;
      _isLoading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(AsyncThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _cancel();
      final syncBytes = widget.syncLookup?.call();
      if (syncBytes != null) {
        setState(() {
          _bytes = syncBytes;
          _isLoading = false;
          _hasError = false;
        });
      } else {
        setState(() {
          _bytes = null;
          _isLoading = true;
          _hasError = false;
        });
        _load();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    super.dispose();
  }

  void _cancel() {
    if (_limiterCompleter != null) {
      widget.limiter.cancel(_limiterCompleter!);
      _limiterCompleter = null;
    }
    _loadingPath = null;
  }

  Future<void> _load() async {
    final targetPath = widget.filePath;
    _loadingPath = targetPath;
    final cacheKey =
        '${widget.container.volId}:${widget.container.mountedAt.millisecondsSinceEpoch}:$targetPath';

    var future = widget.cache[cacheKey];

    if (future == null) {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _hasError = false;
        });
      }

      await Future.delayed(widget.debounce);
      if (targetPath != _loadingPath || !mounted || _disposed) return;

      final syncBytes = widget.syncLookup?.call();
      if (syncBytes != null) {
        if (mounted && !_disposed) {
          setState(() {
            _bytes = syncBytes;
            _isLoading = false;
          });
        }
        return;
      }

      future = widget.cache[cacheKey];
      if (future == null) {
        future = _fetchWithQueue(widget.container, targetPath).then(
          (data) => data,
          onError: (err) {
            if (widget.cache[cacheKey] == future) {
              widget.cache.remove(cacheKey);
            }
            throw err;
          },
        );
        widget.cache[cacheKey] = future;
      }
    }

    try {
      final data = await future;
      if (targetPath != _loadingPath || !mounted || _disposed) return;
      setState(() {
        _bytes = data;
        _isLoading = false;
      });
    } catch (_) {
      if (targetPath == _loadingPath && mounted && !_disposed) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<Uint8List> _fetchWithQueue(
    MountedContainer container,
    String targetPath,
  ) async {
    final completer = Completer<void>();
    _limiterCompleter = completer;
    bool acquired = false;

    try {
      await widget.limiter.acquire(completer);
      acquired = true;

      if (targetPath != _loadingPath || !mounted || _disposed) {
        throw Exception('Cancelled before processing');
      }

      return await widget.fetchFn(container, targetPath);
    } finally {
      if (_limiterCompleter == completer) _limiterCompleter = null;
      if (acquired) widget.limiter.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }
    if (_hasError || _bytes == null || _bytes!.isEmpty) {
      return widget.errorBuilder?.call(context) ?? const SizedBox.shrink();
    }
    return widget.imageBuilder(context, _bytes!, widget.cacheHeight);
  }
}
