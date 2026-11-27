import 'dart:async';


import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/widgets/activity/file_operations_window_page.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_title_bar.dart';
import 'package:vaultexplorer/core/windowing/desktop_windowing.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/core/windowing/window_caption.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';

/// Gives the file operations that take a while one window on Linux and
/// Windows, like the system file manager's copy dialog, instead of the
/// progress ring in the toolbar (see `AppBarTransferButton`).
///
///  * A single window shows every operation, one card per operation. Starting
///    another copy while one runs adds a card to the open window instead of
///    opening a second window.
///  * The window is small and sits in the corner of the screen, like a
///    notification. It cannot be resized or maximized; on Windows it grows
///    and shrinks with its cards, and many operations scroll inside it.
///  * An operation joins the window once it has been running for a moment, so
///    a rename or a one-file delete never flashes a card.
///  * When an operation finishes, or is cancelled, its card leaves; the window
///    closes by itself once its last card is gone. An operation that ends with
///    a problem keeps its card, saying what failed, until it is closed.
///  * Closing the window while operations are still running cancels them, as
///    in the system's copy dialog. The cancel button of a card cancels just
///    that operation.
///
/// Where native windows are not available (see [isAvailable]) nothing here
/// runs, and the ring keeps doing what it always did.
class FileOperationWindows extends ChangeNotifier {
  FileOperationWindows(this._service) {
    _service.addListener(_onServiceChanged);
    _onServiceChanged();
  }

  /// Whether file operations get a window in this run: Linux or Windows, with
  /// native windows working.
  static bool get isAvailable =>
      DesktopWindowing.isSupportedPlatform && DesktopWindowing.ensureReady();

  /// The one window all operations share.
  static const String windowKey = 'fileops';

  /// The height the window is opened with where the runner cannot resize it
  /// (Linux): room for two cards. On Windows it follows its cards.
  static const double fixedHeight = 190;

  /// How long an operation runs before it appears in the window.
  static const Duration showDelay = Duration(milliseconds: 800);

  /// How long a finished operation stays in the service's list. Other parts
  /// of the app look at finished operations there (to refresh a folder, say).
  static const Duration lingerAfterFinish = Duration(seconds: 4);

  final FileOperationService _service;

  final Set<FileOperation> _observed = <FileOperation>{};
  final Map<int, Timer> _showTimers = <int, Timer>{};
  final Map<int, Timer> _dismissTimers = <int, Timer>{};

  /// The operations the window shows, in the order they joined (oldest first).
  final List<FileOperation> _shown = <FileOperation>[];

  /// Operations that must not get a card (again): the person closed or
  /// cancelled it, or no window could be made.
  final Set<int> _declined = <int>{};

  /// The window while one is open (or being opened by us).
  SecondaryWindowEntry? _entry;
  bool _opening = false;
  bool _disposed = false;

  /// The operations the window shows right now.
  List<FileOperation> get shown => List<FileOperation>.unmodifiable(_shown);

  void _onServiceChanged() {
    if (_disposed) return;
    _syncObserved(_service.operations);
    _evaluate();
  }

  /// The service does not report progress of its operations, only that the
  /// list changed, so each operation is listened to itself.
  void _syncObserved(List<FileOperation> operations) {
    final current = operations.toSet();
    var changed = false;
    for (final op in _observed.difference(current).toList()) {
      op.removeListener(_evaluate);
      _observed.remove(op);
      _showTimers.remove(op.id)?.cancel();
      _dismissTimers.remove(op.id)?.cancel();
      _declined.remove(op.id);
      if (_shown.remove(op)) changed = true;
    }
    for (final op in current) {
      if (_observed.add(op)) op.addListener(_evaluate);
    }
    if (changed) _afterShownChanged();
  }

  void _evaluate() {
    if (_disposed) return;
    var changed = false;
    for (final op in List<FileOperation>.of(_observed)) {
      switch (op.status) {
        case FileOperationStatus.pending:
          break;
        case FileOperationStatus.running:
          changed |= _considerShowing(op);
        case FileOperationStatus.completed:
        case FileOperationStatus.cancelled:
          changed |= _finish(op);
        case FileOperationStatus.completedWithErrors:
        case FileOperationStatus.diskFull:
        case FileOperationStatus.failed:
          if (op.cancelRequested || _declined.contains(op.id)) {
            // The person cancelled it or closed its card: nothing to say.
            if (_shown.remove(op)) changed = true;
            _dismissLater(op);
          } else if (_show(op)) {
            changed = true;
          }
      }
    }
    if (changed) _afterShownChanged();
  }

