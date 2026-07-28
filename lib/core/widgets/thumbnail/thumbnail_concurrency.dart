import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'dart:collection';

/// Suppresses the "unhandled future" lint for intentional fire-and-forget
/// background work.
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    debugPrint('unawaited error (non-fatal): $e');
  });
}

class ConcurrencyLimiter {
  final int maxConcurrency;
  int _running = 0;
  final _waiting = Queue<Completer<void>>(); 
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

  void cancelAll() {
    while (_waiting.isNotEmpty) {
      final next = _waiting.removeFirst();
      if (!next.isCompleted) {
        next.completeError(Exception('Cancelled all in queue'));
      }
    }
  }

  void release() {
    _running = (_running - 1).clamp(0, maxConcurrency);
    _drainNext();
  }

  void _drainNext() {
    while (_waiting.isNotEmpty && _running < maxConcurrency) {
      final next = _waiting.removeFirst();
      if (next.isCompleted) {
        continue;
      }
      _running++;
      next.complete();
    }
  }
}

class ThumbnailConcurrency {
  ThumbnailConcurrency._();
  static final imageLimiter = ConcurrencyLimiter(2);
  static final videoLimiter = ConcurrencyLimiter(1);
  static final imageCache = LruCache<String, Future<Uint8List>>(60);
  static final videoCache = LruCache<String, Future<Uint8List>>(100);
}