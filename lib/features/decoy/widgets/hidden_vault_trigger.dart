import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/hold_trigger.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';

/// Wraps a widget (an AppBar title, a page counter, ...) with the hidden
/// "hold for 3 seconds" gesture that opens the real vault's
/// [LockGateScreen] from inside the Mask Mode decoy reader.
///
/// Design notes (docs/architecture.md §7, ADR-028):
///
/// * Timing/gating is delegated to [HoldTrigger], measured from raw
///   touch-down via [onTapDown]/[onTapUp]/[onTapCancel] rather than
///   [GestureDetector.onLongPress] -- the latter's own ~500ms recognition
///   delay would sit *in front of* the 3-second hold, and layering a timer
///   on top of a gesture recognizer that already has its own internal
///   timing makes the actual required hold duration harder to reason
///   about than just measuring from the first touch.
/// * No visual feedback at all while holding (no ripple override, no
///   progress ring, no color change): the entire point is that this looks
///   like an inert app-bar title until it's been held for the full
///   duration. A haptic pulse only fires once, on success.
/// * Navigates with [Navigator.push], not `pushReplacement` -- so that
///   backing out of an authenticated vault session returns to the decoy
///   UI rather than leaving the vault as the screen the app rests on. The
///   OS-level launcher icon/label disguise is untouched by this trigger;
///   that only ever changes via the explicit Settings toggle (ADR-025).
class HiddenVaultTrigger extends StatefulWidget {
  final Widget child;

  const HiddenVaultTrigger({super.key, required this.child});

  @override
  State<HiddenVaultTrigger> createState() => _HiddenVaultTriggerState();
}

class _HiddenVaultTriggerState extends State<HiddenVaultTrigger> {
  static const _holdDuration = Duration(seconds: 2);

  late final _hold = HoldTrigger(duration: _holdDuration, onComplete: _fire);

  Future<void> _fire() async {
    await HapticFeedback.heavyImpact();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LockGateScreen()),
    );
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _hold.start(),
      onTapUp: (_) => _hold.cancel(),
      onTapCancel: _hold.cancel,
      child: widget.child,
    );
  }
}
