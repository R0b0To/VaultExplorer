import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/activity/file_operations_sheet.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';

/// App bar action button that displays active file operations and transfers.
///
/// Features:
/// - Takes zero space when idle (`SizedBox.shrink()`).
/// - **1-Second Rule (Avoid UI flicker)**: Delays appearance by 800ms. If an
///   operation finishes in under 800ms, no indicator is shown at all.
/// - **Progress Ring**: A circular progress ring around a centered transfer icon
///   tracks aggregate progress across active operations.
/// - **Multi-op Badge**: Displays the active transfer count when multiple
///   operations run concurrently.
/// - **Completion Linger**: Shows a filled checkmark for 4 seconds after
///   successful completion before auto-dismissing (unless errors occurred).
/// - **Activity Center**: Tapping the icon opens [FileOperationsSheet] with full
///   metrics (speed, ETA, cancel controls, item lists).
class AppBarTransferButton extends StatefulWidget {
  const AppBarTransferButton({super.key});

  @override
  State<AppBarTransferButton> createState() => _AppBarTransferButtonState();
}

class _AppBarTransferButtonState extends State<AppBarTransferButton> {
  static const _kShowDelay = Duration(milliseconds: 800);
  static const _kLingerDuration = Duration(seconds: 4);

  Timer? _showDebounceTimer;
  Timer? _lingerTimer;

  bool _isDebouncePassed = false;
  final Set<FileOperation> _observedOps = {};

  @override
  void initState() {
    super.initState();
    FileOperationService.instance.addListener(_onServiceChanged);
    FileOperationsSheet.isOpenNotifier.addListener(_onSheetStateChanged);
    _syncObservedOperations();
    _evaluateState();
  }

  @override
  void dispose() {
    _showDebounceTimer?.cancel();
    _lingerTimer?.cancel();
    FileOperationService.instance.removeListener(_onServiceChanged);
    FileOperationsSheet.isOpenNotifier.removeListener(_onSheetStateChanged);
    for (final op in _observedOps) {
      op.removeListener(_onOperationChanged);
    }
    _observedOps.clear();
    super.dispose();
  }

  void _onServiceChanged() {
    _syncObservedOperations();
    _evaluateState();
  }

  void _onOperationChanged() {
    _evaluateState();
  }

  void _onSheetStateChanged() {
    _evaluateState();
  }

  void _syncObservedOperations() {
    final currentOps = FileOperationService.instance.operations;
    final currentSet = currentOps.toSet();

    // Remove listeners from ops no longer in the service list
    final removed = _observedOps.difference(currentSet);
    for (final op in removed) {
      op.removeListener(_onOperationChanged);
      _observedOps.remove(op);
    }

    // Add listeners to new ops
    for (final op in currentOps) {
      if (_observedOps.add(op)) {
        op.addListener(_onOperationChanged);
      }
    }
  }

  void _evaluateState() {
    if (!mounted) return;

    final svc = FileOperationService.instance;
    final ops = svc.operations;
    final activeCount = svc.activeCount;

    final hasErrors = ops.any(
      (op) =>
          op.status == FileOperationStatus.failed ||
          op.status == FileOperationStatus.diskFull ||
          op.status == FileOperationStatus.completedWithErrors,
    );

    // 1. If there are no operations at all, reset debounce and cancel timers.
    if (ops.isEmpty) {
      _showDebounceTimer?.cancel();
      _showDebounceTimer = null;
      _lingerTimer?.cancel();
      _lingerTimer = null;
      if (_isDebouncePassed) {
        setState(() => _isDebouncePassed = false);
      }
      return;
    }

    // 2. If there are active operations:
    if (activeCount > 0) {
      _lingerTimer?.cancel();
      _lingerTimer = null;

      // If already showing or if error occurred, ensure showing
      if (_isDebouncePassed) {
        setState(() {});
        return;
      }

      // Schedule 800ms debounce timer to avoid flicker for quick operations
      if (_showDebounceTimer == null) {
        _showDebounceTimer = Timer(_kShowDelay, () {
          _showDebounceTimer = null;
          if (mounted && FileOperationService.instance.operations.isNotEmpty) {
            setState(() => _isDebouncePassed = true);
          }
        });
      }
      return;
    }

    // 3. No active operations, but lingering completed/failed operations exist:
    _showDebounceTimer?.cancel();
    _showDebounceTimer = null;

    // If errors exist, always show so the user isn't unaware of failures
    if (hasErrors) {
      _lingerTimer?.cancel();
      _lingerTimer = null;
      if (!_isDebouncePassed) {
        setState(() => _isDebouncePassed = true);
      } else {
        setState(() {});
      }
      return;
    }

    // If the 800ms debounce never passed (operation completed very fast), don't show
    if (!_isDebouncePassed) {
      return;
    }

    // If sheet is open, pause the linger timer so items don't disappear while looking
    if (FileOperationsSheet.isOpenNotifier.value) {
      _lingerTimer?.cancel();
      _lingerTimer = null;
      setState(() {});
      return;
    }

    // Start linger timer to auto-clear finished operations after 4 seconds
    if (_lingerTimer == null) {
      _lingerTimer = Timer(_kLingerDuration, () {
        _lingerTimer = null;
        FileOperationService.instance.clearFinished();
        if (mounted) {
          setState(() => _isDebouncePassed = false);
        }
      });
    }

    setState(() {});
  }

