import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Error-container banner with icon + message.
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

/// Generic tinted inline banner (success / warning / info / error) — the
/// general-purpose sibling of [InlineErrorBanner], built on
/// [AppSemanticColors] so status colors never get hand-rolled again.
enum AppBannerTone { info, success, warning, error }

class InlineBanner extends StatelessWidget {
  final String message;
  final AppBannerTone tone;
  final IconData? icon;
  final Widget? trailing;

  const InlineBanner(
    this.message, {
    super.key,
    this.tone = AppBannerTone.info,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final semantic = context.semanticColors;
    final textTheme = context.typography;

    final (Color bg, Color fg, IconData defaultIcon) = switch (tone) {
      AppBannerTone.info => (cs.secondaryContainer, cs.onSecondaryContainer, Icons.info_outline_rounded),
      AppBannerTone.success => (semantic.successContainer, semantic.onSuccessContainer, Icons.check_circle_outline_rounded),
      AppBannerTone.warning => (semantic.warningContainer, semantic.onWarningContainer, Icons.warning_amber_rounded),
      AppBannerTone.error => (cs.errorContainer, cs.onErrorContainer, Icons.error_outline_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon ?? defaultIcon, size: AppIconSize.standard, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: textTheme.bodySmall?.copyWith(color: fg, height: 1.4)),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
