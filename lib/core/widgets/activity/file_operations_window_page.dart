import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/activity/file_operation_windows.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_frame.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_title_bar.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/core/windowing/window_caption.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';

/// The content of the file operations window on desktop: a small, quiet panel
/// that says how each running operation is doing and gets out of the way.
///
/// Each operation is one slim card (see `_OperationCard`): what is being
/// worked on, a thin progress bar with the percentage, and the speed, the time
/// and the items left as short figures with an icon each. The cards are
/// stacked, oldest first.
///
/// The window is as tall as its cards (up to [maxVisibleCards] of them, then
/// they scroll) where the runner can resize it (Windows); the person never
/// can. It sits in the corner of the screen, like a notification.
///
/// The window's title shows the percentage of a single operation, so it reads
/// in the taskbar, and says that transfers are in progress when there are
/// several.
///
/// An operation that ends with a problem keeps its card: it turns into a short
/// result with a button that dismisses it. Any other ending removes the card
/// (see `FileOperationWindows`).
class FileOperationsWindowPage extends StatefulWidget {
  const FileOperationsWindowPage({super.key, required this.manager});

  final FileOperationWindows manager;

  /// The width of the window.
  static const double windowWidth = 380;

  /// How many cards show before the list scrolls.
  static const int maxVisibleCards = 3;

  static const double _runningCardHeight = 88;
  static const double _resultCardHeight = 92;

  static double _cardHeight(FileOperation op) =>
      _isRunning(op) ? _runningCardHeight : _resultCardHeight;

  /// The height of the cards (dividers included) for [operations], at least
  /// one card and at most [maxVisibleCards] of them.
  static double listHeightFor(List<FileOperation> operations) {
    var height = 0.0;
    for (final op in operations.take(maxVisibleCards)) {
      height += _cardHeight(op) + 1;
    }
    return math.max(_runningCardHeight, height - 1);
  }

  @override
  State<FileOperationsWindowPage> createState() =>
      _FileOperationsWindowPageState();
}

class _FileOperationsWindowPageState extends State<FileOperationsWindowPage> {
  String? _lastTitle;
  double? _lastHeight;

  void _updateWindowTitle(List<FileOperation> operations) {
    if (!mounted || operations.isEmpty) return;
    final l10n = context.l10n;
    final String title;
    if (operations.length > 1) {
      title = l10n.fileOpsTransfersInProgressTitle;
    } else {
      final op = operations.single;
      final fraction = op.progressFraction;
      title = _isRunning(op) && fraction != null
          ? l10n.fileOpWinPercentComplete(
              (fraction * 100).floor().clamp(0, 100),
            )
          : op.shortSummary;
    }
    if (title == _lastTitle) return;
    _lastTitle = title;
    SecondaryWindowScope.maybeOf(context)?.setTitle(title);
  }

