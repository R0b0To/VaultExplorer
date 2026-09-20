import 'dart:async';

/// Collapses a burst of "something changed" signals into one trigger.
///
/// Fires [onFire] once [quiet] has passed with no new [poke] -- or, if the
/// signals never stop (a big copy in progress), once [maxWait] has passed
/// since the first one, so a busy folder still gets synced periodically
/// instead of being postponed forever.
///
/// Uses plain [Timer]s, so tests drive it with `fakeAsync`.
class SyncDebouncer {
  final Duration quiet;
  final Duration maxWait;
  final void Function() onFire;

  Timer? _quietTimer;
  Timer? _maxTimer;

  SyncDebouncer({
    required this.quiet,
    required this.maxWait,
    required this.onFire,
  });

  /// True between the first [poke] of a burst and the moment it fires.
  bool get isPending => _quietTimer != null;

  void poke() {
    _quietTimer?.cancel();
    _quietTimer = Timer(quiet, _fire);
    _maxTimer ??= Timer(maxWait, _fire);
  }

  void cancel() {
    _quietTimer?.cancel();
    _maxTimer?.cancel();
    _quietTimer = null;
    _maxTimer = null;
  }

  void _fire() {
    cancel();
    onFire();
  }
}
