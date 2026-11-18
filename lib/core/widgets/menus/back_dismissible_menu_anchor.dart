import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Tracks whether any [BackDismissibleMenuAnchor] is currently open.
///
/// A [MenuAnchor] is an overlay, not a route, so the system back button never
/// reaches it: back used to act on whatever sat underneath (go up a folder,
/// arm the exit, close the viewer) while the menu stayed on screen. Every
/// back handler that can coexist with a toolbar menu checks [hasOpenMenu] and
/// stands down, leaving that press to the menu, which closes itself.
class OpenMenuBackGuard {
  OpenMenuBackGuard._();

  static int _openCount = 0;

  /// True while at least one menu is open, including during the very back
  /// press that is about to close it (the menu closes after every back
  /// handler has run, so handlers all see the same value).
  static bool get hasOpenMenu => _openCount > 0;
}

/// Drop-in replacement for [MenuAnchor] for the app's toolbar and context
/// menus. Compared to a bare [MenuAnchor] it:
///
///  * closes on the system back button / gesture instead of letting back act
///    on the screen underneath, and
///  * consumes the tap that lands outside the menu, so tapping a folder, file
///    or button while a menu is open only dismisses the menu instead of also
///    activating whatever was tapped.
class BackDismissibleMenuAnchor extends StatefulWidget {
  const BackDismissibleMenuAnchor({
    super.key,
    required this.menuChildren,
    this.builder,
    this.controller,
    this.alignmentOffset,
    this.onOpen,
    this.onClose,
    this.consumeOutsideTap = true,
  });

  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder? builder;
  final MenuController? controller;
  final Offset? alignmentOffset;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final bool consumeOutsideTap;

  @override
  State<BackDismissibleMenuAnchor> createState() =>
      _BackDismissibleMenuAnchorState();
}

class _BackDismissibleMenuAnchorState
    extends State<BackDismissibleMenuAnchor> {
  MenuController? _ownController;
  bool _open = false;

  MenuController get _controller =>
      widget.controller ?? (_ownController ??= MenuController());

  void _setOpen(bool value) {
    if (_open == value) return;
    _open = value;
    OpenMenuBackGuard._openCount += value ? 1 : -1;
    if (mounted) setState(() {});
  }

  void _handleOpen() {
    _setOpen(true);
    widget.onOpen?.call();
  }

  void _handleClose() {
    _setOpen(false);
    widget.onClose?.call();
  }

  @override
  void dispose() {
    // MenuAnchor does not always report a close while it is being torn down.
    if (_open) {
      _open = false;
      OpenMenuBackGuard._openCount -= 1;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Blocks the route from popping while the menu is up; back closes the
      // menu instead.
      canPop: !_open,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || !_open) return;
        // Every PopScope on the route is notified synchronously for the same
        // back press. Closing on a microtask lets the others see the menu as
        // still open (see OpenMenuBackGuard) and leave this press alone.
        scheduleMicrotask(() {
          if (_open) _controller.close();
        });
      },
      child: MenuAnchor(
        controller: _controller,
        alignmentOffset: widget.alignmentOffset ?? Offset.zero,
        consumeOutsideTap: widget.consumeOutsideTap,
        onOpen: _handleOpen,
        onClose: _handleClose,
        menuChildren: widget.menuChildren,
        builder: widget.builder,
      ),
    );
  }
}
