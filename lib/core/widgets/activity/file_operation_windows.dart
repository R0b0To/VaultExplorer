import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/widgets/activity/file_operation_progress_page.dart';
import 'package:vaultexplorer/core/windowing/desktop_windowing.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/core/windowing/window_caption.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';

/// Gives every file operation that takes a while a window of its own on Linux
/// and Windows, like the system file manager's copy dialog, instead of the
/// progress ring in the toolbar (see `AppBarTransferButton`).
///
///  * A window opens once an operation has been running for a moment, so a
///    rename or a one-file delete never flashes one.
///  * One window per operation, so two copies at once are two windows.
///  * When the operation finishes, or is cancelled, its window closes by
///    itself. An operation that ends with a problem opens (or keeps) its
///    window to say what failed, until it is closed.
///  * Closing a window while its operation is still running cancels it, as in
///    the system's copy dialog. The cancel button in the window does the same.
///
/// Where native windows are not available (see [isAvailable]) nothing here
/// runs, and the ring keeps doing what it always did.
class FileOperationWindows {
  FileOperationWindows(this._service) {
    _service.addListener(_onServiceChanged);
    _onServiceChanged();
  }

  /// Whether file operations get windows in this run: Linux or Windows, with
  /// native windows working.
  static bool get isAvailable =>
      DesktopWindowing.isSupportedPlatform && DesktopWindowing.ensureReady();

  /// How long an operation runs before its window opens.
  static const Duration showDelay = Duration(milliseconds: 800);

  /// How long a finished operation stays in the service's list. Other parts
  /// of the app look at finished operations there (to refresh a folder, say).
  static const Duration lingerAfterFinish = Duration(seconds: 4);

  final FileOperationService _service;

  final Set<FileOperation> _observed = <FileOperation>{};
  final Map<int, Timer> _showTimers = <int, Timer>{};
  final Map<int, Timer> _dismissTimers = <int, Timer>{};

  /// Operations that have a window open right now.
  final Set<int> _windowed = <int>{};

  /// Operations that must not get a window (again): the person closed or
  /// cancelled it, or no window could be made.
  final Set<int> _declined = <int>{};

  bool _disposed = false;

  String _keyOf(FileOperation op) => 'fileop:${op.id}';

  void _onServiceChanged() {
    if (_disposed) return;
    _syncObserved(_service.operations);
    _evaluate();
  }

  /// The service does not report progress of its operations, only that the
  /// list changed, so each operation is listened to itself.
  void _syncObserved(List<FileOperation> operations) {
    final current = operations.toSet();
    for (final op in _observed.difference(current).toList()) {
      op.removeListener(_evaluate);
      _observed.remove(op);
      _showTimers.remove(op.id)?.cancel();
      _dismissTimers.remove(op.id)?.cancel();
      _declined.remove(op.id);
    }
    for (final op in current) {
      if (_observed.add(op)) op.addListener(_evaluate);
    }
  }

  void _evaluate() {
    if (_disposed) return;
    for (final op in List<FileOperation>.of(_observed)) {
      switch (op.status) {
        case FileOperationStatus.pending:
          break;
        case FileOperationStatus.running:
          _considerOpening(op);
        case FileOperationStatus.completed:
        case FileOperationStatus.cancelled:
          _finish(op);
        case FileOperationStatus.completedWithErrors:
        case FileOperationStatus.diskFull:
        case FileOperationStatus.failed:
          if (op.cancelRequested || _declined.contains(op.id)) {
            // The person cancelled it or closed its window: nothing to say.
            if (!_windowed.contains(op.id)) _dismissLater(op);
          } else {
            _open(op);
          }
      }
    }
  }

  void _considerOpening(FileOperation op) {
    if (_windowed.contains(op.id) || _declined.contains(op.id)) return;
    final started = op.runStartTime;
    if (started == null) return;
    final wait = showDelay - DateTime.now().difference(started);
    if (wait <= Duration.zero) {
      _open(op);
      return;
    }
    // Look again when the delay is over. Nothing else may report in by then.
    _showTimers[op.id] ??= Timer(wait, () {
      _showTimers.remove(op.id);
      _evaluate();
    });
  }

  void _open(FileOperation op) {
    if (_windowed.contains(op.id)) return;
    _showTimers.remove(op.id)?.cancel();
    final key = _keyOf(op);
    final opened = SecondaryWindows.instance.open(
      key: key,
      title: op.shortSummary,
      size: const Size(500, 420),
      constraints: const BoxConstraints(minWidth: 440, minHeight: 360),
      builder: (_) => FileOperationProgressPage(operation: op),
      onCreated: (entry) => unawaited(centerWindowOver(entry.viewId)),
    );
    if (!opened) {
      _declined.add(op.id);
      return;
    }
    _windowed.add(op.id);
    final entry = SecondaryWindows.instance.entryFor(key);
    if (entry != null) {
      unawaited(entry.closed.then((_) => _onWindowClosed(op)));
    }
  }

  /// The operation ended without a problem (or was cancelled): its window has
  /// nothing more to say.
  void _finish(FileOperation op) {
    _showTimers.remove(op.id)?.cancel();
    if (_windowed.contains(op.id)) {
      SecondaryWindows.instance.close(_keyOf(op));
    }
    _dismissLater(op);
  }

  void _dismissLater(FileOperation op) {
    _dismissTimers.putIfAbsent(
      op.id,
      () => Timer(lingerAfterFinish, () {
        _dismissTimers.remove(op.id);
        if (!_disposed) _service.dismiss(op.id);
      }),
    );
  }

  void _onWindowClosed(FileOperation op) {
    _windowed.remove(op.id);
    if (_disposed) return;
    final running =
        op.status == FileOperationStatus.pending ||
        op.status == FileOperationStatus.running;
    if (running) {
      _declined.add(op.id);
      op.requestCancel();
      return;
    }
    switch (op.status) {
      case FileOperationStatus.completedWithErrors:
      case FileOperationStatus.diskFull:
      case FileOperationStatus.failed:
        // The result was read (or ignored): it is not needed any more, and
        // must not bring its window back before it is gone from the list.
        _declined.add(op.id);
        _service.dismiss(op.id);
      case FileOperationStatus.pending:
      case FileOperationStatus.running:
      case FileOperationStatus.completed:
      case FileOperationStatus.cancelled:
        break;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _service.removeListener(_onServiceChanged);
    for (final op in _observed) {
      op.removeListener(_evaluate);
    }
    _observed.clear();
    for (final timer in _showTimers.values) {
      timer.cancel();
    }
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    _showTimers.clear();
    _dismissTimers.clear();
  }
}

/// Starts [FileOperationWindows] for the app. Watch it once from the root of
/// the app; it is null where file operations do not get windows.
final fileOperationWindowsProvider = Provider<FileOperationWindows?>((ref) {
  if (!FileOperationWindows.isAvailable) return null;
  final windows = FileOperationWindows(ref.watch(fileOperationServiceProvider));
  ref.onDispose(windows.dispose);
  return windows;
});
