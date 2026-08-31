import 'dart:convert';
import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';

/// A numeric keypad widget for entering a PIN, styled to match
/// [PatternLockView] (dot progress indicator, error state, pulse-free
/// but same card-level integration points: `key`-driven reset,
/// `showError`, `enabled`).
///
/// Digits are collected internally and only handed to
/// [onPinComplete] once the user taps the confirm button.
class PinLockView extends StatefulWidget {
  final ValueChanged<String> onPinComplete;
  final int minLength;
  final int maxLength;
  final bool showError;
  final bool enabled;

  const PinLockView({
    super.key,
    required this.onPinComplete,
    this.minLength = 4,
    this.maxLength = 8,
    this.showError = false,
    this.enabled = true,
  });

  @override
  State<PinLockView> createState() => _PinLockViewState();
}

class _PinLockViewState extends State<PinLockView> {
  String _digits = '';

  @override
  void didUpdateWidget(covariant PinLockView old) {
    super.didUpdateWidget(old);
    if (widget.showError != old.showError && !widget.showError) {
      setState(() => _digits = '');
    }
  }

  void _onDigit(String d) {
    if (!widget.enabled) return;
    if (_digits.length >= widget.maxLength) return;
    HapticFeedback.lightImpact();
    setState(() => _digits += d);
  }

  void _onBackspace() {
    if (!widget.enabled || _digits.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _onSubmit() {
    if (!widget.enabled || _digits.length < widget.minLength) return;
    widget.onPinComplete(_digits);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = widget.showError ? cs.error : cs.primary;
    final canSubmit = widget.enabled && _digits.length >= widget.minLength;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Dots / PIN Progress Indicator
        _DotIndicator(
          length: _digits.length,
          minLength: widget.minLength,
          color: activeColor,
          inactiveColor: cs.outlineVariant.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 32),
        // Keypad
        _Keypad(
          enabled: widget.enabled,
          onDigit: _onDigit,
          onBackspace: _onBackspace,
          onSubmit: canSubmit ? _onSubmit : null,
          hasDigits: _digits.isNotEmpty,
        ),
      ],
    );
  }
}

class _DotIndicator extends StatelessWidget {
  final int length;
  final int minLength;
  final Color color;
  final Color inactiveColor;

  const _DotIndicator({
    required this.length,
    required this.minLength,
    required this.color,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final slots = max(minLength, length);
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(slots, (i) {
          final filled = i < length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: filled ? 16 : 14,
            height: filled ? 16 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? color : Colors.transparent,
              border: Border.all(
                color: filled ? color : inactiveColor,
                width: 2,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onSubmit;
  final bool hasDigits;

  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
    required this.hasDigits,
  });

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  static const double _buttonSpacing = 16.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: _buttonSpacing),
                _KeypadButton(
                  label: row[i],
                  enabled: enabled,
                  onTap: () => onDigit(row[i]),
                ),
              ],
            ],
          ),
          const SizedBox(height: _buttonSpacing),
        ],
        // Bottom row: Backspace, 0, Confirm
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _KeypadButton(
              icon: Icons.backspace_outlined,
              enabled: enabled && hasDigits,
              isSpecialAction: true,
              onTap: onBackspace,
            ),
            const SizedBox(width: _buttonSpacing),
            _KeypadButton(
              label: '0',
              enabled: enabled,
              onTap: () => onDigit('0'),
            ),
            const SizedBox(width: _buttonSpacing),
            _KeypadButton(
              icon: Icons.arrow_forward_rounded,
              enabled: onSubmit != null,
              filled: true,
              color: cs.primary,
              onTap: onSubmit ?? () {},
            ),
          ],
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool enabled;
  final bool filled;
  final bool isSpecialAction;
  final Color? color;
  final VoidCallback onTap;

  const _KeypadButton({
    this.label,
    this.icon,
    required this.enabled,
    this.filled = false,
    this.isSpecialAction = false,
    this.color,
    required this.onTap,
  });

  static const double _buttonSize = 76.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg;
    final Color fg;
    BorderSide borderSide = BorderSide.none;

    if (filled) {
      bg = enabled
          ? (color ?? cs.primary)
          : cs.surfaceContainerHighest.withValues(alpha: 0.5);
      fg = enabled ? cs.onPrimary : cs.onSurfaceVariant.withValues(alpha: 0.35);
    } else if (isSpecialAction) {
      bg = Colors.transparent;
      fg = enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.25);
    } else {
      bg = cs.surfaceContainerHighest;
      fg = enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.35);
      borderSide = BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.25),
        width: 1,
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: _buttonSize,
      height: _buttonSize,
      child: Material(
        color: bg,
        shape: CircleBorder(side: borderSide),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Center(
            child: label != null
                ? Text(
                    label!,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      color: fg,
                      letterSpacing: -0.5,
                    ),
                  )
                : Icon(icon, size: 26, color: fg),
          ),
        ),
      ),
    );
  }
}

// ── Utility ───────────────────────────────────────────────────────────────────

const int _pinKdfIterations = 50000;
const int _pinSaltBytes = 16;
const int _pinHashBytes = 32;

Future<Uint8List> _derivePinBits(
  VaultCryptoApi cryptoApi,
  String pin,
  Uint8List salt,
) async {
  final hash = await cryptoApi.hashPasswordSha256(
    password: pin,
    salt: salt,
    iterations: _pinKdfIterations,
    outputLen: _pinHashBytes,
  );
  if (hash == null) {
    throw Exception('PIN bit derivation failed');
  }
  return hash;
}

Future<String> hashPin(VaultCryptoApi cryptoApi, String pin) async {
  final salt = Uint8List(_pinSaltBytes);
  final rng = Random.secure();
  for (int i = 0; i < _pinSaltBytes; i++) {
    salt[i] = rng.nextInt(256);
  }
  final hash = await _derivePinBits(cryptoApi, pin, salt);
  return '${base64Encode(salt)}:${base64Encode(hash)}';
}

Future<bool> verifyPin(
  VaultCryptoApi cryptoApi,
  String pin,
  String? stored,
) async {
  if (stored == null) return false;
  final parts = stored.split(':');
  if (parts.length != 2) return false;
  try {
    final salt = Uint8List.fromList(base64Decode(parts[0]));
    final expected = base64Decode(parts[1]);
    final actual = await _derivePinBits(cryptoApi, pin, salt);
    return _constantTimeEquals(actual, expected);
  } catch (_) {
    return false;
  }
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}
