import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/app/main_shell.dart';
import 'package:vaultexplorer/features/lock/lock_gate_controller.dart';

class LockGateScreen extends ConsumerStatefulWidget {
  const LockGateScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lockGateProvider);
    ref.listen<LockGateState>(lockGateProvider, (previous, next) {
      if (next.navigateTick > (previous?.navigateTick ?? 0)) {
        _goToDashboard();
        return;
      }
      // One-shot auto-biometric-prompt: fires exactly when settings finish
      // loading (null -> non-null) with fingerprint unlock enabled --
      // mirrors the pre-Riverpod screen's post-_init() delayed call.
      final justLoadedWithFingerprint =
          previous?.settings == null &&
          next.settings?.masterPasswordIsFingerprint == true;
      if (justLoadedWithFingerprint) {
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
                  TextField(
                    controller: _pwCtrl,
                    obscureText: _obscure,
                    enabled: !isLockedOut && !state.checking,
                    autofocus: !s.masterPasswordIsFingerprint,
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
                  if (s.masterPasswordIsFingerprint) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: isLockedOut
                          ? null
                          : () => ref
                                .read(lockGateProvider.notifier)
                                .tryBiometric(context.l10n),
                      icon: const Icon(Icons.fingerprint_rounded, size: 20),
                      label: Text(context.l10n.useBiometric),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}