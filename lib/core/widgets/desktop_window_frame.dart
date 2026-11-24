import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_title_bar.dart';

enum _FrameSlot { bar, page }

/// Marks a window that keeps its native title bar (a secondary window on
/// Linux, or on Windows when the runner could not hide the OS caption), as
/// opposed to a Windows window whose caption is drawn by Flutter: the main one
/// and, normally, the secondary ones.
///
/// Inside it [DesktopCaptionFrame] draws nothing: a second row of caption
/// buttons would sit under the native ones.
class NativeWindowChrome extends InheritedWidget {
  const NativeWindowChrome({super.key, required super.child});

  /// Whether [context] sits in a window with a native title bar.
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NativeWindowChrome>() != null;

  @override
  bool updateShouldNotify(NativeWindowChrome oldWidget) => false;
}

/// Gives a pushed page its own caption row (drag area plus minimize, maximize
/// and close) on Windows, where the runner has no native title bar.
///
/// A page that already draws a [DesktopWindowTitleBar] (the shell, a browser
/// tab host) claims the frame, and the frame's own row collapses to nothing.
/// That is decided at layout time, so no frame is ever drawn with both rows.
class DesktopCaptionFrame extends StatefulWidget {
  final Widget child;

  const DesktopCaptionFrame({super.key, required this.child});

  @override
  State<DesktopCaptionFrame> createState() => _DesktopCaptionFrameState();
}

class _DesktopCaptionFrameState extends State<DesktopCaptionFrame> {
  final DesktopCaptionClaims _claims = DesktopCaptionClaims();

  @override
  void dispose() {
    _claims.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (NativeWindowChrome.of(context)) return widget.child;
    return _buildFrame();
  }

  Widget _buildFrame() => CustomMultiChildLayout(
    delegate: _FrameLayoutDelegate(_claims),
    children: [
      LayoutId(
        id: _FrameSlot.bar,
        child: const ClipRect(
          child: DesktopWindowTitleBar(
            height: kDesktopTitleBarHeight,
            tabs: SizedBox.shrink(),
          ),
        ),
      ),
      LayoutId(
        id: _FrameSlot.page,
        child: DesktopCaptionClaimsScope(
          claims: _claims,
          child: widget.child,
        ),
      ),
    ],
  );
}

class _FrameLayoutDelegate extends MultiChildLayoutDelegate {
  final DesktopCaptionClaims claims;

  _FrameLayoutDelegate(this.claims) : super(relayout: claims);

  @override
  void performLayout(Size size) {
    final barHeight = claims.claimed
        ? 0.0
        : kDesktopTitleBarHeight.clamp(0.0, size.height).toDouble();
    layoutChild(
      _FrameSlot.bar,
      BoxConstraints.tightFor(width: size.width, height: barHeight),
    );
    positionChild(_FrameSlot.bar, Offset.zero);
    layoutChild(
      _FrameSlot.page,
      BoxConstraints.tightFor(width: size.width, height: size.height - barHeight),
    );
    positionChild(_FrameSlot.page, Offset(0, barHeight));
  }

  @override
  bool shouldRelayout(_FrameLayoutDelegate oldDelegate) =>
      oldDelegate.claims != claims;
}

/// Wraps every page the wrapped builder transitions in a [DesktopCaptionFrame].
class DesktopCaptionPageTransitionsBuilder extends PageTransitionsBuilder {
  final PageTransitionsBuilder inner;

  const DesktopCaptionPageTransitionsBuilder(this.inner);

  @override
  Duration get transitionDuration => inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Pages pushed on a nested navigator (a settings detail pane, say) sit
    // inside a page that already has its caption row, so only root-navigator
    // routes get a frame.
    final isRootRoute =
        route.navigator == Navigator.maybeOf(context, rootNavigator: true);
    final needsFrame = isRootRoute && !NativeWindowChrome.of(context);
    return inner.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      needsFrame ? DesktopCaptionFrame(child: child) : child,
    );
  }
}

/// Counts the dialogs and bottom sheets that are open on the root navigator.
class DesktopModalTracker extends NavigatorObserver {
  int openCount = 0;

  static bool _isModal(Route<dynamic>? route) =>
      route is RawDialogRoute || route is ModalBottomSheetRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route)) openCount++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route) && openCount > 0) openCount--;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isModal(route) && openCount > 0) openCount--;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_isModal(oldRoute) && openCount > 0) openCount--;
    if (_isModal(newRoute)) openCount++;
  }
}

/// The root navigator's observer; pass it to `MaterialApp.navigatorObservers`.
final DesktopModalTracker desktopModalTracker = DesktopModalTracker();

/// While a dialog or bottom sheet is open its barrier covers the caption row,
/// so the row cannot take the drag. This lets a press that starts in the
/// caption row's strip and then moves still drag the window. It only listens,
/// so nothing under the pointer loses its clicks.
class DesktopModalWindowDrag extends StatefulWidget {
  final Widget child;

  const DesktopModalWindowDrag({super.key, required this.child});

  @override
  State<DesktopModalWindowDrag> createState() => _DesktopModalWindowDragState();
}

class _DesktopModalWindowDragState extends State<DesktopModalWindowDrag> {
  static const _channel = MethodChannel('vaultexplorer/window');
  static const double _slop = 6;

  Offset? _pressStart;

  void _onDown(PointerDownEvent event) {
    final armed =
        desktopModalTracker.openCount > 0 &&
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton &&
        event.position.dy < kDesktopTitleBarHeight;
    _pressStart = armed ? event.position : null;
  }

  void _onMove(PointerMoveEvent event) {
    final start = _pressStart;
    if (start == null || (event.position - start).distance < _slop) return;
    _pressStart = null;
    unawaited(_startDragging());
  }

  Future<void> _startDragging() async {
    try {
      await _channel.invokeMethod<void>('startDragging');
    } on MissingPluginException {
      // Hosts without the Windows runner keep their native title bar.
    } on PlatformException {
      // A transient runner shutdown should not interrupt the UI.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformFeatures.isWindows) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (_) => _pressStart = null,
      onPointerCancel: (_) => _pressStart = null,
      child: widget.child,
    );
  }
}
