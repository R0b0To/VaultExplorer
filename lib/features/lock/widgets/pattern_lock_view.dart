import 'dart:convert';
import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';

/// A beautiful 3×3 pattern lock widget drawn on a [CustomPainter].
///
/// Returns the selected pattern as a `List<int>` (dot indices 0-8) via
/// [onPatternComplete].  Dots are numbered left-to-right, top-to-bottom:
///
///     0  1  2
///     3  4  5
///     6  7  8
///
class PatternLockView extends StatefulWidget {
  /// Called when the user lifts their finger after connecting ≥1 dot.
  final ValueChanged<List<int>> onPatternComplete;

  /// Number of dots along each axis.
  final int gridSize;

  /// If true, the dots/lines are shown in the error colour after a wrong attempt.
  final bool showError;

  /// Whether the widget currently accepts touch input.
  final bool enabled;

  const PatternLockView({
    super.key,
    required this.onPatternComplete,
    this.gridSize = 3,
    this.showError = false,
    this.enabled = true,
  });

  @override
  State<PatternLockView> createState() => _PatternLockViewState();
}

class _PatternLockViewState extends State<PatternLockView>
    with SingleTickerProviderStateMixin {
  final List<int> _selectedDots = [];
  Offset? _currentTouch;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PatternLockView old) {
    super.didUpdateWidget(old);
    if (widget.showError != old.showError && !widget.showError) {
      _selectedDots.clear();
      _currentTouch = null;
    }
  }

  // ── Layout helpers ──────────────────────────────────────────────────────────

  List<Offset> _dotCenters(Size size) {
    final n = widget.gridSize;
    final dx = size.width / n;
    final dy = size.height / n;
    return List.generate(n * n, (i) {
      final col = i % n;
      final row = i ~/ n;
      return Offset(dx * (col + 0.5), dy * (row + 0.5));
    });
  }

  int? _hitTest(Offset pos, Size size) {
    final centers = _dotCenters(size);
    final hitRadius = min(size.width, size.height) / widget.gridSize * 0.4;
    for (int i = 0; i < centers.length; i++) {
      if ((centers[i] - pos).distance <= hitRadius) return i;
    }
    return null;
  }

  // ── Touch handling ──────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    if (!widget.enabled) return;
    final box = context.findRenderObject() as RenderBox;
    final pos = box.globalToLocal(d.globalPosition);
    setState(() {
      _selectedDots.clear();
      _currentTouch = pos;
    });
    _trySelect(pos, box.size);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!widget.enabled) return;
    final box = context.findRenderObject() as RenderBox;
    final pos = box.globalToLocal(d.globalPosition);
    setState(() => _currentTouch = pos);
    _trySelect(pos, box.size);
  }

  void _onPanEnd(DragEndDetails _) {
    if (!widget.enabled) return;
    setState(() => _currentTouch = null);
    if (_selectedDots.isNotEmpty) {
      widget.onPatternComplete(List.unmodifiable(_selectedDots));
    }
  }

  void _trySelect(Offset pos, Size size) {
    final dot = _hitTest(pos, size);
    if (dot != null && !_selectedDots.contains(dot)) {
      _selectedDots.add(dot);
      HapticFeedback.lightImpact();
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // FIX: was a hardcoded Size(280, 280) regardless of viewport. On small
    // phones or foldables in narrow mode (esp. inside UnlockSheet's bottom
    // sheet, which also has 24dp horizontal padding from AppBottomSheet),
    // this could overflow or leave inconsistent margins. Now it clamps to
    // the available width minus the sheet's own horizontal padding.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSide = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 280.0;
        final side = maxSide.clamp(220.0, 320.0);

        return AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, _) => GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: CustomPaint(
              painter: _PatternPainter(
                gridSize: widget.gridSize,
                selected: _selectedDots,
                currentTouch: _currentTouch,
                colorScheme: Theme.of(context).colorScheme,
                showError: widget.showError,
                pulseScale: _pulseAnim.value,
              ),
              size: Size(side, side),
            ),
          ),
        );
      },
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _PatternPainter extends CustomPainter {
  final int gridSize;
  final List<int> selected;
  final Offset? currentTouch;
  final ColorScheme colorScheme;
  final bool showError;
  final double pulseScale;

  _PatternPainter({
    required this.gridSize,
    required this.selected,
    this.currentTouch,
    required this.colorScheme,
    required this.showError,
    required this.pulseScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = gridSize;
    final dx = size.width / n;
    final dy = size.height / n;
    final centers = List.generate(n * n, (i) {
      final col = i % n;
      final row = i ~/ n;
      return Offset(dx * (col + 0.5), dy * (row + 0.5));
    });

    final activeColor = showError ? colorScheme.error : colorScheme.primary;
    final inactiveColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.35);

    // Lines
    if (selected.length > 1) {
      final linePaint = Paint()
        ..color = activeColor.withValues(alpha: 0.6)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(centers[selected[0]].dx, centers[selected[0]].dy);
      for (int i = 1; i < selected.length; i++) {
        path.lineTo(centers[selected[i]].dx, centers[selected[i]].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // Trailing line to finger
    if (selected.isNotEmpty && currentTouch != null) {
      final trailPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.3)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(centers[selected.last], currentTouch!, trailPaint);
    }

    // Dots
    final dotRadius = min(dx, dy) * 0.12;
    for (int i = 0; i < centers.length; i++) {
      final isSelected = selected.contains(i);

      // Outer ring
      final ringPaint = Paint()
        ..color = isSelected ? activeColor : inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      final ringRadius = dotRadius * 2.2 * (isSelected ? 1.0 : pulseScale);
      canvas.drawCircle(centers[i], ringRadius, ringPaint);

      // Inner dot
      final dotPaint = Paint()
        ..color = isSelected ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(centers[i], dotRadius, dotPaint);

      // Glow for selected dots
      if (isSelected) {
        final glowPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(centers[i], dotRadius * 3.2, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) => true;
}

// ── Utility ───────────────────────────────────────────────────────────────────

// SECURITY NOTE: patterns are drawn from a far smaller space than
// passwords (permutations over at most 9 dots — a few hundred thousand
// possibilities), so a fast, unsalted, single-round hash lets a stored
// hash be exhaustively reversed almost instantly if it's ever recovered.
// This mirrors PasswordHasher's PBKDF2 approach (see password_hasher.dart)
// with a random per-pattern salt and repeated key derivation, specifically
// to make brute-forcing the *entire* pattern space computationally
// expensive rather than free.
//
// Breaking change: this replaces the old single-round unsalted SHA-256
// format 1:1 (same "pattern -> stored string" contract), but old stored
// values won't verify against it — anyone with a pattern set up under the
// previous scheme will need to re-create it.
const int _patternKdfIterations = 50000;
const int _patternSaltBytes = 16;
const int _patternHashBytes = 32;

Future<Uint8List> _derivePatternBits(
  VaultCryptoApi cryptoApi,
  List<int> pattern,
  Uint8List salt,
) async {
  final input = pattern.join('-');
  final hash = await cryptoApi.hashPasswordSha256(
    password: input,
    salt: salt,
    iterations: _patternKdfIterations,
    outputLen: _patternHashBytes,
  );
  if (hash == null) {
    throw Exception('Pattern bit derivation failed');
  }
  return hash;
}

/// Derives a salted, PBKDF2-stretched hash of [pattern] for secure storage.
///
/// Returns `"<salt_b64>:<hash_b64>"` — a fresh random salt is generated on
/// every call, so hashing the same pattern twice yields different strings
/// (callers that need to confirm two entries match should compare the raw
/// pattern lists *before* hashing, not the hashed output).
Future<String> hashPattern(VaultCryptoApi cryptoApi, List<int> pattern) async {
  final salt = Uint8List(_patternSaltBytes);
  final rng = Random.secure();
  for (int i = 0; i < _patternSaltBytes; i++) {
    salt[i] = rng.nextInt(256);
  }
  final hash = await _derivePatternBits(cryptoApi, pattern, salt);
  return '${base64Encode(salt)}:${base64Encode(hash)}';
}

/// Verifies [pattern] against a `stored` value produced by [hashPattern].
///
/// Uses a constant-time byte comparison so timing can't leak how many
/// leading bytes matched. Returns `false` (rather than throwing) for a
/// null, malformed, or pre-migration legacy stored value.
Future<bool> verifyPattern(
  VaultCryptoApi cryptoApi,
  List<int> pattern,
  String? stored,
) async {
  if (stored == null) return false;
  final parts = stored.split(':');
  if (parts.length != 2) return false;
  try {
    final salt = Uint8List.fromList(base64Decode(parts[0]));
    final expected = base64Decode(parts[1]);
    final actual = await _derivePatternBits(cryptoApi, pattern, salt);
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
