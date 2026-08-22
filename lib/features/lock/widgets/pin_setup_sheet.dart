import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';

/// Bottom sheet that guides the user through setting up a PIN lock.
///
/// Flow:
///   1. Enter a PIN (>= 4 digits).
///   2. Confirm by entering the same PIN again.
///   3. Returns the salted hash of the confirmed PIN via [Navigator.pop].
///
/// The return value is `String?` -- null if the user cancels. Mirrors
/// [PatternSetupSheet] step-for-step.
class PinSetupSheet extends StatefulWidget {
  const PinSetupSheet({super.key});

  @override
  State<PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends State<PinSetupSheet> {
  _SetupStep _step = _SetupStep.enter;
  String? _firstPin;
  String? _error;
  bool _showError = false;
  int _resetKey = 0; // Force PinLockView rebuild on reset.

  Future<void> _onPinComplete(String pin) async {
    switch (_step) {
      case _SetupStep.enter:
        setState(() {
          _firstPin = pin;
          _step = _SetupStep.confirm;
          _error = null;
          _showError = false;
          _resetKey++;
        });
        break;

      case _SetupStep.confirm:
        if (_firstPin == pin) {
          final hash = await hashPin(pin);
          if (mounted) Navigator.pop(context, hash);
        } else {
          setState(() {
            _error = context.l10n.pinsDontMatch;
            _showError = true;
          });
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              setState(() {
                _step = _SetupStep.enter;
                _firstPin = null;
                _showError = false;
                _error = null;
                _resetKey++;
              });
            }
          });
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);

    final title = _step == _SetupStep.enter
        ? context.l10n.createUnlockPinTitle
        : context.l10n.confirmPinTitle;
    final subtitle = _showError
        ? (_error ?? '')
        : (_step == _SetupStep.enter
              ? context.l10n.enterAtLeast4Digits
              : context.l10n.enterSamePinAgain);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  Icon(
                    Icons.dialpad_rounded,
                    size: 20,
                    color: _showError ? cs.error : cs.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _showError ? cs.error : null,
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
                    color: _showError ? cs.error : cs.onSurfaceVariant,
                    fontWeight: _showError ? FontWeight.bold : null,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Keypad ──────────────────────────────────────────────
              Center(
                child: PinLockView(
                  key: ValueKey(_resetKey),
                  onPinComplete: _onPinComplete,
                  showError: _showError,
                ),
              ),

              const SizedBox(height: 12),

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

enum _SetupStep { enter, confirm }
