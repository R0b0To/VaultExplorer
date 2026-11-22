import 'package:flutter/gestures.dart';
import 'package:vaultexplorer/app/app_navigator_key.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';

/// The two extra buttons on most desktop mice.
enum MouseNavButton { back, forward }

/// Gives the mouse's back and forward buttons to whichever screen wants them.
///
/// One global pointer route watches every press. Screens that have history of
/// their own (the file browser) [register] a handler; the newest one that
/// returns `true` wins, so only the focused pane reacts. A back press nobody
/// takes closes the topmost page, dialog or sheet of the app's navigator, the
/// way the button works in most desktop programs. Forward does nothing unless
/// a handler takes it.
class MouseNavDispatcher {
  MouseNavDispatcher._();

  static final MouseNavDispatcher instance = MouseNavDispatcher._();

  final List<bool Function(MouseNavButton button)> _handlers = [];
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
  void register(bool Function(MouseNavButton button) handler) =>
      _handlers.add(handler);

  void unregister(bool Function(MouseNavButton button) handler) =>
      _handlers.remove(handler);

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
    dispatch(button);
  }

  /// Runs the handlers, newest first. Public for tests.
  bool dispatch(MouseNavButton button) {
    for (final handler in _handlers.reversed.toList()) {
      if (handler(button)) return true;
    }
    if (button == MouseNavButton.back) {
      final navigator = appNavigatorKey.currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.maybePop();
        return true;
      }
    }
    return false;
  }
}
