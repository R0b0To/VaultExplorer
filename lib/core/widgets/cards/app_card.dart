import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// A grouped surface for related content, optionally rendered as
/// divider-separated full-bleed rows via [AppCard.rows].
class AppCard extends StatelessWidget {
  final List<Widget> children;
  final bool dividers;
  final EdgeInsetsGeometry padding;

  final double dividerIndent;

  const AppCard({
    super.key,
    required this.children,
    this.dividers = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.dividerIndent = 68,
  });

  /// A card whose children are full-bleed rows (e.g. tappable list tiles)
  /// separated by inset dividers, matching about_screen's `_AboutGroup`.
  const AppCard.rows({
    super.key,
    required this.children,
    this.dividerIndent = 68,
  })  : dividers = true,
        padding = EdgeInsets.zero;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Card(
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: dividers
          ? Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Divider(height: 1, indent: dividerIndent, endIndent: 16),
                ],
              ],
            )
          : Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
    );
  }
}
