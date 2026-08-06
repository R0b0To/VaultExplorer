import 'package:flutter/material.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

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
      menuChildren: [
        for (final (field, label, icon) in [
          (SortBy.name, context.l10n.sortFieldName, Icons.sort_by_alpha_rounded),
          (SortBy.size, context.l10n.sortFieldSize, Icons.data_usage_rounded),
          (SortBy.extension, context.l10n.sortFieldType, Icons.category_outlined),
          (SortBy.date, context.l10n.sortFieldDate, Icons.schedule_rounded),
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
