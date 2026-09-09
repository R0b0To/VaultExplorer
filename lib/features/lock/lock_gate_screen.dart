import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/app/main_shell.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/lock/lock_gate_controller.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';

/// Which credential input the gate currently shows. Driven by
/// [AppSettings.masterUnlockMethod], with [password] also reachable at any
/// time via "use password instead" ([LockGateState.showPasswordFallback]) --
/// the real master password stays valid no matter which quick method is
/// configured, exactly as in [ContainerUnlockMethod]'s biometrics/pattern/
/// pin relationship to a vault's real password.
enum _LockGateCredential { biometric, pattern, pin, password }

class LockGateScreen extends ConsumerStatefulWidget {
  /// When true, pops this screen with `true` upon successful unlock
  /// instead of navigating to [MainShell] itself. Allows caller
  /// (e.g. [HiddenVaultTrigger]) to manage route transitions atomically.
  final bool popOnSuccess;

  const LockGateScreen({super.key, this.popOnSuccess = false});

  @override
  ConsumerState<LockGateScreen> createState() => _LockGateScreenState();
}

class _LockGateScreenState extends ConsumerState<LockGateScreen> {
  final _pwCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  void _goToDashboard() {
    if (widget.popOnSuccess) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
  }

  Future<void> _checkPassword() async {
    final l10n = context.l10n;
    final wrongPassword = await ref
        .read(lockGateProvider.notifier)
        .checkPassword(_pwCtrl.text, l10n);
    if (wrongPassword && mounted) {
      _pwCtrl.clear();
    }
  }

  _LockGateCredential _credentialFor(AppSettings s, LockGateState state) {
    if (state.showPasswordFallback) return _LockGateCredential.password;
    switch (s.masterUnlockMethod) {
      case MasterUnlockMethod.biometrics:
        return _LockGateCredential.biometric;
      case MasterUnlockMethod.pattern:
        return _LockGateCredential.pattern;
      case MasterUnlockMethod.pin:
        return _LockGateCredential.pin;
      case MasterUnlockMethod.password:
        return _LockGateCredential.password;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lockGateProvider);
    ref.listen<LockGateState>(lockGateProvider, (previous, next) {
      if (next.navigateTick > (previous?.navigateTick ?? 0)) {
        _goToDashboard();
        return;
      }
      // One-shot auto-biometric-prompt: fires exactly when settings finish
      // loading (null -> non-null) with biometric quick-unlock as the
      // active method -- mirrors the pre-Riverpod screen's post-_init()
      // delayed call.
      final justLoadedWithBiometrics =
          previous?.settings == null &&
          next.settings?.masterUnlockMethod == MasterUnlockMethod.biometrics;
      if (justLoadedWithBiometrics) {
        final l10n = context.l10n;
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            ref.read(lockGateProvider.notifier).tryBiometric(l10n);
          }
        });
      }
    });

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (state.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    final s = state.settings!;
    final isLockedOut = state.isLockedOut;
    final credential = _credentialFor(s, state);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    context.l10n.brandNameNoSpace,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.enterPasswordSubtitle,
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  ..._buildCredential(
                    credential: credential,
                    state: state,
                    isLockedOut: isLockedOut,
                    cs: cs,
                    textTheme: textTheme,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCredential({
    required _LockGateCredential credential,
    required LockGateState state,
    required bool isLockedOut,
    required ColorScheme cs,
    required TextTheme textTheme,
  }) {
    switch (credential) {
      case _LockGateCredential.biometric:
        return [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.fingerprint_rounded,
              size: 56,
              color: cs.primary,
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 16),
            Text(
              state.error!,
              style: textTheme.bodySmall?.copyWith(color: cs.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ref
                      .read(lockGateProvider.notifier)
                      .setShowPasswordFallback(true),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(context.l10n.usePasswordButtonLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: isLockedOut
                      ? null
                      : () => ref
                            .read(lockGateProvider.notifier)
                            .tryBiometric(context.l10n),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(context.l10n.authenticateButtonLabel),
                ),
              ),
            ],
          ),
        ];

      case _LockGateCredential.pattern:
        return [
          Text(
            context.l10n.drawUnlockPatternTitle,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: PatternLockView(
              key: ValueKey(state.patternResetKey),
              enabled: !isLockedOut,
              showError: state.patternError,
              onPatternComplete: (pattern) => ref
                  .read(lockGateProvider.notifier)
                  .onPatternComplete(pattern, context.l10n),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: textTheme.bodySmall?.copyWith(color: cs.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => ref
                .read(lockGateProvider.notifier)
                .setShowPasswordFallback(true),
            child: Text(context.l10n.usePasswordInsteadButtonLabel),
          ),
        ];

      case _LockGateCredential.pin:
        return [
          Text(
            context.l10n.enterUnlockPinTitle,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: PinLockView(
              key: ValueKey(state.pinResetKey),
              enabled: !isLockedOut,
              showError: state.pinError,
              onPinComplete: (pin) => ref
                  .read(lockGateProvider.notifier)
                  .onPinComplete(pin, context.l10n),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: textTheme.bodySmall?.copyWith(color: cs.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => ref
                .read(lockGateProvider.notifier)
                .setShowPasswordFallback(true),
            child: Text(context.l10n.usePasswordInsteadButtonLabel),
          ),
        ];

      case _LockGateCredential.password:
        return [
          TextField(
            controller: _pwCtrl,
            obscureText: _obscure,
            enabled: !isLockedOut && !state.checking,
            autofocus: true,
            autofillHints: null,
            onSubmitted: (_) => _checkPassword(),
            decoration: InputDecoration(
              labelText: context.l10n.masterPasswordFieldLabelTitleCase,
              prefixIcon: const Icon(Icons.key_rounded, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: textTheme.bodySmall?.copyWith(color: cs.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (state.checking || isLockedOut)
                ? null
                : _checkPassword,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: state.checking
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                    ),
                  )
                : Text(context.l10n.unlock),
          ),
        ];
    }
  }
}