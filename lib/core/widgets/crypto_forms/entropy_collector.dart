import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/entropy_pool.dart';

const int _trailLifetimeMs = 900;
const int _maxTrailPoints = 80;

class _TrailPoint {
  final Offset position;
  final int bornMs;
  const _TrailPoint(this.position, this.bornMs);
}

/// Body of the "Add randomness" wizard step: a pad the user drags a finger
/// over to stir touch-movement entropy into the new volume's keys, like
/// VeraCrypt desktop's mouse-movement step.
///
/// All state lives in the [EntropyPool] owned by the wizard, so the collected
/// randomness survives stepping back and forth. The wizard enables "Next" when
/// [EntropyPool.isSatisfied], and reads the bytes with [EntropyPool.takeBytes]
/// when it starts creating.
///
/// The pad claims touches outright (see [EagerGestureRecognizer]) so that
/// dragging on it doesn't scroll the wizard page underneath.
class EntropyCollector extends StatefulWidget {
  final EntropyPool pool;

  /// Fixed pad height; by default it scales with the screen (landscape phones
  /// are short and the page around the pad still needs room to scroll).
  final double? padHeight;

  const EntropyCollector({
    super.key,
    required this.pool,
    this.padHeight,
  });

  @override
  State<EntropyCollector> createState() => _EntropyCollectorState();
}

class _EntropyCollectorState extends State<EntropyCollector>
    with SingleTickerProviderStateMixin {
  final List<_TrailPoint> _trail = [];
  final Stopwatch _clock = Stopwatch()..start();
  late final AnimationController _frame;

  @override
  void initState() {
    super.initState();
    _frame = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_pruneTrail);
  }

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }

  void _pruneTrail() {
    final now = _clock.elapsedMilliseconds;
    _trail.removeWhere((p) => now - p.bornMs >= _trailLifetimeMs);
    if (_trail.isEmpty) _frame.stop();
  }

  void _onPointer(PointerEvent e) {
    final pos = e.localPosition;
    _trail.add(_TrailPoint(pos, _clock.elapsedMilliseconds));
    if (_trail.length > _maxTrailPoints) _trail.removeAt(0);
    if (!_frame.isAnimating) _frame.repeat();

    final accepted = widget.pool.addSample(pos.dx, pos.dy, e.timeStamp);
    if (accepted && widget.pool.sampleCount % 12 == 0) {
      HapticFeedback.selectionClick();
    }
  }

  Widget _buildPad(BuildContext context) {
    final cs = context.colors;
    final l10n = context.l10n;
    final padHeight = widget.padHeight ??
        (MediaQuery.sizeOf(context).height * 0.32).clamp(140.0, 260.0);
    return Semantics(
      label: l10n.entropyPadSemantics,
      child: RawGestureDetector(
        gestures: <Type, GestureRecognizerFactory>{
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            () => EagerGestureRecognizer(),
            (EagerGestureRecognizer instance) {},
          ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointer,
          onPointerMove: _onPointer,
          child: Container(
            height: padHeight,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _TrailPainter(
                    trail: _trail,
                    clock: _clock,
                    color: cs.primary,
                    repaint: _frame,
                  ),
                ),
                IgnorePointer(
                  child: ListenableBuilder(
                    listenable: widget.pool,
                    builder: (context, _) => AnimatedOpacity(
                      opacity: widget.pool.sampleCount == 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gesture_rounded,
                                size: 36, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                            const SizedBox(height: 8),
                            Text(
                              l10n.entropyPadHint,
                              style: context.typography.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;
    final pool = widget.pool;
    final done = pool.isComplete;
    final skipped = pool.skipped;
    final success = context.semanticColors.success;
    final accent = done ? success : cs.primary;

    final String statusText;
    if (skipped) {
      statusText = l10n.entropySkippedStatus;
    } else if (done) {
      statusText = l10n.entropyComplete;
    } else {
      statusText = l10n.entropyProgress((pool.progress * 100).floor());
    }

    final hex = pool.previewHex;
    final monoStyle = textTheme.bodySmall?.copyWith(
      fontFamily: 'JetBrains Mono',
      color: cs.onSurfaceVariant,
      letterSpacing: 0.6,
      height: 1.4,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: LinearProgressIndicator(
            value: skipped ? 0 : pool.progress,
            minHeight: 8,
            color: accent,
            backgroundColor: cs.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (done && !skipped) ...[
              Icon(Icons.check_circle_rounded, size: 18, color: success),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                statusText,
                style: textTheme.bodyMedium?.copyWith(
                  color: done && !skipped ? success : cs.onSurfaceVariant,
                  fontWeight: done && !skipped ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.entropyPoolLabel,
                style: textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              ExcludeSemantics(
                child: Text(
                  '${hex.substring(0, 16)}\n${hex.substring(16)}',
                  style: monoStyle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.entropyIntro,
          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _buildPad(context),
        const SizedBox(height: 14),
        ListenableBuilder(
          listenable: widget.pool,
          builder: (context, _) => _buildStatus(context),
        ),
        ListenableBuilder(
          listenable: widget.pool,
          builder: (context, _) {
            if (widget.pool.isComplete || widget.pool.skipped) {
              return const SizedBox.shrink();
            }
            return Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: widget.pool.skip,
                child: Text(l10n.entropySkip),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TrailPainter extends CustomPainter {
  final List<_TrailPoint> trail;
  final Stopwatch clock;
  final Color color;

  _TrailPainter({
    required this.trail,
    required this.clock,
    required this.color,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.elapsedMilliseconds;
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in trail) {
      final age = (now - p.bornMs) / _trailLifetimeMs;
      if (age >= 1) continue;
      paint.color = color.withValues(alpha: (1 - age) * 0.9);
      canvas.drawCircle(p.position, 7 * (1 - age * 0.5), paint);
    }
  }

  // Repainting is driven by the animation controller handed to super(repaint:).
  @override
  bool shouldRepaint(covariant _TrailPainter oldDelegate) => true;
}
