import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Segmented progress bar + "current / total" caption + step title, shown
/// at the top of every [WizardScaffold] step.
///
/// Reused as-is by every creation wizard in the app (container/vault
/// creation, USB formatting) so they all agree on one progress look rather
/// than each hand-rolling its own stepper chrome.
class WizardStepIndicator extends StatelessWidget {
  /// 0-based index of the step currently shown.
  final int currentStep;
  final int totalSteps;

  /// Already-localized short title for the current step (e.g. "Basic
  /// Info") — doubles as that step's on-page heading.
  final String stepTitle;

  const WizardStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.stepTitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(totalSteps, (i) {
              final filled = i <= currentStep;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == totalSteps - 1 ? 0 : 6,
                  ),
                  child: AnimatedContainer(
                    duration: AppMotion.medium1,
                    curve: AppMotion.standard,
                    height: 5,
                    decoration: BoxDecoration(
                      color: filled
                          ? cs.primary
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.xOfYCounter(currentStep + 1, totalSteps),
            style: textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stepTitle,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
