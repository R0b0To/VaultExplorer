import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/dashboard/widgets/pattern_pin_verify_controller.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';

class PatternVerifySheet extends ConsumerStatefulWidget {
  final String storedHash;
  const PatternVerifySheet({super.key, required this.storedHash});
  @override
  ConsumerState<PatternVerifySheet> createState() => _PatternVerifySheetState();
}

class _PatternVerifySheetState extends ConsumerState<PatternVerifySheet> {
  void _onPatternComplete(List<int> pattern) {
    ref
        .read(patternVerifyProvider(widget.storedHash).notifier)
        .submitPattern(pattern, incorrectMessage: context.l10n.incorrectPatternError);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patternVerifyProvider(widget.storedHash));
    ref.listen<VerifyState>(patternVerifyProvider(widget.storedHash), (previous, next) {
      if (next.verified && (previous == null || !previous.verified)) {
        Navigator.pop(context, widget.storedHash);
      }
    });

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    Widget header = Column(
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
                context.l10n.verifyPatternTitle,
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
          state.showError ? (state.error ?? '') : ' ',
          style: textTheme.bodySmall?.copyWith(
            color: state.showError ? cs.error : Colors.transparent,
            fontWeight: state.showError ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );

    Widget cancelButton = TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      child: Text(
        context.l10n.cancel,
        style: textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
      ),
    );

    Widget patternView = PatternLockView(
      key: ValueKey(state.resetKey),
      onPatternComplete: _onPatternComplete,
      showError: state.showError,
    );

    return AppBottomSheet(
      child: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: isLandscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          const SizedBox(height: 24),
                          cancelButton,
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    patternView,
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 24),
                    Center(child: patternView),
                    const SizedBox(height: 16),
                    Center(child: cancelButton),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ),
    );
  }
}

class PinVerifySheet extends ConsumerStatefulWidget {
  final String storedHash;
  const PinVerifySheet({super.key, required this.storedHash});
  @override
  ConsumerState<PinVerifySheet> createState() => _PinVerifySheetState();
}

class _PinVerifySheetState extends ConsumerState<PinVerifySheet> {
  void _onPinComplete(String pin) {
    ref
        .read(pinVerifyProvider(widget.storedHash).notifier)
        .submitPin(pin, incorrectMessage: context.l10n.incorrectPinError);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pinVerifyProvider(widget.storedHash));
    ref.listen<VerifyState>(pinVerifyProvider(widget.storedHash), (previous, next) {
      if (next.verified && (previous == null || !previous.verified)) {
        Navigator.pop(context, widget.storedHash);
      }
    });

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    Widget header = Column(
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
                context.l10n.verifyPinTitle,
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
          state.showError ? (state.error ?? '') : ' ',
          style: textTheme.bodySmall?.copyWith(
            color: state.showError ? cs.error : Colors.transparent,
            fontWeight: state.showError ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );

    Widget cancelButton = TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      child: Text(
        context.l10n.cancel,
        style: textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
      ),
    );

    Widget pinView = PinLockView(
      key: ValueKey(state.resetKey),
      onPinComplete: _onPinComplete,
      showError: state.showError,
    );

    return AppBottomSheet(
      child: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: isLandscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          const SizedBox(height: 24),
                          cancelButton,
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    pinView,
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 28),
                    Center(child: pinView),
                    const SizedBox(height: 16),
                    Center(child: cancelButton),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ),
    );
  }
}
