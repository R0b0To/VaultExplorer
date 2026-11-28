import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/menus/back_dismissible_menu_anchor.dart';

/// Opens a cascading context menu where the user right-clicks (secondary
/// button, or a mouse's right button on a tablet/phone) on the empty part of a
/// folder listing, the way a desktop file manager offers "New", "Paste",
/// "View", "Sort by" and "Refresh" there.
///
/// It wraps the whole listing with a translucent [GestureDetector]. A tile's
/// own right-click (its item menu) sits deeper in the widget tree, so it wins
/// the gesture arena and this menu only appears for clicks that no item
/// claimed: the gaps of a grid, the space under the last row, or an empty
/// folder.
///
/// [menuBuilder] runs when the menu is about to open, so it always reflects
/// the current clipboard, selection, layout and sort state.
class FolderBackgroundContextMenu extends StatefulWidget {
  const FolderBackgroundContextMenu({
    super.key,
    required this.child,
    required this.menuBuilder,
    this.enabled = true,
  });

  final Widget child;

  /// Builds the menu entries for the click. Return an empty list to show
  /// nothing.
  final List<Widget> Function(BuildContext context) menuBuilder;

  final bool enabled;

  @override
  State<FolderBackgroundContextMenu> createState() =>
      _FolderBackgroundContextMenuState();
}

class _FolderBackgroundContextMenuState
    extends State<FolderBackgroundContextMenu> {
  final MenuController _controller = MenuController();
  List<Widget> _entries = const <Widget>[];

  /// Where the last click landed, in this widget's own coordinates. The
  /// menu's zero-size anchor sits exactly here.
  Offset _clickAt = Offset.zero;

  void _onSecondaryTapUp(TapUpDetails details) {
    if (!widget.enabled) return;
    final entries = widget.menuBuilder(context);
    if (entries.isEmpty) return;
    if (_controller.isOpen) _controller.close();
    setState(() {
      _entries = entries;
      _clickAt = details.localPosition;
    });
    // Rebuild MenuAnchor with the latest children (and the anchor at the new
    // click) before opening its overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.enabled) return;
      _controller.open();
    });
  }

  @override
  Widget build(BuildContext context) {
    // The anchor must NOT be the listing itself. A MenuAnchor counts a tap on
    // its own anchor as a tap "inside" the menu, so with the whole listing as
    // the anchor a click anywhere on it never dismissed the menu (only Esc or
    // choosing an entry did). The listing is therefore a sibling, and the
    // menu hangs off a zero-size anchor placed at the click; every click on
    // the listing is then an outside click that closes the menu.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapUp: widget.enabled ? _onSecondaryTapUp : null,
          child: widget.child,
        ),
        Positioned(
          left: _clickAt.dx,
          top: _clickAt.dy,
          width: 0,
          height: 0,
          child: BackDismissibleMenuAnchor(
            controller: _controller,
            menuChildren: _entries,
          ),
        ),
      ],
    );
  }
}
