import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/activity/file_operations_sheet.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';

/// App bar action button that displays active file operations and transfers.
class AppBarTransferButton extends ConsumerStatefulWidget {
  const AppBarTransferButton({super.key});

  @override
  ConsumerState<AppBarTransferButton> createState() =>
      _AppBarTransferButtonState();
}

class _AppBarTransferButtonState extends ConsumerState<AppBarTransferButton> {
  static const _kShowDelay = Duration(milliseconds: 800);
  static const _kLingerDuration = Duration(seconds: 4);

  Timer? _showDebounceTimer;
  Timer? _lingerTimer;

  bool _isDebouncePassed = false;
  bool _initialEvaluating = false;
  DateTime? _mirrorPushStartedAt;
  final Set<FileOperation> _observedOps = {};

  // Store reference in a field instead of reading 'ref' on every getter access
  late final FileOperationService _svc;

  @override
  void initState() {
    super.initState();
    _svc = ref.read(fileOperationServiceProvider);
    _svc.addListener(_onServiceChanged);
    FileOperationsSheet.isOpenNotifier.addListener(_onSheetStateChanged);
    _syncObservedOperations();
    _initialEvaluating = true;
    _evaluateState();
    _initialEvaluating = false;
  }

  @override
  void dispose() {
    _showDebounceTimer?.cancel();
    _lingerTimer?.cancel();
    _svc.removeListener(_onServiceChanged);
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
    final currentOps = _svc.operations;
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

  void _updateState({bool? debouncePassed}) {
    if (debouncePassed != null) {
      _isDebouncePassed = debouncePassed;
    }
    if (!_initialEvaluating && mounted) {
      setState(() {});
    }
  }

  void _evaluateState() {
    if (!mounted && !_initialEvaluating) return;

    final svc = _svc;
    final ops = svc.operations;
    final activeOps = svc.activeOperations;
    final now = DateTime.now();
    final mirrorPushActive = svc.mirrorPushActiveCount > 0;
    if (mirrorPushActive) {
      _mirrorPushStartedAt ??= now;
    } else {
      _mirrorPushStartedAt = null;
    }
    final hasActiveActivity = activeOps.isNotEmpty || mirrorPushActive;

    final hasErrors = ops.any(
      (op) =>
          op.status == FileOperationStatus.failed ||
          op.status == FileOperationStatus.diskFull ||
          op.status == FileOperationStatus.completedWithErrors,
    );

    // 1. If there are no operations at all, reset debounce and cancel timers.
    if (ops.isEmpty && !mirrorPushActive) {
      _showDebounceTimer?.cancel();
      _showDebounceTimer = null;
      _lingerTimer?.cancel();
      _lingerTimer = null;
      _updateState(debouncePassed: false);
      return;
    }

    // 2. If there are active operations:
    if (hasActiveActivity) {
      _lingerTimer?.cancel();
      _lingerTimer = null;

      final earliestStart = activeOps.isEmpty
          ? (_mirrorPushStartedAt ?? now)
          : activeOps
                .map((op) => op.runStartTime ?? op.createdAt)
                .reduce((a, b) => a.isBefore(b) ? a : b);
      final elapsed = now.difference(earliestStart);

      if (elapsed >= _kShowDelay) {
        _showDebounceTimer?.cancel();
        _showDebounceTimer = null;
        _updateState(debouncePassed: true);
        return;
      }

      if (_isDebouncePassed) {
        _showDebounceTimer?.cancel();
        _showDebounceTimer = null;
        _updateState();
        return;
      }

      final remaining = _kShowDelay - elapsed;
      _showDebounceTimer?.cancel();
      _showDebounceTimer = Timer(remaining, () {
        _showDebounceTimer = null;
        if (mounted &&
            (_svc.operations.isNotEmpty || _svc.mirrorPushActiveCount > 0)) {
          setState(() => _isDebouncePassed = true);
        }
      });
      return;
    }

    // 3. No active operations, but lingering completed/failed operations exist:
    _showDebounceTimer?.cancel();
    _showDebounceTimer = null;

    // If errors exist, always show so the user isn't unaware of failures
    if (hasErrors) {
      _lingerTimer?.cancel();
      _lingerTimer = null;
      _updateState(debouncePassed: true);
      return;
    }

    final qualifiedCompletedOps = ops.where((op) {
      final start = op.runStartTime ?? op.createdAt;
      final end = op.completedAt ?? now;
      return end.difference(start) >= _kShowDelay;
    }).toList();

    if (qualifiedCompletedOps.isEmpty && !_isDebouncePassed) {
      _svc.clearFinished();
      return;
    }

    // If sheet is open, pause the linger timer so items don't disappear while looking
    if (FileOperationsSheet.isOpenNotifier.value) {
      _lingerTimer?.cancel();
      _lingerTimer = null;
      _updateState(debouncePassed: true);
      return;
    }

    final latestCompletion = ops
        .map((op) => op.completedAt ?? op.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final lingerElapsed = now.difference(latestCompletion);

    if (lingerElapsed >= _kLingerDuration) {
      _lingerTimer?.cancel();
      _lingerTimer = null;
      _svc.clearFinished();
      _updateState(debouncePassed: false);
      return;
    }

    final remainingLinger = _kLingerDuration - lingerElapsed;
    _updateState(debouncePassed: true);

    _lingerTimer ??= Timer(remainingLinger, () {
      _lingerTimer = null;
      _svc.clearFinished();
      if (mounted) {
        setState(() => _isDebouncePassed = false);
      }
    });
  }

  double? _calculateAggregateProgress() {
    if (_svc.mirrorPushActiveCount > 0) return null;
    final active = _svc.activeOperations;
    if (active.isEmpty) {
      return _svc.mirrorPushActiveCount > 0 ? null : 1.0;
    }

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
    final svc = _svc;
    final ops = svc.operations;
    final isVisible =
        _isDebouncePassed && (ops.isNotEmpty || svc.mirrorPushActiveCount > 0);

    final activeCount = svc.combinedActivityCount;
    final hasActive = activeCount > 0;

    final cs = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;

    final isError = ops.any(
      (op) =>
          op.status == FileOperationStatus.failed ||
          op.status == FileOperationStatus.diskFull,
    );
    final isWarning =
        !isError &&
        ops.any((op) => op.status == FileOperationStatus.completedWithErrors);

    final Color statusColor = isError
        ? cs.error
        : isWarning
        ? semantic.warning
        : cs.primary;

    final double? progress = hasActive ? _calculateAggregateProgress() : 1.0;

    return SizedBox(
      width: 48,
      height: 48,
      child: AnimatedOpacity(
        opacity: isVisible ? 1 : 0,
        duration: AppMotion.short2,
        child: IgnorePointer(
          ignoring: !isVisible,
          child: ExcludeSemantics(
            excluding: !isVisible,
            child: Tooltip(
              message: context.l10n.transferActivityTooltip,
              child: IconButton(
                padding: const EdgeInsets.all(8.0),
                onPressed: () => FileOperationsSheet.show(context),
                icon: Badge(
                  isLabelVisible: activeCount > 1,
                  label: Text(
                    '$activeCount',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
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
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
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
            ),
          ),
        ),
      ),
    );
  }
}
