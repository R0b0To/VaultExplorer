import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/menus/back_dismissible_menu_anchor.dart';

IconData sortIconFor(SortBy sortBy) => switch (sortBy) {
  SortBy.name => Icons.sort_by_alpha_rounded,
  SortBy.size => Icons.data_usage_rounded,
  SortBy.extension => Icons.category_outlined,
  SortBy.date => Icons.schedule_rounded,
};

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
    for (final (field, label) in [
      (SortBy.name, l10n.sortFieldName),
      (SortBy.size, l10n.sortFieldSize),
      (SortBy.extension, l10n.sortFieldType),
      (SortBy.date, l10n.sortFieldDate),
    ])
      MenuItemButton(
        leadingIcon: Icon(
          sortIconFor(field),
          color: sortBy == field ? cs.primary : cs.onSurfaceVariant,
        ),
        trailingIcon: sortBy == field
            ? Icon(
                sortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
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
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BackDismissibleMenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: Icon(sortIconFor(widget.sortBy)),
        tooltip: context.l10n.sortOptionsTooltip,
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
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
