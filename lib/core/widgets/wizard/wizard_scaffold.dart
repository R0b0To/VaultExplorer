import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_step_indicator.dart';

/// Full-screen chrome for a linear, multi-step creation wizard.
///
/// The caller's State owns the current step index, builds [stepContent]
/// for whichever step is current, and decides [canProceed] — this widget
/// only renders the progress indicator, the keyboard-safe scroll area, and
/// the bottom Back/Next bar, and reports taps back via [onNext] /
/// [onBackOrExit]. Both the AppBar's leading icon and the system back
/// gesture route through the same [onBackOrExit] callback, so the caller
/// makes one decision — step back if not on the first step, otherwise
/// pop the screen — in one place.
class WizardScaffold extends StatelessWidget {
  final String appBarTitle;
  final int currentStep;
  final int totalSteps;
  final String stepTitle;
  final Widget stepContent;

  /// True while an async operation (final creation, a folder/keyfile pick,
  /// a USB permission request, ...) is in flight. Disables Back/Next and
  /// shows a thin progress line under the AppBar.
  final bool busy;

  /// Snack bar message shown if the person tries to back out while [busy].
  final String busyMessage;

  /// Whether the current step's inputs are complete/valid — gates the
  /// Next/Create button so the person can't proceed with invalid or
  /// missing inputs.
  final bool canProceed;

  final bool isLastStep;

  /// Label for the trailing button — "Next" on every step but the last,
  /// where the caller passes its own create/erase-and-create label.
  final String nextLabel;

  final VoidCallback onNext;
  final VoidCallback onBackOrExit;

  /// Rendered above the Back/Next row on every step, so an async failure
  /// (creation error, folder-pick failure, USB permission denial, ...)
  /// stays visible regardless of which step triggered it.
  final String? errorMessage;

  const WizardScaffold({
    super.key,
    required this.appBarTitle,
    required this.currentStep,
    required this.totalSteps,
    required this.stepTitle,
    required this.stepContent,
    required this.busy,
    required this.busyMessage,
    required this.canProceed,
    required this.isLastStep,
    required this.nextLabel,
    required this.onNext,
    required this.onBackOrExit,
    this.errorMessage,
  });

  void _handleBackOrExit(BuildContext context) {
    if (busy) {
      showAppSnackBar(context, message: busyMessage, tone: AppBannerTone.warning);
      return;
    }
    onBackOrExit();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackOrExit(context);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _handleBackOrExit(context),
          ),
          title: Text(
            appBarTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: busy
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(
                    color: cs.primary,
                    backgroundColor: cs.primaryContainer,
                  ),
                )
              : null,
        ),
        body: SafeArea(
          child: Column(
            children: [
              WizardStepIndicator(
                currentStep: currentStep,
                totalSteps: totalSteps,
                stepTitle: stepTitle,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: stepContent,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (errorMessage != null) ...[
                      InlineErrorBanner(errorMessage!),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                busy ? null : () => _handleBackOrExit(context),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              context.l10n.wizardBackButton,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed:
                                (busy || !canProceed) ? null : onNext,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              shape: const StadiumBorder(),
                            ),
                            child: busy && isLastStep
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation(
                                        cs.onPrimary,
                                      ),
                                    ),
                                  )
                                : Text(
                                    nextLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
