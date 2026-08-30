import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_setup_controller.dart';

/// Bottom sheet that guides the user through setting up a PIN lock.
///
/// Flow:
///   1. Enter a PIN (>= 4 digits).
///   2. Confirm by entering the same PIN again.
///   3. Returns the salted hash of the confirmed PIN via [Navigator.pop].
///
/// The return value is `String?` -- null if the user cancels. Mirrors
/// [PatternSetupSheet] step-for-step.
class PinSetupSheet extends ConsumerStatefulWidget {
  const PinSetupSheet({super.key});

  @override
  ConsumerState<PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends ConsumerState<PinSetupSheet> {
  void _onPinComplete(String pin) {
    ref.read(pinSetupProvider.notifier).submitPin(
      pin,
      mismatchMessage: context.l10n.pinsDontMatch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pinSetupProvider);
    ref.listen<PinSetupState>(pinSetupProvider, (previous, next) {
      if (next.completedHash != null && previous?.completedHash == null) {
        Navigator.pop(context, next.completedHash);
      }
    });

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;

    final title = state.step == PinSetupStep.enter
        ? context.l10n.createUnlockPinTitle
        : context.l10n.confirmPinTitle;
    final subtitle = state.showError
        ? (state.error ?? '')
        : (state.step == PinSetupStep.enter
              ? context.l10n.enterAtLeast4Digits
              : context.l10n.enterSamePinAgain);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: isLandscape
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Left: Info & Cancel Button ─────────────────────────
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.dialpad_rounded,
                                size: 22,
                                color: state.showError ? cs.error : cs.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  title,
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: state.showError ? cs.error : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: textTheme.bodySmall?.copyWith(
                              color: state.showError ? cs.error : cs.onSurfaceVariant,
                              fontWeight: state.showError ? FontWeight.bold : null,
                            ),
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(context.l10n.cancel),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    const VerticalDivider(width: 1),
                    const SizedBox(width: 24),
                    // ── Right: Scaled PIN Dialpad ─────────────────────────
                    Expanded(
                      flex: 6,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: mq.size.height * 0.72,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: PinLockView(
                              key: ValueKey(state.resetKey),
                              onPinComplete: _onPinComplete,
                              showError: state.showError,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Header ──────────────────────────────────────────────
                    Row(
                      children: [
                        Icon(
                          Icons.dialpad_rounded,
                          size: 20,
                          color: state.showError ? cs.error : cs.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: state.showError ? cs.error : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: state.showError ? cs.error : cs.onSurfaceVariant,
                          fontWeight: state.showError ? FontWeight.bold : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Keypad ──────────────────────────────────────────────
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PinLockView(
                          key: ValueKey(state.resetKey),
                          onPinComplete: _onPinComplete,
                          showError: state.showError,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Cancel button ───────────────────────────────────────
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        context.l10n.cancel,
                        style: textTheme.labelLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}