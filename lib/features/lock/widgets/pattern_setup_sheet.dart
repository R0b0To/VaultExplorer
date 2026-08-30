import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_setup_controller.dart';

/// Bottom sheet that guides the user through setting up a pattern lock.
///
/// Flow:
///   1. Draw a pattern (≥ 4 dots).
///   2. Confirm by drawing the same pattern again.
///   3. Returns the SHA-256 hash of the confirmed pattern via [Navigator.pop].
///
/// The return value is `String?` — null if the user cancels.
class PatternSetupSheet extends ConsumerStatefulWidget {
  const PatternSetupSheet({super.key});

  @override
  ConsumerState<PatternSetupSheet> createState() => _PatternSetupSheetState();
}

class _PatternSetupSheetState extends ConsumerState<PatternSetupSheet> {
  void _onPatternComplete(List<int> pattern) {
    ref.read(patternSetupProvider.notifier).submitPattern(
      pattern,
      tooShortMessage: context.l10n.connectAtLeast4Dots,
      mismatchMessage: context.l10n.patternsDontMatch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patternSetupProvider);
    ref.listen<PatternSetupState>(patternSetupProvider, (previous, next) {
      if (next.completedHash != null && previous?.completedHash == null) {
        Navigator.pop(context, next.completedHash);
      }
    });

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;

    final title = state.step == PatternSetupStep.draw
        ? context.l10n.drawUnlockPatternTitle
        : context.l10n.confirmPatternTitle;
    final subtitle = state.showError
        ? (state.error ?? '')
        : (state.step == PatternSetupStep.draw
              ? context.l10n.connectAtLeast4Dots
              : context.l10n.drawSamePatternAgain);

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
                      flex: 5,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.pattern_rounded,
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
                    // ── Right: Scaled Pattern Grid ─────────────────────────
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: mq.size.height * 0.7,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: PatternLockView(
                              key: ValueKey(state.resetKey),
                              onPatternComplete: _onPatternComplete,
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
                          Icons.pattern_rounded,
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
                    const SizedBox(height: 24),

                    // ── Pattern grid ────────────────────────────────────────
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PatternLockView(
                          key: ValueKey(state.resetKey),
                          onPatternComplete: _onPatternComplete,
                          showError: state.showError,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

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