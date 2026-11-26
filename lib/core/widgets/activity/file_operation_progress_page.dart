import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';

/// The content of a file operation's own window on desktop: what the copy
/// dialog of the system file manager shows.
///
///  * a line saying what is happening and between which places,
///  * the percentage, big, with a cancel button beside it,
///  * a graph of the transfer speed over the progress so far (a plain progress
///    bar when the size is not known, as for deleting),
///  * what is being worked on, the time remaining and the items remaining.
///
/// The window's title shows the percentage too, so it reads in the taskbar.
///
/// An operation that ends with a problem keeps the window: it turns into the
/// result (what failed) with a Close button. Any other ending closes the window
/// (see `FileOperationWindows`).
class FileOperationProgressPage extends StatefulWidget {
  const FileOperationProgressPage({super.key, required this.operation});

  final FileOperation operation;

  @override
  State<FileOperationProgressPage> createState() =>
      _FileOperationProgressPageState();
}

class _FileOperationProgressPageState extends State<FileOperationProgressPage> {
  /// How often the speed is measured at most, and how many measurements the
  /// graph keeps. The graph is over progress, not time, so the cap only bounds
  /// memory on very long operations.
  static const Duration _sampleEvery = Duration(milliseconds: 400);
  static const int _maxSamples = 600;

  final List<_SpeedSample> _samples = <_SpeedSample>[];
  DateTime? _lastSampleAt;
  int _lastSampleBytes = 0;
  double? _speed;
  String? _lastTitle;

  FileOperation get _op => widget.operation;

  @override
  void initState() {
    super.initState();
    _lastSampleBytes = _op.transferredBytes;
    _op.addListener(_onOperationChanged);
  }

  @override
  void dispose() {
    _op.removeListener(_onOperationChanged);
    super.dispose();
  }

  void _onOperationChanged() => _measureSpeed();

  /// The speed over the last moments, smoothed, as opposed to the operation's
  /// own figure, which is the average since it started.
  void _measureSpeed() {
    if (_op.status != FileOperationStatus.running) return;
    final now = DateTime.now();
    final last = _lastSampleAt;
    final bytes = _op.transferredBytes;
    if (last == null) {
      _lastSampleAt = now;
      _lastSampleBytes = bytes;
      return;
    }
    final elapsed = now.difference(last);
    if (elapsed < _sampleEvery) return;
    final instant =
        (bytes - _lastSampleBytes) / (elapsed.inMicroseconds / 1000000.0);
    _lastSampleAt = now;
    _lastSampleBytes = bytes;
    if (instant < 0) return;
    final previous = _speed;
    _speed = previous == null ? instant : previous * 0.6 + instant * 0.4;
    final fraction = _op.progressFraction;
    if (fraction == null) return;
    _samples.add(_SpeedSample(fraction, _speed!));
    if (_samples.length > _maxSamples) _samples.removeAt(0);
  }

  void _updateWindowTitle() {
    if (!mounted) return;
    final title = _windowTitle(context);
    if (title == _lastTitle) return;
    _lastTitle = title;
    SecondaryWindowScope.maybeOf(context)?.setTitle(title);
  }

  String _windowTitle(BuildContext context) {
    final percent = _percent;
    if (_isRunning && percent != null) {
      return context.l10n.fileOpWinPercentComplete(percent);
    }
    return _op.shortSummary;
  }

  bool get _isRunning =>
      _op.status == FileOperationStatus.pending ||
      _op.status == FileOperationStatus.running;

