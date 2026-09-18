import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

/// The layout-mode options, shared between [LayoutModeMenuButton]'s own
/// MenuAnchor and any other cascade (e.g. the FAB toolbar's "More" menu)
/// that wants to embed the same choices as a [SubmenuButton]'s
/// `menuChildren`.
List<Widget> buildLayoutModeMenuItems({
  required BuildContext context,
  required ColorScheme cs,
  required BrowserLayoutMode layoutMode,
  required ValueChanged<BrowserLayoutMode> onLayoutModeChanged,
  required GridAspectRatio gridAspectRatio,
  ValueChanged<GridAspectRatio>? onGridAspectRatioChanged,
}) {
  final l10n = context.l10n;
  Widget modeItem(BrowserLayoutMode mode, IconData icon, String label) {
    final isActive = layoutMode == mode;
    return MenuItemButton(
      leadingIcon: Icon(icon, color: isActive ? cs.primary : cs.onSurfaceVariant),
      trailingIcon: isActive ? Icon(Icons.check_rounded, size: 16, color: cs.primary) : null,
      onPressed: () => onLayoutModeChanged(mode),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive ? cs.primary : null,
        ),
      ),
    );
  }

  return [
    modeItem(BrowserLayoutMode.list, Icons.view_list_rounded, l10n.layoutModeColumnedList),
    modeItem(BrowserLayoutMode.detailed, Icons.view_agenda_rounded, l10n.layoutModeDetailedList),
    modeItem(BrowserLayoutMode.compact, Icons.list_rounded, l10n.layoutModeCompactList),
    SubmenuButton(
      leadingIcon: Icon(
        Icons.grid_view_rounded,
        color: layoutMode == BrowserLayoutMode.grid ? cs.primary : cs.onSurfaceVariant,
      ),
      trailingIcon: layoutMode == BrowserLayoutMode.grid
          ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
          : null,
      menuChildren: [
        for (final ratio in GridAspectRatio.values)
          MenuItemButton(
            leadingIcon: Icon(
              ratio.icon,
              color: (layoutMode == BrowserLayoutMode.grid && gridAspectRatio == ratio)
                  ? cs.primary
                  : cs.onSurfaceVariant,
            ),
            trailingIcon: (layoutMode == BrowserLayoutMode.grid && gridAspectRatio == ratio)
                ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
                : null,
            onPressed: () {
              onLayoutModeChanged(BrowserLayoutMode.grid);
              onGridAspectRatioChanged?.call(ratio);
            },
            child: Text(
              ratio.getLocalizedLabel(l10n),
              style: TextStyle(
                fontWeight: (layoutMode == BrowserLayoutMode.grid && gridAspectRatio == ratio)
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: (layoutMode == BrowserLayoutMode.grid && gridAspectRatio == ratio)
                    ? cs.primary
                    : null,
              ),
            ),
          ),
      ],
      child: Text(
        l10n.layoutModeGalleryGrid,
        style: TextStyle(
          fontWeight: layoutMode == BrowserLayoutMode.grid ? FontWeight.bold : FontWeight.normal,
          color: layoutMode == BrowserLayoutMode.grid ? cs.primary : null,
        ),
      ),
    ),
    modeItem(BrowserLayoutMode.masonry, Icons.dashboard_rounded, l10n.layoutModeMasonry),
  ];
}

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
      menuChildren: buildLayoutModeMenuItems(
        context: context,
        cs: cs,
        layoutMode: widget.layoutMode,
        onLayoutModeChanged: widget.onLayoutModeChanged,
        gridAspectRatio: widget.gridAspectRatio,
        onGridAspectRatioChanged: widget.onGridAspectRatioChanged,
      ),
    );
  }
}