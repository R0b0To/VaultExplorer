import 'dart:async';

/// Generic bounded-concurrency gate: at most [maxConcurrent] holders of
/// [acquire] proceed at once, everyone else queues in FIFO order until a
/// slot is [release]d.
///
/// This used to exist as three separate, functionally identical private
/// classes -- `_CopySemaphore` in `file_operation_service.dart` (bounding
/// concurrent copy/move item processing), `_ScanSemaphore` in
/// `file_browser_screen.dart` (bounding concurrent directory listings
/// during a "play media here" recursive scan), and a third `_CopySemaphore`
/// duplicated *again* inside test/file_operation_service_test.dart --
/// unavoidably, since the production one was file-private and the test
/// couldn't reach it. None could see any of the others' definitions, so
/// the same fix -- and the same bug, if one is ever found -- would have
/// had to land three times. Consolidated into one shared, independently
/// testable primitive as part of the file-browser-screen decomposition
/// (tech-debt audit, Sept 2026); the test file now imports this and tests
/// it directly instead of a same-shaped stand-in.
class BoundedSemaphore {
  final int maxConcurrent;
  int _running = 0;
  final _queue = <Completer<void>>[];

  BoundedSemaphore(this.maxConcurrent);

  Future<void> acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _running = (_running - 1).clamp(0, maxConcurrent);
    }
  }

  /// Current number of holders inside [acquire] (i.e. actively running,
  /// not queued). Exposed for tests -- the test suite's own
  /// `_CopySemaphore` fixture (a *third* copy of this same class, kept in
  /// test/file_operation_service_test.dart purely because the production
  /// one was file-private and unreachable from a test) already had these,
  /// which is what made using it as the reference shape here easy.
  int get running => _running;

  /// Number of callers currently queued in [acquire], waiting for a slot.
  int get waiting => _queue.length;
}
