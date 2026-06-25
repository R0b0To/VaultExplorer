import 'package:flutter/material.dart';
import '../../../utils/file_type_utils.dart';

class FileTile extends StatelessWidget {
  final String name;
  final String? subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  final bool selectionMode;
  final bool selected;

  const FileTile({
    super.key,
    required this.name,
    this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: 'File: $name${subtitle != null ? ", $subtitle" : ""}',
      button: true,
      selected: selected,
      child: ListTile(
        dense: true,
        selected: selected,
        // Match selection background style with DirectoryTile
        selectedTileColor: cs.primaryContainer.withOpacity(0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          iconForFile(name),
          size: 22,
          color: selected ? cs.primary : colorForFile(name),
          semanticLabel: null, // covered by parent Semantics
        ),
        title: Text(
          name,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              )
            : null,
        // Displays the standard selection indicator when selectionMode is active, otherwise null
        trailing: selectionMode
            ? Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? cs.primary : cs.outline,
              )
            : null,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}