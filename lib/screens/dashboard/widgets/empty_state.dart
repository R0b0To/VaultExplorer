import 'package:flutter/material.dart';
import '/widgets/common_widgets.dart';

class EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const EmptyState({Key? key, required this.onAdd}) : super(key: key);

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