import 'package:flutter/material.dart';

/// Shared floating-pill shell used by every transient "activity" surface
/// (clipboard pending, file operation progress).
class FloatingPill extends StatelessWidget {
  final Widget child;
  final Color color;
  final VoidCallback? onTap;

  const FloatingPill({
    super.key,
    required this.child,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: color,
      elevation: 6,
      shadowColor: cs.shadow.withValues(alpha: 0.4),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}
