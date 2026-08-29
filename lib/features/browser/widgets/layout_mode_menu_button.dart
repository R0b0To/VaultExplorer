import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

/// App-bar popup button for choosing the current file-list layout mode
/// (list/compact/grid/masonry).
class LayoutModeMenuButton extends StatefulWidget {
  final BrowserLayoutMode layoutMode;
  final ValueChanged<BrowserLayoutMode> onLayoutModeChanged;

  const LayoutModeMenuButton({
    super.key,
    required this.layoutMode,
    required this.onLayoutModeChanged,
  });

  @override
  State<LayoutModeMenuButton> createState() => _LayoutModeMenuButtonState();
}

class _LayoutModeMenuButtonState extends State<LayoutModeMenuButton> {
  // Was `_menuIsOpen` on the parent's State, shared (and never actually
  // read) across three different popup buttons -- see the identical note
  // in sort_menu_button.dart. Kept local here for the same reason.
  bool _menuIsOpen = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentIcon = switch (widget.layoutMode) {
      BrowserLayoutMode.list => Icons.view_list_rounded,
      BrowserLayoutMode.compact => Icons.list_rounded,
      BrowserLayoutMode.grid => Icons.grid_view_rounded,
      BrowserLayoutMode.masonry => Icons.dashboard_rounded,
    };
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: Icon(currentIcon),
        tooltip: context.l10n.layoutOptionsTooltip,
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      onOpen: () => setState(() => _menuIsOpen = true),
      onClose: () => setState(() => _menuIsOpen = false),
      menuChildren: [
        for (final (mode, label, icon) in [
          (BrowserLayoutMode.list, context.l10n.layoutModeDetailedList, Icons.view_list_rounded),
          (BrowserLayoutMode.compact, context.l10n.layoutModeCompactList, Icons.list_rounded),
          (BrowserLayoutMode.grid, context.l10n.layoutModeGalleryGrid, Icons.grid_view_rounded),
          (BrowserLayoutMode.masonry, context.l10n.layoutModeMasonry, Icons.dashboard_rounded),
        ])
          MenuItemButton(
            leadingIcon: Icon(icon, color: widget.layoutMode == mode ? cs.primary : cs.onSurfaceVariant),
            trailingIcon: widget.layoutMode == mode
                ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
                : null,
            onPressed: () => widget.onLayoutModeChanged(mode),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: widget.layoutMode == mode ? FontWeight.bold : FontWeight.normal,
                color: widget.layoutMode == mode ? cs.primary : null,
              ),
            ),
          ),
      ],
    );
  }
}
