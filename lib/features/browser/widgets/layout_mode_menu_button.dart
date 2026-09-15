import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

/// App-bar popup button for choosing the current file-list layout mode
/// (list/detailed/compact/grid/masonry) and grid aspect ratios.
class LayoutModeMenuButton extends StatefulWidget {
  final BrowserLayoutMode layoutMode;
  final ValueChanged<BrowserLayoutMode> onLayoutModeChanged;
  final GridAspectRatio gridAspectRatio;
  final ValueChanged<GridAspectRatio>? onGridAspectRatioChanged;

  const LayoutModeMenuButton({
    super.key,
    required this.layoutMode,
    required this.onLayoutModeChanged,
    this.gridAspectRatio = GridAspectRatio.square,
    this.onGridAspectRatioChanged,
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
      BrowserLayoutMode.detailed => Icons.view_agenda_rounded,
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
        MenuItemButton(
          leadingIcon: Icon(
            Icons.view_list_rounded,
            color: widget.layoutMode == BrowserLayoutMode.list ? cs.primary : cs.onSurfaceVariant,
          ),
          trailingIcon: widget.layoutMode == BrowserLayoutMode.list
              ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
              : null,
          onPressed: () => widget.onLayoutModeChanged(BrowserLayoutMode.list),
          child: Text(
            context.l10n.layoutModeColumnedList,
            style: TextStyle(
              fontWeight: widget.layoutMode == BrowserLayoutMode.list ? FontWeight.bold : FontWeight.normal,
              color: widget.layoutMode == BrowserLayoutMode.list ? cs.primary : null,
            ),
          ),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            Icons.view_agenda_rounded,
            color: widget.layoutMode == BrowserLayoutMode.detailed ? cs.primary : cs.onSurfaceVariant,
          ),
          trailingIcon: widget.layoutMode == BrowserLayoutMode.detailed
              ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
              : null,
          onPressed: () => widget.onLayoutModeChanged(BrowserLayoutMode.detailed),
          child: Text(
            context.l10n.layoutModeDetailedList,
            style: TextStyle(
              fontWeight: widget.layoutMode == BrowserLayoutMode.detailed ? FontWeight.bold : FontWeight.normal,
              color: widget.layoutMode == BrowserLayoutMode.detailed ? cs.primary : null,
            ),
          ),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            Icons.list_rounded,
            color: widget.layoutMode == BrowserLayoutMode.compact ? cs.primary : cs.onSurfaceVariant,
          ),
          trailingIcon: widget.layoutMode == BrowserLayoutMode.compact
              ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
              : null,
          onPressed: () => widget.onLayoutModeChanged(BrowserLayoutMode.compact),
          child: Text(
            context.l10n.layoutModeCompactList,
            style: TextStyle(
              fontWeight: widget.layoutMode == BrowserLayoutMode.compact ? FontWeight.bold : FontWeight.normal,
              color: widget.layoutMode == BrowserLayoutMode.compact ? cs.primary : null,
            ),
          ),
        ),
        SubmenuButton(
          leadingIcon: Icon(
            Icons.grid_view_rounded,
            color: widget.layoutMode == BrowserLayoutMode.grid ? cs.primary : cs.onSurfaceVariant,
          ),
          trailingIcon: widget.layoutMode == BrowserLayoutMode.grid
              ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
              : null,
          menuChildren: [
            for (final ratio in GridAspectRatio.values)
              MenuItemButton(
                leadingIcon: Icon(
                  ratio.icon,
                  color: (widget.layoutMode == BrowserLayoutMode.grid && widget.gridAspectRatio == ratio)
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                trailingIcon: (widget.layoutMode == BrowserLayoutMode.grid && widget.gridAspectRatio == ratio)
                    ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
                    : null,
                onPressed: () {
                  widget.onLayoutModeChanged(BrowserLayoutMode.grid);
                  widget.onGridAspectRatioChanged?.call(ratio);
                },
                child: Text(
                  ratio.getLocalizedLabel(context.l10n),
                  style: TextStyle(
                    fontWeight: (widget.layoutMode == BrowserLayoutMode.grid && widget.gridAspectRatio == ratio)
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: (widget.layoutMode == BrowserLayoutMode.grid && widget.gridAspectRatio == ratio)
                        ? cs.primary
                        : null,
                  ),
                ),
              ),
          ],
          child: Text(
            context.l10n.layoutModeGalleryGrid,
            style: TextStyle(
              fontWeight: widget.layoutMode == BrowserLayoutMode.grid ? FontWeight.bold : FontWeight.normal,
              color: widget.layoutMode == BrowserLayoutMode.grid ? cs.primary : null,
            ),
          ),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            Icons.dashboard_rounded,
            color: widget.layoutMode == BrowserLayoutMode.masonry ? cs.primary : cs.onSurfaceVariant,
          ),
          trailingIcon: widget.layoutMode == BrowserLayoutMode.masonry
              ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
              : null,
          onPressed: () => widget.onLayoutModeChanged(BrowserLayoutMode.masonry),
          child: Text(
            context.l10n.layoutModeMasonry,
            style: TextStyle(
              fontWeight: widget.layoutMode == BrowserLayoutMode.masonry ? FontWeight.bold : FontWeight.normal,
              color: widget.layoutMode == BrowserLayoutMode.masonry ? cs.primary : null,
            ),
          ),
        ),
      ],
    );
  }
}