import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/app/app_navigator_key.dart';
import 'package:vaultexplorer/app/secondary_window_app.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/core/utils/mouse_nav_buttons.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_frame.dart';
import 'package:vaultexplorer/core/windowing/app_windows.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:ve_desktop_transfer/ve_desktop_transfer.dart';
import 'package:vaultexplorer/core/windowing/window_caption.dart';

/// The root of the app on Linux and Windows (`runWidget`, not `runApp`).
///
/// Nothing is drawn in the platform's own window. Every window of the app is a
/// view in this widget's `ViewCollection`: the main window ([VaultExplorerApp])
/// and the secondary windows (`SecondaryWindows`) side by side, so none is the
/// anchor of the others. Closing any window leaves the rest open, and the app
/// ends when the last one is gone (see `DesktopWindowPolicy`).
///
/// Everything below this widget is above the windows, so it must not need a
/// `View`: it sits below the `ProviderScope` and builds nothing but the views.
class DesktopAppHost extends StatefulWidget {
  const DesktopAppHost({super.key});

  @override
  State<DesktopAppHost> createState() => _DesktopAppHostState();
}

class _DesktopAppHostState extends State<DesktopAppHost> {
  final AppWindows _windows = AppWindows.instance;
  final SecondaryWindows _secondary = SecondaryWindows.instance;

  @override
  void initState() {
    super.initState();
    _windows.addListener(_onWindowsChanged);
    _secondary.addListener(_onWindowsChanged);
    // The mouse's back and forward buttons serve every window, so this is
    // installed once for the life of the app and not by any one window.
    MouseNavDispatcher.instance.install();
    _windows.openStartupWindow();
  }

  @override
  void dispose() {
    _windows.removeListener(_onWindowsChanged);
    _secondary.removeListener(_onWindowsChanged);
    super.dispose();
  }

  void _onWindowsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ViewCollection(
      views: _windows.buildViews(
        mainBuilder: (context) => const MainWindowChrome(
          child: VaultExplorerApp(ownsMouseNavigation: false),
        ),
        secondaryBuilder: (context, entry) => SecondaryWindowApp(entry: entry),
      ),
    );
  }
}

/// What a window other than the platform's own needs around the main app, the
/// same things `SecondaryWindowApp` does for its own `MaterialApp`:
///
/// * the mouse's back button acts on this window's navigator, and
/// * the title bar is the Flutter caption row on Windows (the runner hides the
///   OS caption), or the native one elsewhere, marked [NativeWindowChrome].
///
/// It sits outside the app's `MaterialApp`, so it can hold the window's view id
/// and the app's navigator key before the first route exists.
///
/// When the main page is drawn in the runner's own window instead (the platform
/// refused to open a window for it), that window already has everything and
/// this does nothing.
class MainWindowChrome extends StatefulWidget {
  const MainWindowChrome({super.key, required this.child});

  final Widget child;

  @override
  State<MainWindowChrome> createState() => _MainWindowChromeState();
}

class _MainWindowChromeState extends State<MainWindowChrome> {
  int? _viewId;

  // Whether this window keeps its OS title bar. Windows tries to replace it
  // with the Flutter caption row first and falls back to the native one when
  // the runner cannot.
  bool _nativeCaption = !PlatformFeatures.isWindows;

  bool get _inRunnerWindow =>
      _viewId != null &&
      _viewId == PlatformDispatcher.instance.implicitView?.viewId;

  Future<void> _replaceNativeCaption(int viewId) async {
    if (!PlatformFeatures.isWindows) return;
    try {
      await useCustomWindowCaption(viewId);
    } catch (error) {
      VeLog.w(
        'MainWindowChrome',
        'Could not replace the window caption; keeping the native one',
        error,
      );
      if (mounted) setState(() => _nativeCaption = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewId = View.maybeOf(context)?.viewId;
    if (viewId == _viewId) return;
    final previous = _viewId;
    if (previous != null) {
      if (!(_inRunnerWindow)) {
        MouseNavDispatcher.instance.unregisterViewNavigator(previous);
      }
      unawaited(VeDesktopTransfer.instance.releaseView(previous));
    }
    _viewId = viewId;
    if (viewId != null) {
      unawaited(VeDesktopTransfer.instance.retainView(viewId));
      if (!_inRunnerWindow) {
        // The dispatcher assumes the app's navigator for the platform's own
        // window only; any other window has to say which one is its own.
        MouseNavDispatcher.instance.registerViewNavigator(
          viewId,
          appNavigatorKey,
        );
        unawaited(_replaceNativeCaption(viewId));
      }
    }
  }

  @override
  void dispose() {
    final viewId = _viewId;
    if (viewId != null) {
      if (!_inRunnerWindow) {
        MouseNavDispatcher.instance.unregisterViewNavigator(viewId);
      }
      unawaited(VeDesktopTransfer.instance.releaseView(viewId));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_inRunnerWindow || !_nativeCaption) return widget.child;
    return NativeWindowChrome(child: widget.child);
  }
}
