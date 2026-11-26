import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_step_indicator.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_window_style.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';

/// Full-screen chrome for a linear, multi-step creation wizard.
///
/// In portrait mode, navigation buttons render in a traditional bottom bar.
/// In landscape mode, the bottom bar disappears and converts into a compact
/// right-hand sidebar, freeing up 100% of the screen's vertical space for content.
///
/// In a native desktop window (see `pushWindowedPage`) it is laid out like a
/// desktop dialog instead: the step title on the left, the form on the plain
/// window surface, and Back / Next pinned to a footer, right-aligned.
class WizardScaffold extends StatelessWidget {
  final String appBarTitle;
  final int currentStep;
  final int totalSteps;
  final String stepTitle;
  final Widget stepContent;
  final bool busy;
  final String busyMessage;
  final bool canProceed;
  final bool isLastStep;
  final String nextLabel;
  final VoidCallback onNext;
  final VoidCallback onBackOrExit;
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

  Widget _buildBackButton(BuildContext context, ColorScheme cs, {double height = 50}) {
    return OutlinedButton(
      onPressed: busy ? null : () => _handleBackOrExit(context),
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(height),
        shape: const StadiumBorder(),
      ),
      child: Text(
        context.l10n.wizardBackButton,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: height < 46 ? 14 : 15,
        ),
      ),
    );
  }

  Widget _buildNextButton(BuildContext context, ColorScheme cs, {double height = 50}) {
    return FilledButton(
      onPressed: (busy || !canProceed) ? null : onNext,
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(height),
        shape: const StadiumBorder(),
      ),
      child: busy && isLastStep
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(cs.onPrimary),
              ),
            )
          : Text(
              nextLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: height < 46 ? 14 : 15,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (SecondaryWindowScope.maybeOf(context) != null) {
      return _buildWindowed(context);
    }
    final cs = context.colors;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final counterText = context.l10n.xOfYCounter(currentStep + 1, totalSteps);

    return Semantics(
      label: appBarTitle,
      container: true,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleBackOrExit(context);
        },
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: isLandscape ? 44 : kToolbarHeight,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, size: isLandscape ? 20 : 24),
              onPressed: () => _handleBackOrExit(context),
            ),
            title: isLandscape
                ? Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          counterText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          stepTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        counterText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        stepTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(isLandscape ? 3 : 4),
              child: busy
                  ? LinearProgressIndicator(
                      minHeight: isLandscape ? 3 : 4,
                      color: cs.primary,
                      backgroundColor: cs.primaryContainer,
                    )
                  : WizardStepIndicator(
                      currentStep: currentStep,
                      totalSteps: totalSteps,
                    ),
            ),
          ),
          body: SafeArea(
            child: isLandscape
                ? _buildLandscapeLayout(context, cs)
                : _buildPortraitLayout(context, cs),
          ),
        ),
      ),
    );
  }

  /// Landscape: Content on the left, vertical action sidebar on the right
  Widget _buildLandscapeLayout(BuildContext context, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: [
              if (errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: InlineErrorBanner(errorMessage!),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: stepContent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 168,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
            border: Border(
              left: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              _buildNextButton(context, cs, height: 44),
              const SizedBox(height: 10),
              _buildBackButton(context, cs, height: 44),
            ],
          ),
        ),
      ],
    );
  }

  /// Portrait: Content on top, standard bottom action bar
  Widget _buildPortraitLayout(BuildContext context, ColorScheme cs) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: stepContent,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (errorMessage != null) ...[
                InlineErrorBanner(errorMessage!),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: _buildBackButton(context, cs, height: 52),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildNextButton(context, cs, height: 52),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The desktop window layout: header, scrolling form, pinned footer.
  Widget _buildWindowed(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;
    final counterText = l10n.xOfYCounter(currentStep + 1, totalSteps);
    final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(kWizardWindowRadius)),
    );
    const buttonSize = WidgetStatePropertyAll<Size>(Size(112, 40));

    return WizardWindowStyle(
      child: Semantics(
        label: appBarTitle,
        container: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBackOrExit(context);
          },
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              // Escape closes the window from the first step; later it would
              // throw away what has been entered, so it does nothing there.
              if (currentStep == 0)
                const SingleActivator(LogicalKeyboardKey.escape): () => _handleBackOrExit(context),
            },
            child: Scaffold(
              backgroundColor: cs.surface,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                    child: SizedBox(
                      height: 4,
                      child: busy
                          ? LinearProgressIndicator(color: cs.primary, backgroundColor: cs.primaryContainer)
                          : WizardStepIndicator(currentStep: currentStep, totalSteps: totalSteps),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          counterText,
                          style: textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stepTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        primary: true,
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: stepContent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                      child: InlineErrorBanner(errorMessage!),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: wizardWindowOutline(cs))),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Row(
                        children: [
                          if (busy)
                            Expanded(
                              child: Text(
                                busyMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          TextButton(
                            onPressed: busy ? null : () => _handleBackOrExit(context),
                            style: ButtonStyle(minimumSize: buttonSize, shape: buttonShape),
                            child: Text(currentStep == 0 ? l10n.cancel : l10n.wizardBackButton),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: (busy || !canProceed) ? null : onNext,
                            style: ButtonStyle(minimumSize: buttonSize, shape: buttonShape),
                            child: busy && isLastStep
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.onPrimary),
                                  )
                                : Text(nextLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
