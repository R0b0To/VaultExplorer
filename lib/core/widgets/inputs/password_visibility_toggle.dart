import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Obscure/reveal toggle icon for password fields.
///
/// [enabled] defaults to true for every existing call site. Pass false to
/// keep the icon visible but non-interactive (e.g. while the field holds a
/// saved credential that shouldn't be revealable in plain text) — the icon
/// dims via Flutter's normal disabled-IconButton styling.
class PasswordVisibilityToggle extends StatelessWidget {
  final bool obscured;
  final VoidCallback onToggle;
  final bool enabled;
  const PasswordVisibilityToggle({
    super.key,
    required this.obscured,
    required this.onToggle,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: AppIconSize.small,
      ),
      onPressed: enabled ? onToggle : null,
    );
  }
}
