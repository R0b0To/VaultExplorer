// See desktop_windowing.dart for why this file imports Flutter internals.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:async';
import 'dart:ui' show AppExitType, PlatformDispatcher;

import 'package:flutter/services.dart' show ServicesBinding;
import 'package:flutter/src/widgets/_window.dart' as flutter_window;
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/windowing/desktop_window_policy.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/core/windowing/window_caption.dart';

const String _kLogTag = 'AppWindows';

/// What the main window is called until the app sets another title. It is what
/// the platform runner used to give it.
const String _kMainWindowTitle = 'vaultexplorer';

/// The main window of the app on Linux and Windows, and the rules that tie it to
/// the other windows ([SecondaryWindows]).
///
/// The app starts with `runWidget` instead of `runApp`, so the platform's own
/// window (the one the runner creates) never shows anything. The main window is
/// created here like any other window: it can be closed on its own, the others
/// stay open, and the app ends when the last window is gone. Which window
/// closes with which, and when the app ends, is [DesktopWindowPolicy]'s call.
///
/// `DesktopAppHost` draws the windows from [buildViews].
class AppWindows extends ChangeNotifier {
  AppWindows._() {
    final secondary = SecondaryWindows.instance;
    _policy = DesktopWindowPolicy(
      independentWindowCount: () => secondary.independentWindowCount,
      closeWindowsServingMain: secondary.closeWindowsServingMain,
      closeAllSecondaryWindows: secondary.closeAll,
      openMainWindow: _openMainWindow,
      exitApp: _exitApp,
    );
    secondary.addListener(_policy.secondaryWindowsChanged);
  }

  static final AppWindows instance = AppWindows._();

  late final DesktopWindowPolicy _policy;

  flutter_window.WindowController? _main;

  // True when the platform refused to create a window for the main page and it
  // is drawn in the runner's own window instead (how the app always ran before
  // windows existed). Closing that window ends the app, as it did.
  bool _mainInRunnerWindow = false;

  /// Whether a main window is open.
  bool get isMainWindowOpen => _policy.isMainOpen;

  /// The id of the main window's view, or null when there is none (it was
  /// closed). It is how the runner knows the window (see
  /// `windowChannelArgsFor`).
  int? get mainViewId {
    final main = _main;
    if (main != null) {
      try {
        return main.rootView.viewId;
      } catch (_) {
        return null;
      }
    }
    return _mainInRunnerWindow
        ? PlatformDispatcher.instance.implicitView?.viewId
        : null;
  }

  /// Opens the main window at startup. Called once, by `DesktopAppHost`.
  void openStartupWindow() {
    if (_policy.isMainOpen) return;
    if (!_createMainWindow()) {
      if (PlatformDispatcher.instance.implicitView == null) {
        // Neither a native window nor the runner's: there is nowhere to show
        // the app, and a process nobody can see must not linger.
        VeLog.e(_kLogTag, 'No window of any kind for the main page');
        _exitApp();
        return;
      }
      VeLog.w(
        _kLogTag,
        'No native window for the main page; using the runner window',
      );
      _mainInRunnerWindow = true;
    } else {
      // The runner's own window stays empty: keep it from being shown.
      unawaited(declareRunnerWindowUnused());
    }
    _policy.mainWindowOpened();
  }

  /// Closes the main window, the way its own close button does: the windows
  /// that only serve it close with it, and the app ends unless a window that
  /// can stand on its own is left (see [DesktopWindowPolicy]).
  ///
  /// Where the main page is drawn in the runner's own window (no native
  /// windows), that window is all there is, so this ends the app.
  void closeMainWindow() {
    final main = _main;
    if (main != null) {
      try {
        // Reports back through the window's delegate, which does the rest.
        main.destroy();
      } catch (error) {
        VeLog.w(_kLogTag, 'Could not close the main window', error);
      }
      return;
    }
    if (_mainInRunnerWindow) _exitApp();
  }

  /// The app locked (or was told to). Everything the vaults showed closes, and
  /// the main window, which draws the lock gate, is there afterwards, even if
  /// the person had closed it while other windows kept the app running.
  void lockRequested() => _policy.lockRequested();

  /// The views of every window, for the root `ViewCollection`.
  List<Widget> buildViews({
    required WidgetBuilder mainBuilder,
    required Widget Function(BuildContext context, SecondaryWindowEntry entry)
    secondaryBuilder,
  }) {
    final main = _main;
    final runnerView = PlatformDispatcher.instance.implicitView;
    return <Widget>[
      if (_mainInRunnerWindow && runnerView != null)
        View(
          key: const ValueKey<String>('main-in-runner-window'),
          view: runnerView,
          child: Builder(builder: mainBuilder),
        )
      else if (main != null)
        // Keyed by the controller: a main window opened again after a lock is
        // a new window, never the old one's state carried over (both would
        // share the app's navigator key).
        flutter_window.Window(
          key: ObjectKey(main),
          controller: main,
          child: Builder(builder: mainBuilder),
        ),
      ...SecondaryWindows.instance.buildViews(secondaryBuilder),
    ];
  }

  bool _createMainWindow() {
    try {
      final delegate = _MainWindowDelegate(this);
      final controller = flutter_window.WindowController(
        size: const Size(1280, 720),
        constraints: const BoxConstraints(minWidth: 360, minHeight: 360),
        title: _kMainWindowTitle,
        delegate: delegate,
      );
      delegate.controller = controller;
      _main = controller;
      return true;
    } catch (error) {
      VeLog.w(_kLogTag, 'Could not create the main window', error);
      _main = null;
      return false;
    }
  }

  // Called by the policy when a lock needs a main window and there is none.
  void _openMainWindow() {
    if (!_createMainWindow()) {
      // Nothing to show the lock gate in. Ending the app is the safe outcome:
      // the exit clean-up locks every vault.
      _exitApp();
      return;
    }
    notifyListeners();
  }

  void _mainWindowDestroyed(flutter_window.WindowController controller) {
    if (!identical(_main, controller)) return;
    _main = null;
    // Redraw without the window, then let go of the controller once the frame
    // that drops the window widget is done (the widget listens to it until
    // then, as with the secondary windows).
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    WidgetsBinding.instance.scheduleFrame();
    _policy.mainWindowClosed();
  }

  void _exitApp() {
    VeLog.d(_kLogTag, 'Asking the platform to exit the app');
    try {
      // `cancelable` makes the framework ask first, which runs the desktop
      // clean-up (lock every vault, delete decrypted "open with" copies,
      // see DesktopEngineBinding). A `required` exit would skip it.
      unawaited(
        ServicesBinding.instance.exitApplication(AppExitType.cancelable),
      );
    } catch (error) {
      VeLog.w(_kLogTag, 'Could not ask the platform to exit', error);
    }
  }
}

class _MainWindowDelegate with flutter_window.WindowControllerDelegate {
  _MainWindowDelegate(this._windows);

  final AppWindows _windows;

  /// The window this delegate belongs to, so that a late report from an old
  /// main window is never taken for the current one.
  flutter_window.WindowController? controller;

  // onWindowCloseRequested keeps the default, which destroys the window.

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    final own = controller;
    if (own != null) _windows._mainWindowDestroyed(own);
  }
}

/// Closes the window that [context] is in: the file manager window it belongs
/// to, or the main window. This is what closing a window's last tab does.
void closeWindowOf(BuildContext context) {
  final entry = SecondaryWindowScope.maybeOf(context);
  if (entry != null) {
    entry.close();
  } else {
    AppWindows.instance.closeMainWindow();
  }
}
