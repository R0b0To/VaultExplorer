import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// A numeric keypad widget for entering a PIN, styled to match
/// [PatternLockView] (dot progress indicator, error state, pulse-free
/// but same card-level integration points: `key`-driven reset,
/// `showError`, `enabled`).
///
/// Digits are collected internally and only handed to
/// [onPinComplete] once the user taps the confirm button -- unlike
/// [PatternLockView] there's no natural "gesture end" to treat as
/// submission, so an explicit confirm affordance (enabled once
/// [minLength] digits have been entered) stands in for it.
class PinLockView extends StatefulWidget {
  /// Called once when the user taps confirm with >= [minLength] digits
  /// entered.
  final ValueChanged<String> onPinComplete;

  /// Fewest digits the confirm button will accept. Mirrors
  /// [PatternLockView]'s "connect at least 4 dots" minimum.
  final int minLength;

  /// Most digits the keypad will accept; further taps are ignored once
  /// reached.
  final int maxLength;

  /// If true, the dot indicator is shown in the error colour after a
  /// wrong attempt.
  final bool showError;

  /// Whether the widget currently accepts touch input.
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
    // Defensive, mirrors PatternLockView: callers currently always pair a
    // showError->false transition with a `key` change (full remount), but
    // guard against a future caller that only flips the flag.
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
        _DotIndicator(
          length: _digits.length,
          minLength: widget.minLength,
          color: activeColor,
          inactiveColor: cs.onSurfaceVariant.withValues(alpha: 0.35),
        ),
        const SizedBox(height: 24),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(slots, (i) {
        final filled = i < length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.transparent,
            border: Border.all(color: filled ? color : inactiveColor, width: 2),
          ),
        );
      }),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final d in row) _KeypadButton(label: d, enabled: enabled, onTap: () => onDigit(d)),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _KeypadButton(
                icon: Icons.backspace_outlined,
                enabled: enabled && hasDigits,
                onTap: onBackspace,
              ),
              _KeypadButton(label: '0', enabled: enabled, onTap: () => onDigit('0')),
              _KeypadButton(
                icon: Icons.check_circle_rounded,
                enabled: onSubmit != null,
                filled: true,
                color: cs.primary,
                onTap: onSubmit ?? () {},
              ),
            ],
          ),
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
  final Color? color;
  final VoidCallback onTap;

  const _KeypadButton({
    this.label,
    this.icon,
    required this.enabled,
    this.filled = false,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = filled ? cs.onPrimary : (color ?? cs.onSurface);
    final bg = filled
        ? (enabled ? (color ?? cs.primary) : cs.onSurfaceVariant.withValues(alpha: 0.2))
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Center(
              child: label != null
                  ? Text(
                      label!,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: enabled ? fg : fg.withValues(alpha: 0.35),
                          ),
                    )
                  : Icon(
                      icon,
                      size: 24,
                      color: enabled ? fg : fg.withValues(alpha: 0.35),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Utility ───────────────────────────────────────────────────────────────────

// SECURITY NOTE: mirrors pattern_lock_view.dart's hashPattern/verifyPattern
// exactly (same PBKDF2-via-native-hashPasswordSha256 approach, same salt/
// iteration/output sizes). A numeric-only PIN is drawn from an even smaller
// space than a pattern once digit count is low (e.g. 10,000 possibilities
// for a 4-digit PIN), so the same salted, iterated hash is used rather than
// a fast unsalted digest, to keep brute-forcing a recovered hash expensive.
const int _pinKdfIterations = 50000;
const int _pinSaltBytes = 16;
const int _pinHashBytes = 32;

Future<Uint8List> _derivePinBits(String pin, Uint8List salt) async {
  final hash = await vaultExplorerApi.hashPasswordSha256(
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

/// Derives a salted, PBKDF2-stretched hash of [pin] for secure storage.
///
/// Returns `"<salt_b64>:<hash_b64>"` -- a fresh random salt is generated on
/// every call, so hashing the same PIN twice yields different strings
/// (callers that need to confirm two entries match should compare the raw
/// PIN strings *before* hashing, not the hashed output).
Future<String> hashPin(String pin) async {
  final salt = Uint8List(_pinSaltBytes);
  final rng = Random.secure();
  for (int i = 0; i < _pinSaltBytes; i++) {
    salt[i] = rng.nextInt(256);
  }
  final hash = await _derivePinBits(pin, salt);
  return '${base64Encode(salt)}:${base64Encode(hash)}';
}

/// Verifies [pin] against a `stored` value produced by [hashPin].
///
/// Uses a constant-time byte comparison so timing can't leak how many
/// leading bytes matched. Returns `false` (rather than throwing) for a
/// null or malformed stored value.
Future<bool> verifyPin(String pin, String? stored) async {
  if (stored == null) return false;
  final parts = stored.split(':');
  if (parts.length != 2) return false;
  try {
    final salt = Uint8List.fromList(base64Decode(parts[0]));
    final expected = base64Decode(parts[1]);
    final actual = await _derivePinBits(pin, salt);
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