  int? get _percent {
    final fraction = _op.progressFraction;
    if (fraction == null) return null;
    return (fraction * 100).floor().clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _op,
        builder: (context, _) {
          // The window's title follows the progress. It is set after this
          // frame, and only when the text changed.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _updateWindowTitle(),
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: _isRunning ? _buildProgress(context) : _buildResult(context),
          );
        },
      ),
    );
  }

  // ── While it runs ─────────────────────────────────────────────────────────

  Widget _buildProgress(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final percent = _percent;
    final hasSize = _op.totalBytes > 0;

    final remainingBytes = math.max(0, _op.totalBytes - _op.transferredBytes);
    final total = _op.totalCount > 0 ? _op.totalCount : _op.items.length;
    final done = _op.doneCount + _op.failCount + _op.skipCount;
    final remainingItems = math.max(0, total - done);
    final eta = _op.estimatedTimeRemaining;

    final activity = _op.currentActivity.isNotEmpty
        ? _op.currentActivity
        : _op.shortSummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_summary(context), style: text.bodyMedium),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                percent == null
                    ? _op.verbIng
                    : l10n.fileOpWinPercentComplete(percent),
                style: text.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: l10n.fileOpsCancelTooltip,
              onPressed: _op.cancelRequested ? null : _op.requestCancel,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (hasSize && percent != null)
          Expanded(
            child: _SpeedGraph(
              samples: _samples,
              progress: _op.progressFraction ?? 0,
              speedLabel: _speed == null
                  ? null
                  : l10n.fileOpWinSpeed(formatBytes(_speed!.round())),
            ),
          )
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _op.progressFraction,
              minHeight: 4,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
            ),
          ),
          const Spacer(),
        ],
        const SizedBox(height: 12),
        Text(
          activity,
          style: text.bodyMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.fileOpWinTimeRemaining(
            eta == null ? l10n.fileOpWinCalculating : formatDuration(eta),
          ),
          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          hasSize
              ? l10n.fileOpWinItemsRemaining(
                  remainingItems,
                  formatBytes(remainingBytes),
                )
              : l10n.fileOpWinItemsRemainingNoSize(remainingItems),
          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  /// "Copying 3 items from A to B", or the shorter forms for operations that
  /// only have a source (delete, export, extract) or only a destination
  /// (import).
  String _summary(BuildContext context) {
    final l10n = context.l10n;
    final items = l10n.fileOpItemsCount(_op.items.length);
    final verb = _op.verbIng;
    if (_op.isTransfer) {
      return l10n.fileOpWinFromTo(
        verb,
        items,
        _op.sourceDisplayName,
        _op.destDisplayName,
      );
    }
    if (_op.isImport) {
      return l10n.fileOpWinTo(verb, items, _op.destDisplayName);
    }
    return l10n.fileOpWinFrom(verb, items, _op.sourceDisplayName);
  }

  // ── When it ended with a problem ──────────────────────────────────────────

  Widget _buildResult(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final failed = _op.itemStatuses
        .where((s) => s.result == FileItemResult.failed)
        .toList();
    const shown = 5;
    final headline =
        (_op.status == FileOperationStatus.failed ||
            _op.status == FileOperationStatus.diskFull)
        ? (_op.errorSummary ?? _op.completionSummary)
        : _op.completionSummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: cs.error, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(headline, style: text.titleMedium)),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: failed.isEmpty
              ? const SizedBox.shrink()
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.fileOpsItemsFailedLabel(failed.length),
                        style: text.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      for (final status in failed.take(shown))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            status.errorMessage == null
                                ? status.item.name
                                : '${status.item.name}: ${status.errorMessage}',
                            style: text.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (failed.length > shown)
                        Text(
                          l10n.fileOpsMoreItemsLabel(failed.length - shown),
                          style: text.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.tonal(
            onPressed: () => SecondaryWindowScope.maybeOf(context)?.close(),
            child: Text(l10n.closeButton),
          ),
        ),
      ],
    );
  }
}

// ── Speed graph ─────────────────────────────────────────────────────────────

/// One measurement: how fast the transfer was going once it was [progress]
/// (0 to 1) of the way through.
class _SpeedSample {
  const _SpeedSample(this.progress, this.bytesPerSecond);

  final double progress;
  final double bytesPerSecond;
}

/// The speed over the progress so far, filling the graph from the left as the
/// operation advances, with a line across at the current speed.
class _SpeedGraph extends StatelessWidget {
  const _SpeedGraph({
    required this.samples,
    required this.progress,
    required this.speedLabel,
  });

  final List<_SpeedSample> samples;
  final double progress;
  final String? speedLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SpeedGraphPainter(
            samples: List<_SpeedSample>.of(samples),
            progress: progress,
            speedLabel: speedLabel,
            fill: cs.primary.withValues(alpha: 0.35),
            stroke: cs.primary,
            grid: cs.outlineVariant.withValues(alpha: 0.5),
            guide: cs.onSurface,
            labelStyle: (Theme.of(context).textTheme.bodyMedium ??
                    const TextStyle())
                .copyWith(color: cs.onSurface),
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

class _SpeedGraphPainter extends CustomPainter {
  _SpeedGraphPainter({
    required this.samples,
    required this.progress,
    required this.speedLabel,
    required this.fill,
    required this.stroke,
    required this.grid,
    required this.guide,
    required this.labelStyle,
    required this.textDirection,
  });

  final List<_SpeedSample> samples;
  final double progress;
  final String? speedLabel;
  final Color fill;
  final Color stroke;
  final Color grid;
  final Color guide;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 10; i++) {
      final x = w * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (var i = 1; i < 4; i++) {
      final y = h * i / 4;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }
    if (samples.isEmpty) return;

    // Leave headroom above the fastest moment so the line is never flush
    // with the top edge.
    var peak = 1.0;
    for (final s in samples) {
      peak = math.max(peak, s.bytesPerSecond);
    }
    peak *= 1.25;

    double yOf(double speed) => h - (speed / peak).clamp(0.0, 1.0) * h;

    final line = Path()..moveTo(0, yOf(samples.first.bytesPerSecond));
    for (final s in samples) {
      line.lineTo(s.progress.clamp(0.0, 1.0) * w, yOf(s.bytesPerSecond));
    }
    final lastX = samples.last.progress.clamp(0.0, 1.0) * w;
    final area = Path.from(line)
      ..lineTo(lastX, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      line,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // The line across at the current speed, with its label above it (below
    // it when it is too close to the top edge).
    final currentY = yOf(samples.last.bytesPerSecond);
    canvas.drawLine(
      Offset(0, currentY),
      Offset(w, currentY),
      Paint()
        ..color = guide
        ..strokeWidth = 1,
    );
    final label = speedLabel;
    if (label != null) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: textDirection,
        maxLines: 1,
      )..layout(maxWidth: w - 16);
      final top = currentY - painter.height - 3 < 2
          ? currentY + 3
          : currentY - painter.height - 3;
      painter.paint(canvas, Offset(w - painter.width - 8, top));
    }
  }

  @override
  bool shouldRepaint(_SpeedGraphPainter old) =>
      old.samples.length != samples.length ||
      old.progress != progress ||
      old.speedLabel != speedLabel ||
      old.fill != fill ||
      old.stroke != stroke ||
      old.grid != grid ||
      old.guide != guide;
}
