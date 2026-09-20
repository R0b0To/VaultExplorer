import 'dart:async';

/// Runs one vault's sync rules strictly one at a time.
///
/// A vault's rules share one ledger, and a run reads and rewrites files on
/// both sides, so two runs must never overlap. Requests that arrive while a
/// run is in progress are queued, and asking for a rule that is *already
/// queued* changes nothing -- a burst of change events costs one run, not
/// one per event. A request for the rule that is running right now is
/// queued again, because the change may have landed after that run scanned.
class SyncRunScheduler {
  final Future<void> Function(String ruleId) _run;

  final Set<String> _queued = <String>{}; // insertion-ordered
  bool _draining = false;
  bool _closed = false;
  String? _current;
  Completer<void>? _idle;

  SyncRunScheduler(this._run);

  /// The rule being run right now, if any.
  String? get current => _current;

  bool get isBusy => _draining;

  /// True if [ruleId] is running or waiting for its turn.
  bool isActive(String ruleId) =>
      _current == ruleId || _queued.contains(ruleId);

  /// Completes when the queue has drained (including requests made while it
  /// was draining). Already complete when nothing is running.
  Future<void> get idle => _idle?.future ?? Future<void>.value();

  void request(String ruleId) {
    if (_closed) return;
    _queued.add(ruleId);
    if (_draining) return;
    _draining = true;
    _idle = Completer<void>();
    unawaited(_drain());
  }

  /// Drops everything queued and refuses new requests. A run already in
  /// progress is left to wind down (it is stopped through its own
  /// cancellation token).
  void close() {
    _closed = true;
    _queued.clear();
  }

  Future<void> _drain() async {
    try {
      while (!_closed && _queued.isNotEmpty) {
        final id = _queued.first;
        _queued.remove(id);
        _current = id;
        try {
          await _run(id);
        } catch (_) {
          // One failing rule must not stop the others.
        }
        _current = null;
      }
    } finally {
      _current = null;
      _draining = false;
      final idle = _idle;
      _idle = null;
      idle?.complete();
    }
  }
}
