// See desktop_windowing.dart for why this file imports Flutter internals.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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
    required this.survivesMainClose,
    required this.resizable,
  });

  /// Identifies what the window shows (for example `config:<vault uri>`), so
  /// asking for the same thing twice brings the existing window forward.
  final String key;

  /// Whether this window stays open when the main window is closed.
  ///
  /// A window that can stand on its own (a file manager window) keeps the app
  /// running, like an Explorer window outliving the one it was opened from; the
  /// app ends when the last such window closes. A window that only exists to
  /// serve the main one (a vault's settings) closes along with it.
  /// See `DesktopWindowPolicy`.
  final bool survivesMainClose;

  /// Whether the person can change this window's size: drag its edges,
  /// maximize it or snap it. A fixed-size window (the file operations window)
  /// has no maximize button either. See [SecondaryWindows.open].
  final bool resizable;

  String title;

  /// Builds the window's page. It runs under the window's own `MaterialApp`,
  /// so it gets its own `Navigator`, theme and localizations.
  final WidgetBuilder contentBuilder;

  /// The window's own navigator (the main window's is `appNavigatorKey`).
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'secondaryWindowNavigator',
  );

  late final flutter_window.WindowController _controller;

  final Completer<void> _closedCompleter = Completer<void>();

  /// Completes once this window is gone, however it was closed (its own
  /// close button, the page popping, a lock, or the main window closing).
  ///
  /// A page that is shown in a window instead of in-window can await this
  /// the way it awaited `Navigator.push`.
  Future<void> get closed => _closedCompleter.future;

  /// The id of this window's view, which is how the platform runner knows the
  /// window (see `windowChannelArgsFor`).
  int get viewId => _controller.rootView.viewId;

  /// Closes this window.
  void close() => SecondaryWindows.instance.close(key);

  /// Changes the window's title: what the taskbar and the window switcher
  /// show, and the native title bar where the window has one.
  void setTitle(String value) {
    if (value == title) return;
    title = value;
    try {
      _controller.setTitle(value);
    } catch (error) {
      VeLog.w(_kLogTag, 'Could not retitle window "$key"', error);
    }
  }
}

/// Lets the page inside a secondary window reach the window it is in (to close
/// it, or to set its title).
class SecondaryWindowScope extends InheritedWidget {
  const SecondaryWindowScope({
    super.key,
    required this.entry,
    required super.child,
  });

  final SecondaryWindowEntry entry;

  /// The window [context] is in, or null in the main window (or in a build
  /// without native windows).
  static SecondaryWindowEntry? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SecondaryWindowScope>()?.entry;

  @override
  bool updateShouldNotify(SecondaryWindowScope oldWidget) =>
      entry != oldWidget.entry;
}

/// Native windows other than the main one (Linux and Windows).
///
/// Every window of the app, the main one included, is a view in one widget
/// tree: Riverpod state and every service are shared between them for free, and
/// only the `Navigator`, `Theme` and `Localizations` are per window (see
/// `SecondaryWindowApp`). `DesktopAppHost` is the root of that tree and draws
/// the views of this registry next to the main window's, from [buildViews].
/// Because no window is the platform's own, none of them is the anchor the
/// others hang from: closing any of them leaves the rest open, and
/// `DesktopWindowPolicy` decides when the app ends.
class SecondaryWindows extends ChangeNotifier {
  SecondaryWindows._();

  static final SecondaryWindows instance = SecondaryWindows._();

  final Map<String, SecondaryWindowEntry> _entries =
      <String, SecondaryWindowEntry>{};

  List<SecondaryWindowEntry> get entries =>
      List<SecondaryWindowEntry>.unmodifiable(_entries.values);

  /// The window open under [key], if any.
  SecondaryWindowEntry? entryFor(String key) => _entries[key];

