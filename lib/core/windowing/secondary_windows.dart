// See desktop_windowing.dart for why this file imports Flutter internals.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'package:flutter/src/widgets/_window.dart' as flutter_window;
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/windowing/desktop_windowing.dart';

const String _kLogTag = 'SecondaryWindows';

/// One open native secondary window.
class SecondaryWindowEntry {
  SecondaryWindowEntry._({
    required this.key,
    required this.title,
    required this.contentBuilder,
  });

  /// Identifies what the window shows (for example `config:<vault uri>`), so
  /// asking for the same thing twice brings the existing window forward.
  final String key;

  final String title;

  /// Builds the window's page. It runs under the window's own `MaterialApp`,
  /// so it gets its own `Navigator`, theme and localizations.
  final WidgetBuilder contentBuilder;

  /// The window's own navigator (the main window's is `appNavigatorKey`).
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'secondaryWindowNavigator',
  );

  late final flutter_window.WindowController _controller;

  /// Closes this window.
  void close() => SecondaryWindows.instance.close(key);
}

/// Native windows other than the main one (Linux and Windows).
///
/// The main window stays what the platform runner created and `runApp` draws
/// into, so none of the runner code changes. Every window opened here is an
/// extra view in the same widget tree, which means Riverpod state and every
/// service are shared with the main window for free; only the `Navigator`,
/// `Theme` and `Localizations` are per window (see `SecondaryWindowApp`).
///
/// [SecondaryWindowsHost] must sit below the `ProviderScope` and above the
/// app's `MaterialApp`.
class SecondaryWindows extends ChangeNotifier {
  SecondaryWindows._();

  static final SecondaryWindows instance = SecondaryWindows._();

  final Map<String, SecondaryWindowEntry> _entries =
      <String, SecondaryWindowEntry>{};

  List<SecondaryWindowEntry> get entries =>
      List<SecondaryWindowEntry>.unmodifiable(_entries.values);

  /// Opens a window showing [builder], or brings the one already open under
  /// [key] to the front.
  ///
  /// Returns false when native windows are not available (Android, a
  /// `VE_MULTI_WINDOW=0` run, or an embedder that refused); the caller then
  /// shows the page inside the main window instead.
  bool open({
    required String key,
    required String title,
    required WidgetBuilder builder,
    Size size = const Size(560, 780),
    BoxConstraints constraints = const BoxConstraints(
      minWidth: 420,
      minHeight: 480,
    ),
  }) {
    final existing = _entries[key];
    if (existing != null) {
      try {
        existing._controller.activate();
      } catch (error) {
        VeLog.w(_kLogTag, 'Could not bring window "$key" forward', error);
      }
      return true;
    }
    if (!DesktopWindowing.ensureReady()) return false;

    final entry = SecondaryWindowEntry._(
      key: key,
      title: title,
      contentBuilder: builder,
    );
    try {
      entry._controller = flutter_window.WindowController(
        size: size,
        constraints: constraints,
        title: title,
        delegate: _EntryDelegate(this, entry),
      );
    } catch (error) {
      VeLog.w(_kLogTag, 'Could not create window "$key"', error);
      return false;
    }
    _entries[key] = entry;
    notifyListeners();
    return true;
  }

  /// Closes the window opened under [key], if any.
  void close(String key) {
    final entry = _entries[key];
    if (entry != null) _destroy(entry);
  }

  /// Closes every secondary window. Called when the app locks: anything that
  /// was showing vault settings must not stay on screen behind the lock gate.
  void closeAll() {
    for (final entry in List<SecondaryWindowEntry>.of(_entries.values)) {
      _destroy(entry);
    }
  }

  void _destroy(SecondaryWindowEntry entry) {
    try {
      // Destroying the native window reports back through
      // _EntryDelegate.onWindowDestroyed, which removes the entry.
      entry._controller.destroy();
    } catch (error) {
      VeLog.w(_kLogTag, 'Destroying window "${entry.key}" failed', error);
    }
    // Idempotent; covers a platform that did not call the delegate.
    _forget(entry);
  }

  void _forget(SecondaryWindowEntry entry) {
    if (!identical(_entries[entry.key], entry)) return;
    _entries.remove(entry.key);
    notifyListeners();
    // The window widget listens to the controller until the frame that drops
    // it from the tree, so the controller is disposed after that frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      entry._controller.dispose();
    });
    // addPostFrameCallback does not schedule a frame by itself.
    WidgetsBinding.instance.scheduleFrame();
  }
}

class _EntryDelegate with flutter_window.WindowControllerDelegate {
  _EntryDelegate(this._windows, this._entry);

  final SecondaryWindows _windows;
  final SecondaryWindowEntry _entry;

  // onWindowCloseRequested keeps the default, which destroys the window. The
  // settings page has no unsaved-changes guard, so a close button behaves like
  // the back button did. If that page ever gets a PopScope, route the request
  // through _entry.navigatorKey.currentState?.maybePop() here instead.

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    _windows._forget(_entry);
  }
}

/// Draws every open [SecondaryWindows] entry as an extra view next to [child].
///
/// [windowBuilder] returns the content of one window; it is where the app puts
/// its per-window `MaterialApp`. It runs below this widget, so it sees the
/// `ProviderScope` above it.
class SecondaryWindowsHost extends StatefulWidget {
  const SecondaryWindowsHost({
    super.key,
    required this.windowBuilder,
    required this.child,
  });

  final Widget Function(BuildContext context, SecondaryWindowEntry entry)
  windowBuilder;

  final Widget child;

  @override
  State<SecondaryWindowsHost> createState() => _SecondaryWindowsHostState();
}

class _SecondaryWindowsHostState extends State<SecondaryWindowsHost> {
  final SecondaryWindows _windows = SecondaryWindows.instance;

  @override
  void initState() {
    super.initState();
    _windows.addListener(_onWindowsChanged);
  }

  @override
  void dispose() {
    _windows.removeListener(_onWindowsChanged);
    super.dispose();
  }

  void _onWindowsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final entries = _windows.entries;
    // The ViewAnchor is always there (with a null view while nothing is open)
    // so [child] keeps the same position in the tree and never loses its state
    // when the first window opens.
    return ViewAnchor(
      view: entries.isEmpty
          ? null
          : ViewCollection(
              views: [
                for (final entry in entries)
                  flutter_window.Window(
                    key: ValueKey<String>(entry.key),
                    controller: entry._controller,
                    child: Builder(
                      builder: (context) =>
                          widget.windowBuilder(context, entry),
                    ),
                  ),
              ],
            ),
      child: widget.child,
    );
  }
}
