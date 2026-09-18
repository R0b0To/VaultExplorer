import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

/// The sort field options, shared between [SortMenuButton]'s own MenuAnchor
/// and any other cascade (e.g. the FAB toolbar's "More" menu) that wants to
/// embed the same choices as a [SubmenuButton]'s `menuChildren`.
List<Widget> buildSortMenuItems({
  required BuildContext context,
  required ColorScheme cs,
  required SortBy sortBy,
  required bool sortAscending,
  required ValueChanged<SortBy> onSortChanged,
}) {
  final l10n = context.l10n;
  return [
    for (final (field, label, icon) in [
      (SortBy.name, l10n.sortFieldName, Icons.sort_by_alpha_rounded),
      (SortBy.size, l10n.sortFieldSize, Icons.data_usage_rounded),
      (SortBy.extension, l10n.sortFieldType, Icons.category_outlined),
      (SortBy.date, l10n.sortFieldDate, Icons.schedule_rounded),
    ])
      MenuItemButton(
        leadingIcon: Icon(icon, color: sortBy == field ? cs.primary : cs.onSurfaceVariant),
        trailingIcon: sortBy == field
            ? Icon(
                sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 16,
                color: cs.primary,
              )
            : null,
        onPressed: () => onSortChanged(field),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: sortBy == field ? FontWeight.bold : FontWeight.normal,
            color: sortBy == field ? cs.primary : null,
          ),
        ),
      ),
  ];
}

/// App-bar popup button for choosing the current sort field/direction.
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
        tooltip: context.l10n.sortOptionsTooltip,
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
      menuChildren: buildSortMenuItems(
        context: context,
        cs: cs,
        sortBy: widget.sortBy,
        sortAscending: widget.sortAscending,
        onSortChanged: widget.onSortChanged,
      ),
    );
  }
}