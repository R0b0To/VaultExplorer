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

  void _onSecondaryTapUp(TapUpDetails details) {
    if (!widget.enabled) return;
    final entries = widget.menuBuilder(context);
    if (entries.isEmpty) return;
    if (_controller.isOpen) _controller.close();
    setState(() => _entries = entries);
    // `position` is relative to the anchor's top-left corner, and the anchor
    // is exactly this detector's box, so the local position is the click.
    _controller.open(position: details.localPosition);
  }

  @override
  Widget build(BuildContext context) {
    return BackDismissibleMenuAnchor(
      controller: _controller,
      menuChildren: _entries,
      builder: (context, controller, _) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: widget.enabled ? _onSecondaryTapUp : null,
        child: widget.child,
      ),
    );
  }
}
