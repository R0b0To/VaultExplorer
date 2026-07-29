import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'package:vaultexplorer/core/utils/retry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';


export 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';

typedef ThumbnailFetchFn = Future<Uint8List> Function(MountedContainer, String);
typedef ThumbnailSyncLookup = Uint8List? Function();

/// Generic async thumbnail loader.
class AsyncThumbnail extends StatefulWidget {
  final MountedContainer container;
  final String filePath;
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
    PlaybackThrottleController.isPlaybackActive.addListener(_onPlaybackActiveChanged);
    final syncBytes = widget.syncLookup?.call();
    if (syncBytes != null) {
      _bytes = syncBytes;
      _isLoading = false;
    } else {
      _load();
    }
  }

  void _onPlaybackActiveChanged() {
    if (!PlaybackThrottleController.isPlaybackActive.value) {
      if (mounted && !_disposed && (_bytes == null || _bytes!.isEmpty || _hasError)) {
        final cacheKey =
            '${widget.container.volId}:${widget.container.mountedAt.millisecondsSinceEpoch}:${widget.filePath}';
        widget.cache.remove(cacheKey);
        setState(() {
          _bytes = null;
          _hasError = false;
          _isLoading = true;
        });
        _load();
      }
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
    PlaybackThrottleController.isPlaybackActive.removeListener(_onPlaybackActiveChanged);
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
        future = _fetchWithQueue(widget.container, targetPath);
        widget.cache[cacheKey] = future;
        final storedFuture = future;
        unawaited(
          storedFuture.then((_) => null, onError: (_) => null).whenComplete(() {
            if (widget.cache[cacheKey] == storedFuture) {
              widget.cache.remove(cacheKey);
            }
          }),
        );
      }
    }

    try {
      final data = await future;
      if (targetPath != _loadingPath || !mounted || _disposed) return;
      setState(() {
        _bytes = data;
        _isLoading = false;
      });
    } catch (e) {
      if (targetPath == _loadingPath && mounted && !_disposed) {
        final errStr = e.toString();
        final isCancellation =
            errStr.contains('Cancelled') || errStr.contains('cancelled');
        if (isCancellation) {
          // Dequeued/cancelled due to rapid scrolling, not a missing or corrupt file.
          // Retry after a brief delay if this tile remains mounted and wanted on screen.
          Future.delayed(const Duration(milliseconds: 150), () {
            if (targetPath == _loadingPath && mounted && !_disposed) {
              _load();
            }
          });
        } else {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
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
      await widget.limiter.acquire(completer, priority: widget.priority);
      acquired = true;

      if (targetPath != _loadingPath || !mounted || _disposed) {
        throw Exception('Cancelled before processing');
      }

      return await retryWithBackoff<Uint8List>((attempt) {
        if (targetPath != _loadingPath || !mounted || _disposed) {
          throw Exception('Cancelled before retry attempt $attempt');
        }
        return widget.fetchFn(container, targetPath);
      });
    } finally {
      if (_limiterCompleter == completer) _limiterCompleter = null;
      if (acquired) widget.limiter.release(completer);
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