import 'package:material_ui/material_ui.dart';

/// A very subtle panel that groups related rows of the side menu (vaults,
/// storage locations, category shortcuts): a faint tint on the menu's own
/// background with softly rounded corners, no border and no divider lines.
///
/// It is a [Material], so the rows inside keep their ink effects.
class DrawerGroup extends StatelessWidget {
  const DrawerGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
