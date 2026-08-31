import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/utils/hold_trigger.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';

class HiddenVaultTrigger extends ConsumerStatefulWidget {
  final Widget child;
  const HiddenVaultTrigger({super.key, required this.child});

  @override
  ConsumerState<HiddenVaultTrigger> createState() => _HiddenVaultTriggerState();
}

class _HiddenVaultTriggerState extends ConsumerState<HiddenVaultTrigger> {
  static const _holdDuration = Duration(seconds: 2);
  late final _hold = HoldTrigger(duration: _holdDuration, onComplete: _fire);

  Future<void> _fire() async {
    await HapticFeedback.heavyImpact();
    if (!mounted) return;

    // 1. Arm screenshot policy according to user settings before entering vault
    final settings = await ref.read(appSettingsServiceProvider).loadSettings();
    await SecureScreenPolicy.apply(preference: settings.blockScreenshots);

    if (!mounted) return;

    // 2. Open LockGateScreen
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LockGateScreen()),
    );

    // 3. If user backed out of the lock gate back to the decoy screen, disable screenshot blocking again
    if (!mounted) return;
    unawaited(SecureScreenPolicy.disableForDecoy());
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