  /// Completes once the scheduler is between frames (immediately when it
  /// already is).
  ///
  /// Creating a native window must not happen while a frame is being built or
  /// while its post-frame callbacks run (an `addPostFrameCallback` is exactly
  /// that). On Windows the native create call pumps the message loop before it
  /// returns, which lets the engine start a new frame inside the frame that is
  /// still running; the scheduler then fails its `schedulerPhase == idle` and
  /// `midFrameMicrotasks` assertions, and the new window never gets a valid
  /// first frame (it ends up blank or behind the main window).
  ///
  /// A caller that may run inside a frame awaits this before [open].
  static Future<void> untilBetweenFrames() {
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      return SynchronousFuture<void>(null);
    }
    final done = Completer<void>();
    // A timer fires on a later turn of the event loop, after the frame that
    // is running now has returned.
    Timer.run(done.complete);
    return done.future;
  }

  /// Opens a window showing [builder], or brings the one already open under
  /// [key] to the front.
  ///
  /// Must not be called from inside a frame; see [untilBetweenFrames].
  ///
  /// With [survivesMainClose] the window outlives the main window: closing the
  /// main window leaves it open, and the app ends when the last window opened
  /// this way closes.
  ///
  /// [onCreated] runs once, right after a new window exists (not when an
  /// open one is brought forward), before its first frame. It is the moment to
  /// place the window, since the platform only shows it after that frame.
  ///
  /// With [resizable] false the window keeps exactly [size], or stays within
  /// [fixedConstraints] when the app itself changes its size (the file
  /// operations window grows with its cards): [constraints] is ignored, the
  /// runner
  /// takes away the resize border and the maximize box where it can (see
  /// `lockWindowSize`), and the caption row shows no maximize button.
  ///
  /// Returns false when native windows are not available (Android, a
  /// `VE_MULTI_WINDOW=0` run, or an embedder that refused); the caller then
  /// shows the page inside the main window instead.
  bool open({
    required String key,
    required String title,
    required WidgetBuilder builder,
    bool survivesMainClose = false,
    bool resizable = true,
    BoxConstraints? fixedConstraints,
    Size size = const Size(560, 780),
    BoxConstraints constraints = const BoxConstraints(
      minWidth: 420,
      minHeight: 480,
    ),
    void Function(SecondaryWindowEntry entry)? onCreated,
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
      survivesMainClose: survivesMainClose,
      resizable: resizable,
    );
    try {
      entry._controller = flutter_window.WindowController(
        size: size,
        constraints: resizable
            ? constraints
            : (fixedConstraints ?? BoxConstraints.tight(size)),
        title: title,
        delegate: _EntryDelegate(this, entry),
      );
    } catch (error) {
      VeLog.w(_kLogTag, 'Could not create window "$key"', error);
      return false;
    }
    _entries[key] = entry;
    notifyListeners();
    if (onCreated != null) {
      try {
        onCreated(entry);
      } catch (error) {
        VeLog.w(_kLogTag, 'Setting up window "$key" failed', error);
      }
    }
    return true;
  }

  /// Closes the window opened under [key], if any.
  void close(String key) {
    final entry = _entries[key];
    if (entry != null) _destroy(entry);
  }

  /// Whether a window that can stand on its own (see
  /// [SecondaryWindowEntry.survivesMainClose]) is open.
  bool get hasIndependentWindows =>
      _entries.values.any((entry) => entry.survivesMainClose);

  /// How many windows that can stand on their own are open.
  int get independentWindowCount =>
      _entries.values.where((entry) => entry.survivesMainClose).length;

  /// Closes every secondary window. Called when the app locks: anything that
  /// was showing vault settings must not stay on screen behind the lock gate.
  void closeAll() {
    for (final entry in List<SecondaryWindowEntry>.of(_entries.values)) {
      _destroy(entry);
    }
  }

  /// Closes the windows that only exist to serve the main window. Called when
  /// the main window closes.
  void closeWindowsServingMain() {
    for (final entry in List<SecondaryWindowEntry>.of(_entries.values)) {
      if (!entry.survivesMainClose) _destroy(entry);
    }
  }

  /// The view of every open window, for the root `ViewCollection`.
  ///
  /// [windowBuilder] returns the content of one window; it is where the app
  /// puts its per-window `MaterialApp`. It runs below the root, so it sees the
  /// `ProviderScope` above it.
  List<Widget> buildViews(
    Widget Function(BuildContext context, SecondaryWindowEntry entry)
    windowBuilder,
  ) {
    return <Widget>[
      for (final entry in entries)
        flutter_window.Window(
          key: ValueKey<String>(entry.key),
          controller: entry._controller,
          child: Builder(builder: (context) => windowBuilder(context, entry)),
        ),
    ];
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
    if (!entry._closedCompleter.isCompleted) entry._closedCompleter.complete();
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
