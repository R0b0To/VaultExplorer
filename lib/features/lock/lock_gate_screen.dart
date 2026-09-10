import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/app/main_shell.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart';
import 'package:vaultexplorer/features/lock/lock_gate_controller.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';

enum _LockGateCredential { biometric, pattern, pin, password }

class LockGateScreen extends ConsumerStatefulWidget {
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

  void _goToDecoyContainer(MountedContainer container) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => FileBrowserScreen(
          container: container,
          resolveContainer: (volId) =>
              volId == container.volId ? container : null,
          onUserActivity: () {},
          showBackButton: false,
        ),
      ),
    );
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
      if (next.decoyNavigateTick > (previous?.decoyNavigateTick ?? 0)) {
        final container = next.decoyContainer;
        if (container != null) _goToDecoyContainer(container);
        return;
      }
      if (next.navigateTick > (previous?.navigateTick ?? 0)) {
        _goToDashboard();
        return;
      }
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

    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;

    return Scaffold(
      body: SafeArea(
        child: isLandscape
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Left: Branding, Info, Error & Fallback Action ──
                    Expanded(
                      flex: 4,
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: Image.asset(
                                    'assets/images/app_icon.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                context.l10n.brandNameNoSpace,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.l10n.enterPasswordSubtitle,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (state.error != null &&
                                  credential != _LockGateCredential.password) ...[
                                const SizedBox(height: 8),
                                Text(
                                  state.error!,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (credential == _LockGateCredential.pattern ||
                                  credential == _LockGateCredential.pin) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () => ref
                                      .read(lockGateProvider.notifier)
                                      .setShowPasswordFallback(true),
                                  child: Text(
                                    context.l10n.usePasswordInsteadButtonLabel,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const VerticalDivider(width: 1),
                    const SizedBox(width: 16),
                    // ── Right: Scaled Lock View (Directly Bounded, No Extra Column) ──
                    Expanded(
                      flex: 6,
                      child: Center(
                        child: _buildLandscapeRightSide(
                          credential: credential,
                          state: state,
                          isLockedOut: isLockedOut,
                          cs: cs,
                          textTheme: textTheme,
                          mq: mq,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Center(
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
                        ..._buildPortraitCredential(
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

  Widget _buildLandscapeRightSide({
    required _LockGateCredential credential,
    required LockGateState state,
    required bool isLockedOut,
    required ColorScheme cs,
    required TextTheme textTheme,
    required MediaQueryData mq,
  }) {
    switch (credential) {
      case _LockGateCredential.pattern:
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: mq.size.height * 0.74,
          ),
          child: FittedBox(
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
        );

      case _LockGateCredential.pin:
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: mq.size.height * 0.76,
          ),
          child: FittedBox(
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
        );

      case _LockGateCredential.biometric:
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fingerprint_rounded,
                  size: 44,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ref
                          .read(lockGateProvider.notifier)
                          .setShowPasswordFallback(true),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
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
                        minimumSize: const Size(0, 44),
                      ),
                      child: Text(context.l10n.authenticateButtonLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case _LockGateCredential.password:
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  const SizedBox(height: 8),
                  Text(
                    state.error!,
                    style: textTheme.bodySmall?.copyWith(color: cs.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: (state.checking || isLockedOut)
                      ? null
                      : _checkPassword,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
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
              ],
            ),
          ),
        );
    }
  }

  List<Widget> _buildPortraitCredential({
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