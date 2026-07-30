import 'package:flutter/material.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

/// App-bar popup button for choosing the current sort field/direction.
///
/// Extracted verbatim from `FileBrowserScreen`'s private
/// `_buildSortPopupButton` as the first slice of the `file_browser_screen.dart`
/// decomposition (docs/tech-debt.md TD-8) -- no behavior change, only a
/// location change. [sortBy]/[sortAscending] are read-only inputs;
/// [onSortChanged] is invoked with the tapped field, exactly as the parent's
/// `_onSortChanged` was invoked directly before.
///
/// Not to be confused with [SortOptionsSheet] (`sort_options_sheet.dart`),
/// an already-built but entirely unused widget covering the same four sort
/// fields via a *different* UI (a bottom-sheet list of rows, not an app-bar
/// menu) -- see docs/tech-debt.md TD-13. That widget wasn't reused here
/// because switching this button's UI from a popup menu to a bottom sheet
/// would be a user-visible UX change, not a pure decomposition.
class SortMenuButton extends StatefulWidget {
  final SortBy sortBy;
  final bool sortAscending;
  final ValueChanged<SortBy> onSortChanged;

  const SortMenuButton({
    super.key,
    required this.sortBy,
    required this.sortAscending,
    required this.onSortChanged,
  });

  @override
  State<SortMenuButton> createState() => _SortMenuButtonState();
}

class _SortMenuButtonState extends State<SortMenuButton> {
  // Was `_menuIsOpen` on the parent's State, shared (and never actually
  // read) across three different popup buttons. Kept local here since nothing
  // outside this widget ever read it -- confirmed by searching every usage
  // in file_browser_screen.dart before this extraction.
  bool _menuIsOpen = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: const Icon(Icons.sort_by_alpha_rounded),
        tooltip: 'Sort options',
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
        for (final (field, label, icon) in const [
          (SortBy.name, 'Name', Icons.sort_by_alpha_rounded),
          (SortBy.size, 'Size', Icons.data_usage_rounded),
          (SortBy.extension, 'Type', Icons.category_outlined),
          (SortBy.date, 'Date', Icons.schedule_rounded),
        ])
          MenuItemButton(
            leadingIcon: Icon(icon, color: widget.sortBy == field ? cs.primary : cs.onSurfaceVariant),
            trailingIcon: widget.sortBy == field
                ? Icon(
                    widget.sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 16,
                    color: cs.primary,
                  )
                : null,
            onPressed: () => widget.onSortChanged(field),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: widget.sortBy == field ? FontWeight.bold : FontWeight.normal,
                color: widget.sortBy == field ? cs.primary : null,
              ),
            ),
          ),
      ],
    );
  }
}
