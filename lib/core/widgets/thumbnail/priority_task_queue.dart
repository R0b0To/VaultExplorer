import 'dart:async';
import 'dart:collection';

import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/utils/task_priority.dart';

export 'package:vaultexplorer/core/utils/task_priority.dart';

/// A concurrency gate with three priority tiers, replacing the old flat
///
/// The previous `ConcurrencyLimiter` served every caller identically: an
/// on-screen grid tile, the media viewer's off-screen next/prev prefetch,
/// and a background speculative prefetch all queued FIFO with no way for a
/// currently-visible tile's request to jump ahead of one already queued
/// for a tile the user has since scrolled past. It was also documented in
/// three places as LIFO but actually implemented as FIFO.
///
/// This queue fixes both: it services **LIFO within a tier** (the most
/// recently queued request for a given tier is the one most likely to
/// still be wanted — matches scroll behavior, and matches the doc
/// comments' original intent), and a [TaskPriority.visible] request always
/// preempts queued [TaskPriority.adjacent]/[TaskPriority.background] slots
/// up to [maxConcurrency].
///
/// It does **not** preempt work already granted a turn and mid-flight
/// (`FETCHING` in the state machine — see architecture.md Section 5):
/// there is no cancellable native `MethodChannel` call, so "preemption"
/// here only ever means "dequeue a higher-priority *waiting* request
/// first," never "interrupt work already in progress."
///
/// Every admission decision also consults
/// [PlaybackThrottleController.isPlaybackActive]. While a video decode
/// session is active: [TaskPriority.background] work is fully gated (never
/// admitted), [TaskPriority.adjacent] work is reduced to one in flight at a
/// time (e.g. only the *very next* carousel neighbor), and
/// [TaskPriority.visible] work is never gated — it's what's on screen. This
/// is a single, general check every [PriorityTaskQueue] instance applies
/// automatically; no caller needs its own "is a video playing" awareness.
class PriorityTaskQueue {
  int maxConcurrency;
  int _running = 0;
  final Map<TaskPriority, int> _runningByTier = {
    for (final tier in TaskPriority.values) tier: 0,
  };
  final Map<TaskPriority, Queue<Completer<void>>> _waiting = {
    for (final tier in TaskPriority.values) tier: Queue<Completer<void>>(),
  };
  final Map<Completer<void>, TaskPriority> _tierOf = {};

  PriorityTaskQueue(this.maxConcurrency);

  /// Requests a turn. Completes [completer]'s future once granted.
  /// [priority] defaults to [TaskPriority.visible] so existing call sites
  /// that don't yet distinguish tiers behave exactly as before.
  Future<void> acquire(
    Completer<void> completer, {
    TaskPriority priority = TaskPriority.visible,
  }) async {
    _tierOf[completer] = priority;
    if (_canAdmit(priority)) {
      _grant(completer, priority);
      return;
    }
    _waiting[priority]!.addLast(completer);
    await completer.future;
  }

  /// Drops [completer] from the *waiting* queue if it's still there
  /// (no-op if it's already been granted a turn or already completed).
  void cancel(Completer<void> completer) {
    for (final tier in TaskPriority.values) {
      if (_waiting[tier]!.remove(completer)) {
        _tierOf.remove(completer);
        if (!completer.isCompleted) {
          completer.completeError(Exception('Cancelled in queue'));
        }
        return;
      }
    }
  }

  /// Drops every waiting request across every tier.
  void cancelAll() {
    for (final tier in TaskPriority.values) {
      _cancelWaitingIn(tier);
    }
  }

  /// Drops every *waiting* (not yet granted a turn) request in [tier] —
  /// exposed for scroll-fling and video-playback-start hooks (Finding
  /// F-13). Cannot touch requests already mid-flight, same as [cancel].
  void cancelTier(TaskPriority tier) => _cancelWaitingIn(tier);

  void _cancelWaitingIn(TaskPriority tier) {
    final q = _waiting[tier]!;
    while (q.isNotEmpty) {
      final c = q.removeFirst();
      _tierOf.remove(c);
      if (!c.isCompleted) {
        c.completeError(Exception('Cancelled all in queue (tier=$tier)'));
      }
    }
  }

  /// Releases the turn held by [completer], letting the next eligible
  /// waiting request (if any) proceed. Every [acquire] that returns
  /// normally (i.e. wasn't cancelled) must be paired with exactly one
  /// [release] call for the same completer.
  void release(Completer<void> completer) {
    final tier = _tierOf.remove(completer) ?? TaskPriority.visible;
    _running = (_running - 1).clamp(0, maxConcurrency);
    _runningByTier[tier] = ((_runningByTier[tier] ?? 1) - 1).clamp(0, maxConcurrency);
    _drainNext();
  }

  void resize(int newMaxConcurrency) {
    assert(newMaxConcurrency > 0);
    maxConcurrency = newMaxConcurrency;
    _drainNext();
  }

  bool _canAdmit(TaskPriority priority) {
    if (_running >= maxConcurrency) return false;
    return _playbackGateAllows(priority);
  }

  bool _playbackGateAllows(TaskPriority priority) {
    if (!PlaybackThrottleController.isPlaybackActive.value) return true;
    switch (priority) {
      case TaskPriority.visible:
        return true;
      case TaskPriority.adjacent:
        return _runningByTier[TaskPriority.adjacent] == 0;
      case TaskPriority.background:
        return false;
    }
  }

  void _grant(Completer<void> completer, TaskPriority priority) {
    _running++;
    _runningByTier[priority] = (_runningByTier[priority] ?? 0) + 1;
    if (!completer.isCompleted) completer.complete();
  }

  void _drainNext() {
    while (_running < maxConcurrency) {
      final next = _dequeueHighestPriority();
      if (next == null) break;
      _grant(next, _tierOf[next]!);
    }
  }

  /// Tiers are iterated in [TaskPriority.values] declaration order
  /// (visible, adjacent, background), so a waiting `visible` request is
  /// always dequeued ahead of a waiting `adjacent`/`background` one.
  /// Within a tier, the most recently queued (LIFO) request wins.
  Completer<void>? _dequeueHighestPriority() {
    for (final tier in TaskPriority.values) {
      if (!_playbackGateAllows(tier)) continue;
      final q = _waiting[tier]!;
      while (q.isNotEmpty) {
        final c = q.removeLast();
        if (c.isCompleted) continue; // defensive; cancel() already removes it
        return c;
      }
    }
    return null;
  }
}
