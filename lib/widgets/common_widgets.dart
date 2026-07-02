import 'package:flutter/material.dart';
import '../theme.dart';

/// Uppercased, letter-spaced section header used above grouped settings
/// cards. Previously duplicated as `_SectionLabel` (app_settings_screen.dart,
/// vault_item_edit_screen.dart), `_SectionHeader` (container_config_sheet.dart),
/// and inlined ad hoc twice in vault_item_detail_screen.dart — each with
/// slightly different letterSpacing (1.2 vs 1.4) and padding. This is the
/// single source of truth going forward.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

/// Icon + title/subtitle + trailing Switch row.
/// Previously duplicated verbatim as `_ToggleRow` in both
/// app_settings_screen.dart and container_config_sheet.dart.
class SettingsToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: AppIconSize.standard, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Error-container banner with icon + message.
/// Previously duplicated in create_container_sheet.dart and twice in
/// unlock_sheet.dart with identical padding/radius/icon-size values.
class InlineErrorBanner extends StatelessWidget {
  final String message;
  const InlineErrorBanner(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: AppIconSize.standard,
            color: cs.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard keyboard-safe, gesture-nav-safe bottom sheet wrapper.
/// Previously the same four-line Padding(bottom: viewInsets) →
/// SafeArea(top:false) → Padding(24,8,24,24) boilerplate was hand-copied
/// into create_container_sheet.dart, container_config_sheet.dart,
/// unlock_sheet.dart, and pattern_setup_sheet.dart.
class AppBottomSheet extends StatelessWidget {
  final Widget child;
  const AppBottomSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: AppSpacing.sheetPadding,
          child: child,
        ),
      ),
    );
  }
}

/// Obscure/reveal toggle icon for password fields.
/// Previously hand-rolled 5x; one instance (_PasswordVerifyDialog in
/// container_config_sheet.dart) used the non-`_outlined` icon variants
/// (Icons.visibility / Icons.visibility_off) while every other instance used
/// the `_outlined` variants — a real visible glyph mismatch. This helper
/// makes that divergence impossible going forward.
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