  bool _considerShowing(FileOperation op) {
    if (_shown.contains(op) || _declined.contains(op.id)) return false;
    final started = op.runStartTime;
    if (started == null) return false;
    final wait = showDelay - DateTime.now().difference(started);
    if (wait <= Duration.zero) return _show(op);
    // Look again when the delay is over. Nothing else may report in by then.
    _showTimers[op.id] ??= Timer(wait, () {
      _showTimers.remove(op.id);
      _evaluate();
    });
    return false;
  }

  /// Adds [op]'s card. Returns whether it was added (it is not when it is
  /// there already).
  bool _show(FileOperation op) {
    if (_shown.contains(op)) return false;
    _showTimers.remove(op.id)?.cancel();
    _shown.add(op);
    return true;
  }

  /// The operation ended without a problem (or was cancelled): its card has
  /// nothing more to say. Returns whether a card left.
  bool _finish(FileOperation op) {
    _showTimers.remove(op.id)?.cancel();
    final removed = _shown.remove(op);
    _dismissLater(op);
    return removed;
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

  /// The person closed the card of an operation that ended with a problem.
  /// The result was read (or ignored): it is not needed any more, and must
  /// not bring its card back before it is gone from the service's list.
  void dismissResult(FileOperation op) {
    if (_disposed) return;
    _declined.add(op.id);
    final removed = _shown.remove(op);
    _service.dismiss(op.id);
    if (removed) _afterShownChanged();
  }

  /// Brings the window in line with the cards: closes it once there are none,
  /// opens it when the first one arrives, and tells the window to redraw.
  void _afterShownChanged() {
    if (_disposed) return;
    if (_shown.isEmpty) {
      _closeWindow();
    } else {
      unawaited(_openWindow());
    }
    notifyListeners();
  }

  Future<void> _openWindow() async {
    if (_entry != null || _opening) return;
    _opening = true;
    // A native window must not be created inside a frame, and an operation's
    // listener may well run in one.
    await SecondaryWindows.untilBetweenFrames();
    _opening = false;
    if (_disposed || _shown.isEmpty || _entry != null) return;

    final first = _shown.first;
    const width = FileOperationsWindowPage.windowWidth;
    // Where the runner can resize the window (Windows) it follows its cards,
    // so the window may take any height between one card and a full list;
    // elsewhere it is pinned to one size.
    final canResize = PlatformFeatures.isWindows;
    final height = canResize
        ? FileOperationsWindowPage.listHeightFor(_shown) +
              kDesktopTitleBarHeight
        : fixedHeight;
    final opened = SecondaryWindows.instance.open(
      key: windowKey,
      title: first.shortSummary,
      size: Size(width, height),
      resizable: false,
      fixedConstraints: canResize
          ? const BoxConstraints(
              minWidth: width,
              maxWidth: width,
              minHeight: 100,
              maxHeight: 600,
            )
          : null,
      builder: (_) => FileOperationsWindowPage(manager: this),
      onCreated: (entry) => unawaited(dockWindowBottomRight(entry.viewId)),
    );
    if (!opened) {
      // No window can be made: the ring in the toolbar keeps showing them.
      _declined.addAll(_shown.map((op) => op.id));
      _shown.clear();
      notifyListeners();
      return;
    }
    final entry = SecondaryWindows.instance.entryFor(windowKey);
    _entry = entry;
    if (entry != null) {
      unawaited(entry.closed.then((_) => _onWindowClosed(entry)));
    }
  }

  /// Closes the window because nothing is left to show.
  void _closeWindow() {
    final entry = _entry;
    if (entry == null) return;
    // Forget it first, so its closing is not taken for the person closing it
    // (see _onWindowClosed) if another operation has joined by then.
    _entry = null;
    SecondaryWindows.instance.close(windowKey);
  }

  /// The window is gone. When the person closed it, whatever it still showed
  /// goes with it: running operations are cancelled, results are dropped.
  void _onWindowClosed(SecondaryWindowEntry entry) {
    if (!identical(entry, _entry)) return;
    _entry = null;
    if (_disposed) return;
    for (final op in List<FileOperation>.of(_shown)) {
      _declined.add(op.id);
      final running =
          op.status == FileOperationStatus.pending ||
          op.status == FileOperationStatus.running;
      if (running) {
        op.requestCancel();
      } else {
        _service.dismiss(op.id);
      }
    }
    _shown.clear();
    notifyListeners();
  }

  @override
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
    if (_entry != null) {
      _entry = null;
      SecondaryWindows.instance.close(windowKey);
    }
    super.dispose();
  }
}

/// Starts [FileOperationWindows] for the app. Watch it once from the root of
/// the app; it is null where file operations do not get a window.
final fileOperationWindowsProvider = Provider<FileOperationWindows?>((ref) {
  if (!FileOperationWindows.isAvailable) return null;
  final windows = FileOperationWindows(ref.watch(fileOperationServiceProvider));
  ref.onDispose(windows.dispose);
  return windows;
});
