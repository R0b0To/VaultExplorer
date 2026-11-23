import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/app/app_navigator_key.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';

/// The two extra buttons on most desktop mice.
enum MouseNavButton { back, forward }

/// Gives the mouse's back and forward buttons to whichever screen wants them.
///
/// One global pointer route watches every press, in every window. Screens that
/// have history of their own (the file browser) [register] a handler; the
/// newest one *of the window the press happened in* that returns `true` wins,
/// so only the focused pane of that window reacts. A back press nobody takes
/// closes the topmost page, dialog or sheet of that window's navigator, the way
/// the button works in most desktop programs. Forward does nothing unless a
/// handler takes it.
class MouseNavDispatcher {
  MouseNavDispatcher._();

  static final MouseNavDispatcher instance = MouseNavDispatcher._();

  final List<_Registration> _handlers = [];
  final Map<int, GlobalKey<NavigatorState>> _viewNavigators = {};
  bool _installed = false;

  /// Starts listening. Does nothing off desktop, and a second call is a no-op.
  void install() {
    if (_installed || !PlatformFeatures.isDesktop) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  void uninstall() {
    if (!_installed) return;
    _installed = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }

  /// [handler] returns whether it used the press.
  ///
  /// [viewId] says which window the handler belongs to (asked at the time of a
  /// press, since a widget can only find out once it is built). Without it, or
  /// when it returns null, the handler hears presses from every window.
  void register(
    bool Function(MouseNavButton button) handler, {
    int? Function()? viewId,
  }) => _handlers.add(_Registration(handler, viewId));

  void unregister(bool Function(MouseNavButton button) handler) =>
      _handlers.removeWhere((entry) => entry.handler == handler);

  /// Tells the dispatcher which navigator an unclaimed back press closes
  /// things in for the secondary window [viewId]. The main window's is
  /// [appNavigatorKey].
  void registerViewNavigator(int viewId, GlobalKey<NavigatorState> key) =>
      _viewNavigators[viewId] = key;

  void unregisterViewNavigator(int viewId) => _viewNavigators.remove(viewId);

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent || event.kind != PointerDeviceKind.mouse) {
      return;
    }
    final MouseNavButton button;
    if (event.buttons & kBackMouseButton != 0) {
      button = MouseNavButton.back;
    } else if (event.buttons & kForwardMouseButton != 0) {
      button = MouseNavButton.forward;
    } else {
      return;
    }
    dispatch(button, viewId: event.viewId);
  }

  /// Runs the handlers, newest first. Public for tests. [viewId] is the window
  /// the press happened in; null means "any window" (the original behaviour).
  bool dispatch(MouseNavButton button, {int? viewId}) {
    for (final entry in _handlers.reversed.toList()) {
      final owner = entry.viewId?.call();
      if (owner != null && viewId != null && owner != viewId) continue;
      if (entry.handler(button)) return true;
    }
    if (button == MouseNavButton.back) {
      final navigator = _navigatorFor(viewId)?.currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.maybePop();
        return true;
      }
    }
    return false;
  }

  GlobalKey<NavigatorState>? _navigatorFor(int? viewId) {
    if (viewId == null) return appNavigatorKey;
    if (viewId == PlatformDispatcher.instance.implicitView?.viewId) {
      return appNavigatorKey;
    }
    return _viewNavigators[viewId];
  }
}

class _Registration {
  const _Registration(this.handler, this.viewId);

  final bool Function(MouseNavButton button) handler;
  final int? Function()? viewId;
}
