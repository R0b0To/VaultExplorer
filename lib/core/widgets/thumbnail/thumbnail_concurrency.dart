import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';

/// Suppresses the "unhandled future" lint for intentional fire-and-forget
/// background work (e.g. warming the on-disk cache after an in-memory hit).
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    debugPrint('unawaited error (non-fatal): $e');
  });
}

/// A LIFO concurrency gate with queue-cancellation support.
///
/// Ordinary semaphores are FIFO, which is the wrong policy for scroll-driven
/// UI: under fast scroll churn, the *oldest* queued request is the one the
/// user has already scrolled past, while the *newest* is the tile they're
/// currently looking at. Servicing newest-first (`removeLast()`) means the
/// visible tile jumps the queue instead of waiting behind stale work, and
/// [cancel] lets a disposed tile drop out of the queue entirely instead of
/// occupying a turn it no longer needs.
class ConcurrencyLimiter {
  final int maxConcurrency;
  int _running = 0;
  final _waiting = <Completer<void>>[];

  ConcurrencyLimiter(this.maxConcurrency);

  Future<void> acquire(Completer<void> completer) async {
    if (_running < maxConcurrency) {
      _running++;
      completer.complete();
      return;
    }
    _waiting.add(completer);
    await completer.future;
  }

  void cancel(Completer<void> completer) {
    if (_waiting.remove(completer)) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Cancelled in queue'));
      }
    }
  }

  void release() {
    _running = (_running - 1).clamp(0, maxConcurrency);
    _drainNext();
  }

  void _drainNext() {
    while (_waiting.isNotEmpty && _running < maxConcurrency) {
      final next = _waiting.removeLast();
      if (next.isCompleted) {
        continue;
      }
      _running++;
      next.complete();
    }
  }
}

/// App-wide thumbnail concurrency + in-flight de-duplication caches.
///
/// The file grid and the playlist carousel render thumbnails for the same
/// underlying files, so these are shared singletons rather than per-widget
/// statics: a grid-triggered fetch and a carousel-triggered fetch for the
/// same file collapse into a single native call instead of racing each
/// other, and both surfaces draw from one global "2 images / 1 video"
/// concurrency budget instead of stacking their own limiters on top of it.
///
/// Images and videos are limited separately so a slow video decode never
/// blocks image thumbnails queued up behind it.
class ThumbnailConcurrency {
  ThumbnailConcurrency._();

  static final imageLimiter = ConcurrencyLimiter(2);
  static final videoLimiter = ConcurrencyLimiter(1);

  static final imageCache = LruCache<String, Future<Uint8List>>(60);
  static final videoCache = LruCache<String, Future<Uint8List>>(100);
}
