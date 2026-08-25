import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';

/// Bottom sheet that guides the user through setting up a pattern lock.
///
/// Flow:
///   1. Draw a pattern (≥ 4 dots).
///   2. Confirm by drawing the same pattern again.
///   3. Returns the SHA-256 hash of the confirmed pattern via [Navigator.pop].
///
/// The return value is `String?` — null if the user cancels.
class PatternSetupSheet extends StatefulWidget {
  const PatternSetupSheet({super.key});

  @override
  State<PatternSetupSheet> createState() => _PatternSetupSheetState();
}

class _PatternSetupSheetState extends State<PatternSetupSheet> {
  _SetupStep _step = _SetupStep.draw;
  List<int>? _firstPattern;
  String? _error;
  bool _showError = false;
  int _resetKey = 0; // Force PatternLockView rebuild on reset.

  Future<void> _onPatternComplete(List<int> pattern) async {
    if (pattern.length < 4) {
      setState(() {
        _error = context.l10n.connectAtLeast4Dots;
        _showError = true;
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _showError = false;
            _resetKey++;
          });
        }
      });
      return;
    }

    switch (_step) {
      case _SetupStep.draw:
        setState(() {
          _firstPattern = pattern;
          _step = _SetupStep.confirm;
          _error = null;
          _showError = false;
          _resetKey++;
        });
        break;

      case _SetupStep.confirm:
        if (listEquals(_firstPattern, pattern)) {
          final hash = await hashPattern(pattern);
          if (mounted) Navigator.pop(context, hash);
        } else {
          setState(() {
            _error = context.l10n.patternsDontMatch;
            _showError = true;
          });
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              setState(() {
                _step = _SetupStep.draw;
                _firstPattern = null;
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
    final isLandscape = mq.orientation == Orientation.landscape;

    final title = _step == _SetupStep.draw
        ? context.l10n.drawUnlockPatternTitle
        : context.l10n.confirmPatternTitle;
    final subtitle = _showError
        ? (_error ?? '')
        : (_step == _SetupStep.draw
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
                                color: _showError ? cs.error : cs.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  title,
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: _showError ? cs.error : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: textTheme.bodySmall?.copyWith(
                              color: _showError ? cs.error : cs.onSurfaceVariant,
                              fontWeight: _showError ? FontWeight.bold : null,
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
                              key: ValueKey(_resetKey),
                              onPatternComplete: _onPatternComplete,
                              showError: _showError,
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
                          color: _showError ? cs.error : cs.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _showError ? cs.error : null,
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
                          color: _showError ? cs.error : cs.onSurfaceVariant,
                          fontWeight: _showError ? FontWeight.bold : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Pattern grid ────────────────────────────────────────
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PatternLockView(
                          key: ValueKey(_resetKey),
                          onPatternComplete: _onPatternComplete,
                          showError: _showError,
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

enum _SetupStep { draw, confirm }