  double? _calculateAggregateProgress() {
    final active = FileOperationService.instance.activeOperations;
    if (active.isEmpty) return 1.0;

    int totalBytes = 0;
    int transferredBytes = 0;
    bool hasByteTracked = false;

    for (final op in active) {
      if (op.totalBytes > 0) {
        hasByteTracked = true;
        totalBytes += op.totalBytes;
        transferredBytes += op.transferredBytes;
      }
    }

    if (hasByteTracked && totalBytes > 0) {
      return (transferredBytes / totalBytes).clamp(0.0, 1.0);
    }

    final fractions = active.map((op) => op.progressFraction).toList();
    if (fractions.every((f) => f == null)) return null; // Indeterminate

    double sum = 0;
    int count = 0;
    for (final f in fractions) {
      if (f != null) {
        sum += f;
        count++;
      }
    }
    return count > 0 ? (sum / active.length).clamp(0.0, 1.0) : null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDebouncePassed) return const SizedBox.shrink();

    final svc = FileOperationService.instance;
    final ops = svc.operations;
    if (ops.isEmpty) return const SizedBox.shrink();

    final activeCount = svc.activeCount;
    final hasActive = activeCount > 0;

    final cs = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;

    final isError = ops.any(
      (op) =>
          op.status == FileOperationStatus.failed ||
          op.status == FileOperationStatus.diskFull,
    );
    final isWarning = !isError && ops.any(
      (op) => op.status == FileOperationStatus.completedWithErrors,
    );

    final Color statusColor = isError
        ? cs.error
        : isWarning
        ? semantic.warning
        : cs.primary;

    final double? progress = hasActive ? _calculateAggregateProgress() : 1.0;

    return Tooltip(
      message: context.l10n.transferActivityTooltip,
      child: IconButton(
        padding: const EdgeInsets.all(8.0),
        onPressed: () => FileOperationsSheet.show(context),
        icon: Badge(
          isLabelVisible: activeCount > 1,
          label: Text(
            '$activeCount',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
          ),
          backgroundColor: cs.primary,
          textColor: cs.onPrimary,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Circular Progress Ring
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.5,
                    color: statusColor,
                    backgroundColor: statusColor.withValues(alpha: 0.2),
                  ),
                ),
                // Center Icon
                AnimatedSwitcher(
                  duration: AppMotion.short2,
                  switchInCurve: AppMotion.standard,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: hasActive
                      ? Icon(
                          Icons.swap_horiz_rounded,
                          key: const ValueKey('active'),
                          size: 15,
                          color: statusColor,
                        )
                      : isError
                      ? Icon(
                          Icons.error_outline_rounded,
                          key: const ValueKey('error'),
                          size: 15,
                          color: cs.error,
                        )
                      : isWarning
                      ? Icon(
                          Icons.warning_amber_rounded,
                          key: const ValueKey('warning'),
                          size: 15,
                          color: semantic.warning,
                        )
                      : Icon(
                          Icons.check_rounded,
                          key: const ValueKey('done'),
                          size: 15,
                          color: cs.primary,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
