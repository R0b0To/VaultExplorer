import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Obscure/reveal toggle icon for password fields.
class PasswordVisibilityToggle extends StatelessWidget {
  final bool obscured;
  final VoidCallback onToggle;
  const PasswordVisibilityToggle({
    super.key,
    required this.obscured,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: AppIconSize.small,
      ),
      onPressed: onToggle,
    );
  }
}
