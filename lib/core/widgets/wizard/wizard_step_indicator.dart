import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Thin segmented progress bar for a linear multi-step wizard: one filled
/// segment per completed/current step, shown edge-to-edge in the
/// [WizardScaffold] AppBar's `bottom` slot.
///
/// Deliberately bar-only — the step counter and step title live in the
/// AppBar's title instead (see [WizardScaffold]), so this stays a single,
/// compact strip regardless of orientation rather than a text block that
/// eats into the limited height available in landscape.
class WizardStepIndicator extends StatelessWidget {
  /// 0-based index of the step currently shown.
  final int currentStep;
  final int totalSteps;

  const WizardStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return Row(
      children: List.generate(totalSteps, (i) {
        final filled = i <= currentStep;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 3),
            child: AnimatedContainer(
              duration: AppMotion.medium1,
              curve: AppMotion.standard,
              height: 4,
              decoration: BoxDecoration(
                color: filled ? cs.primary : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
        );
      }),
    );
  }
}