import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Pure layout component for the file browser's customizable action row.
///
/// Renders in [axis] direction — [Axis.horizontal] for the portrait bottom
/// bar, [Axis.vertical] for the landscape sidebar rail — showing whichever
/// [actions] are currently visible (already filtered/ordered by the caller
/// via [FileManagerToolbarConfig.visible]).
///
/// This widget owns none of the actions' actual behaviour: each entry is
/// supplied as a ready-to-render widget via [builders], so the screen that
/// composes this bar keeps full control over what tapping "Add" or "Sort"
/// does (reusing its existing menu/sheet logic) while this widget only
/// decides layout, spacing, and background chrome. That split is what
/// makes the bar reusable for both the bottom bar and the sidebar rail
/// without duplicating any behaviour.
class FileManagerActionBar extends StatelessWidget {
  final Axis axis;
  final List<FileManagerAction> actions;
  final Map<FileManagerAction, WidgetBuilder> builders;

  const FileManagerActionBar({
    super.key,
    required this.axis,
    required this.actions,
    required this.builders,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final children = actions
        .map((a) => builders[a]?.call(context) ?? const SizedBox.shrink())
        .toList(growable: false);

    if (children.isEmpty) return const SizedBox.shrink();

    if (axis == Axis.horizontal) {
      return Material(
        color: cs.surfaceContainer,
        elevation: 3,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: children,
            ),
          ),
        ),
      );
    }

    return Material(
      color: cs.surfaceContainerLow,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final child in children) ...[
                child,
                const SizedBox(height: AppSpacing.xs),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
