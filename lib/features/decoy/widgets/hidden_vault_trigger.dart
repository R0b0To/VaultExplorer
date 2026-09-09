import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/app/main_shell.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/core/utils/hold_trigger.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';

class HiddenVaultTrigger extends ConsumerStatefulWidget {
  final Widget child;

  /// Runs right after successful unlock -- for state that needs
  /// to be waiting on the vault side by the time whatever screen follows
  /// unlock ([MainShell]) mounts. See `decoy_share_import_flow.dart`'s use
  /// of this for handing a shared file that arrived while disguised over
  /// to the real share-import flow.
  /// If authentication is cancelled, this callback is NOT invoked, preserving
  /// any pending share buffer for the local screen.
  final Future<void> Function()? onBeforeReveal;

  const HiddenVaultTrigger({super.key, required this.child, this.onBeforeReveal});

  @override
  ConsumerState<HiddenVaultTrigger> createState() => _HiddenVaultTriggerState();
}

class _HiddenVaultTriggerState extends ConsumerState<HiddenVaultTrigger> {
  static const _holdDuration = Duration(seconds: 2);
  late final _hold = HoldTrigger(duration: _holdDuration, onComplete: _fire);

  Future<void> _fire() async {
    await HapticFeedback.heavyImpact();
    if (!mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final secureScreenPolicy = ref.read(secureScreenPolicyProvider);
    final onBeforeReveal = widget.onBeforeReveal;

    // 1. Arm screenshot policy according to user settings before entering vault
    final settings = await ref.read(appSettingsServiceProvider).loadSettings();
    await secureScreenPolicy.apply(
      preference: settings.blockScreenshots,
    );

    if (!mounted) return;

    // 2. Open LockGateScreen and await auth challenge result.
    // Keeping this screen's BuildContext alive throughout authentication prevents
    // premature disposal and ensures cancellation preserves the transient route.
    final unlocked = await navigator.push<bool>(
      MaterialPageRoute(builder: (_) => const LockGateScreen(popOnSuccess: true)),
    );

    // 3. If user backed out / cancelled authentication, re-disable screenshot
    // blocking for decoy mode and keep the host screen (e.g. share picker) intact.
    // Notice that onBeforeReveal was not called, so any pending share buffer is
    // preserved for the local picker.
    if (unlocked != true) {
      unawaited(secureScreenPolicy.disableForDecoy());
      return;
    }

    // 4. Authentication succeeded!
    // Commit the handoff now (e.g. moving share items to real vault buffer).
    if (onBeforeReveal != null) {
      try {
        await onBeforeReveal();
      } catch (_) {
        // Best-effort -- see the field's doc comment.
      }
    }

    // 5. Atomic route replacement:
    // Dismiss any transient screens (like the share picker) and push MainShell
    // directly over the root decoy screen (route.isFirst).
    // This guarantees that exiting the real vault returns directly to the decoy
    // file manager root, never back into the transient share picker.
    await navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => route.isFirst,
    );

    // 6. When the user eventually exits the vault back to decoy root, restore
    // screenshot blocking policy for decoy mode.
    unawaited(secureScreenPolicy.disableForDecoy());
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