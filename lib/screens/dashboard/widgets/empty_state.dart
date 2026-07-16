import 'package:flutter/material.dart';
import '/widgets/common_widgets.dart';

/// Dashboard's "no containers yet" state. Kept as its own named widget
/// (rather than inlining [AppEmptyState] at the call site) so the copy and
/// call-to-action stay easy to find, while the actual illustration/animation
/// behavior is shared with every other empty state in the app.
class EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const EmptyState({super.key, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.lock_outline_rounded,
      title: 'No containers yet',
      message: 'Mount a VeraCrypt container, connect a USB drive, or create '
          'a brand-new encrypted vault to get started.',
    );
  }
}