import 'package:flutter/material.dart';
import '../mixins/sort_mixin.dart';
import '../../../theme.dart';

class SortOptionsSheet extends StatelessWidget {
  final SortBy sortBy;
  final bool ascending;
  final ValueChanged<SortBy> onSelect;

  const SortOptionsSheet({
    super.key,
    required this.sortBy,
    required this.ascending,
    required this.onSelect,
  });

  static Future<void> show(
    BuildContext context, {
    required SortBy sortBy,
    required bool ascending,
    required ValueChanged<SortBy> onSelect,
  }) {
    return _showPopupMenu(context, sortBy: sortBy, ascending: ascending, onSelect: onSelect);
  }

  static Future<void> _showPopupMenu(
    BuildContext context, {
    required SortBy sortBy,
    required bool ascending,
    required ValueChanged<SortBy> onSelect,
  }) async {
    final RenderBox? button = context.findRenderObject() as RenderBox?;
    final RenderBox? overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;

    final RelativeRect position;
    if (button != null && overlay != null) {
      final buttonOffset = button.localToGlobal(Offset.zero, ancestor: overlay);
      final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
      final left = buttonOffset.dx;
      final right = overlay.size.width - (buttonOffset.dx + button.size.width);

      if (isLandscape) {
        position = RelativeRect.fromLTRB(
          left,
          buttonOffset.dy + button.size.height + 8,
          right,
          0,
        );
      } else {
        position = RelativeRect.fromLTRB(
          left,
          10,
          right,
          overlay.size.height - buttonOffset.dy + 8,
        );
      }
    } else {
      final size = MediaQuery.of(context).size;
      position = RelativeRect.fromLTRB(size.width - 100, kToolbarHeight, 110, 0);
    }

    final value = await showMenu<SortBy>(
      context: context,
      position: position,
      constraints: const BoxConstraints(
        minWidth: 180,
        maxWidth: 240,
      ),
      items: [
        for (final (field, label, icon) in _fields)
          PopupMenuItem<SortBy>(
            value: field,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: sortBy == field ? Theme.of(context).colorScheme.primary : null,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: sortBy == field ? FontWeight.bold : FontWeight.normal,
                    color: sortBy == field ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
                const Spacer(),
                if (sortBy == field)
                  Icon(
                    ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
    );

    if (value != null) {
      onSelect(value);
    }
  }

  static const _fields = [
    (SortBy.name, 'Name', Icons.sort_by_alpha_rounded),
    (SortBy.size, 'Size', Icons.data_usage_rounded),
    (SortBy.extension, 'Type', Icons.category_outlined),
    (SortBy.date, 'Date', Icons.schedule_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (field, label, icon) in _fields)
              _SortRow(
                icon: icon,
                label: label,
                isActive: sortBy == field,
                ascending: ascending,
                onTap: () {
                  onSelect(field);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool ascending;
  final VoidCallback onTap;

  const _SortRow({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.ascending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = isActive ? cs.primary : cs.onSurface;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: AppIconSize.standard, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
            if (isActive)
              Icon(
                ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: AppIconSize.standard,
                color: cs.primary,
              ),
          ],
        ),
      ),
    );
  }
}
