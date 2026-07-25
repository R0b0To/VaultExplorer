import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Bold, primary-tinted label introducing a [SectionCard] group.
///
/// This is the "settings section" header style used across App Settings,
/// About, File Manager Settings, and the unlock / create-container flows —
/// distinct from [SectionLabel]'s small uppercase style, which is used for
/// form-field groupings instead.
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(
        title,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: cs.primary,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

/// Groups related rows (switches, list tiles, option pickers) into a single
/// `surfaceContainerHigh` card whose corners pinch together between rows and
/// round out fully at the top/bottom edge.
///
/// This is the shared "settings section" look — previously duplicated
/// verbatim as a private `_buildSectionGroup` in several screens. Pair with
/// [SectionHeader] above it.
class SectionCard extends StatelessWidget {
  final List<Widget> children;
  const SectionCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final cs = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(children.length, (index) {
        final isFirst = index == 0;
        final isLast = index == children.length - 1;
        final isOnly = children.length == 1;

        BorderRadius radius;
        if (isOnly) {
          radius = BorderRadius.circular(AppRadius.lg);
        } else if (isFirst) {
          radius = const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
            bottom: Radius.circular(4),
          );
        } else if (isLast) {
          radius = const BorderRadius.vertical(
            top: Radius.circular(4),
            bottom: Radius.circular(AppRadius.lg),
          );
        } else {
          radius = BorderRadius.circular(4);
        }

        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 2.0),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: ListTileTheme(
              tileColor: Colors.transparent,
              child: children[index],
            ),
          ),
        );
      }),
    );
  }
}
