import 'dart:async';
import 'package:flutter/foundation.dart';

/// Fires [onComplete] once, the first time [start] has been called without
/// an intervening [cancel] for at least [duration].
///
/// This is the timing/gating logic behind
/// `lib/features/decoy/widgets/hidden_vault_trigger.dart`'s hold gesture,
/// pulled out into its own dependency-free class specifically so it can be
/// unit-tested with `package:fake_async` (see
/// `test/core/utils/hold_trigger_test.dart`) without needing a widget tree
/// -- and, for this particular feature, without needing to build the real
/// screen the widget navigates to on success.
class HoldTrigger {
  HoldTrigger({required this.duration, required this.onComplete});

  final Duration duration;
  final VoidCallback onComplete;

  Timer? _timer;
  bool _fired = false;

  /// Begins (or restarts) the hold. Call from the gesture's "pressed" edge
  /// (e.g. `onTapDown`).
  void start() {
    _timer?.cancel();
    _fired = false;
    _timer = Timer(duration, _complete);
  }

  /// Aborts the current hold without firing. Call from the gesture's
  /// "released"/"interrupted" edges (e.g. `onTapUp`, `onTapCancel`).
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _complete() {
    if (_fired) return;
    _fired = true;
    onComplete();
  }

  /// Releases the underlying timer. Call from the owning widget's
  /// `dispose`.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
