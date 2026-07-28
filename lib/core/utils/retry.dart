import 'dart:async';
import 'dart:math';

/// Shared exponential-backoff retry helper (Finding F-11 / Roadmap Phase 1
/// item 5).
///
/// Before this existed, [FullResImageCache] retried 3 times with a *flat*
/// 300ms delay, and the thumbnail path ([AsyncThumbnail]/
/// [ThumbnailConcurrency]) had no retry at all — a transient failure (USB
/// hiccup, container I/O glitch) surfaced straight to the caller's error
/// state and stayed there until a brand-new widget instance was created
/// (e.g. by scrolling the tile off-screen and back, or pull-to-refresh).
///
/// [attempt] is 0-indexed and receives the current attempt number so
/// callers that need to re-check "is this still wanted" between attempts
/// (see [FullResImageCache.fetch]'s `isStillWanted`) can do so themselves
/// inside the callback before doing real work.
Future<T> retryWithBackoff<T>(
  Future<T> Function(int attempt) attemptFn, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 200),
  double multiplier = 2.0,
  Duration maxDelay = const Duration(seconds: 3),
  bool Function(Object error)? retryIf,
}) async {
  assert(maxAttempts > 0, 'maxAttempts must be > 0');
  var delay = initialDelay;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await attemptFn(attempt);
    } catch (e) {
      final isLastAttempt = attempt == maxAttempts - 1;
      final shouldRetry = retryIf?.call(e) ?? true;
      if (isLastAttempt || !shouldRetry) rethrow;
      await Future.delayed(delay);
      delay = Duration(
        milliseconds: min(
          (delay.inMilliseconds * multiplier).round(),
          maxDelay.inMilliseconds,
        ),
      );
    }
  }
  // Unreachable: the loop above always either returns or rethrows on its
  // final iteration.
  throw StateError('retryWithBackoff: exhausted attempts without result');
}