  /// Makes the window as tall as its cards (Windows only; elsewhere it keeps
  /// the height it was opened with).
  void _updateWindowHeight(List<FileOperation> operations) {
    if (!mounted || operations.isEmpty) return;
    final caption = NativeWindowChrome.of(context)
        ? 0.0
        : kDesktopTitleBarHeight;
    final height = FileOperationsWindowPage.listHeightFor(operations) + caption;
    if (height == _lastHeight) return;
    _lastHeight = height;
    final viewId = View.maybeOf(context)?.viewId;
    if (viewId != null) setWindowContentHeight(viewId, height);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        // The window follows the list of operations, and (for its title) the
        // progress of each.
        listenable: Listenable.merge(<Listenable>[
          widget.manager,
          ...widget.manager.shown,
        ]),
        builder: (context, _) {
          final operations = widget.manager.shown;
          // The title and the height are set after this frame, and only when
          // they changed.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateWindowTitle(operations);
            _updateWindowHeight(operations);
          });
          if (operations.isEmpty) return const SizedBox.shrink();
          return Scrollbar(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: operations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final op = operations[index];
                return SizedBox(
                  height: FileOperationsWindowPage._cardHeight(op),
                  child: _OperationCard(
                    key: ValueKey<int>(op.id),
                    operation: op,
                    manager: widget.manager,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

bool _isRunning(FileOperation op) =>
    op.status == FileOperationStatus.pending ||
    op.status == FileOperationStatus.running;

/// One operation in the window: its progress while it runs, a short result
/// when it ended with a problem.
class _OperationCard extends StatefulWidget {
  const _OperationCard({
    super.key,
    required this.operation,
    required this.manager,
  });

  final FileOperation operation;
  final FileOperationWindows manager;

  @override
  State<_OperationCard> createState() => _OperationCardState();
}

class _OperationCardState extends State<_OperationCard> {
  /// How often the speed is measured at most.
  static const Duration _sampleEvery = Duration(milliseconds: 400);

  DateTime? _lastSampleAt;
  int _lastSampleBytes = 0;
  double? _speed;

  FileOperation get _op => widget.operation;

  @override
  void initState() {
    super.initState();
    _lastSampleBytes = _op.transferredBytes;
    _op.addListener(_measureSpeed);
  }

  @override
  void dispose() {
    _op.removeListener(_measureSpeed);
    super.dispose();
  }

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
  }

  int? get _percent {
    final fraction = _op.progressFraction;
    if (fraction == null) return null;
    return (fraction * 100).floor().clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _op,
      builder: (context, _) =>
          _isRunning(_op) ? _buildProgress(context) : _buildResult(context),
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
    final etaText = eta == null ? '…' : formatDuration(eta);

    final activity = _op.currentActivity.isNotEmpty
        ? _op.currentActivity
        : _op.shortSummary;
    final muted = text.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: _summary(context),
                  child: Text(
                    activity,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  tooltip: l10n.fileOpsCancelTooltip,
                  onPressed: _op.cancelRequested ? null : _op.requestCancel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _op.progressFraction,
                      minHeight: 5,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: cs.primary,
                    ),
                  ),
                ),
                if (percent != null) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$percent%',
                      textAlign: TextAlign.end,
                      style: text.labelLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              if (hasSize && _speed != null)
                _Stat(
                  icon: Icons.speed_rounded,
                  label: '${formatBytes(_speed!.round())}/s',
                  tooltip: l10n.fileOpWinSpeed(formatBytes(_speed!.round())),
                  style: muted,
                ),
              if (hasSize)
                _Stat(
                  icon: Icons.schedule_rounded,
                  label: etaText,
                  tooltip: l10n.fileOpWinTimeRemaining(
                    eta == null ? l10n.fileOpWinCalculating : etaText,
                  ),
                  style: muted,
                ),
              _Stat(
                icon: Icons.insert_drive_file_outlined,
                label: hasSize
                    ? '$remainingItems · ${formatBytes(remainingBytes)}'
                    : '$remainingItems',
                tooltip: hasSize
                    ? l10n.fileOpWinItemsRemaining(
                        remainingItems,
                        formatBytes(remainingBytes),
                      )
                    : l10n.fileOpWinItemsRemainingNoSize(remainingItems),
                style: muted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Copying 3 items from A to B", or the shorter forms for operations that
  /// only have a source (delete, export, extract) or only a destination
  /// (import). Shown when hovering the card's first line.
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
    final headline =
        (_op.status == FileOperationStatus.failed ||
            _op.status == FileOperationStatus.diskFull)
        ? (_op.errorSummary ?? _op.completionSummary)
        : _op.completionSummary;
    // Hovering the count lists what failed.
    final details = failed
        .take(8)
        .map(
          (s) => s.errorMessage == null
              ? s.item.name
              : '${s.item.name}: ${s.errorMessage}',
        )
        .join('\n');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.error, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (failed.isNotEmpty)
                  Tooltip(
                    message: details,
                    child: Text(
                      l10n.fileOpsItemsFailedLabel(failed.length),
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              icon: const Icon(Icons.close_rounded),
              iconSize: 16,
              padding: EdgeInsets.zero,
              tooltip: l10n.closeButton,
              onPressed: () => widget.manager.dismissResult(_op),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small figure with an icon, such as the speed or the time left. Hovering
/// it says in words what it is.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.style,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: style?.color),
          const SizedBox(width: 4),
          Text(label, style: style),
        ],
      ),
    );
  }
}
