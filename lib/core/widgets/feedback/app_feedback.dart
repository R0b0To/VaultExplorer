import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart' show AppBannerTone;

/// Centralized SnackBar presenter so every screen shows the same shape,
/// duration, and icon language instead of hand-building `SnackBar(...)`
/// inline. Uses [AppSemanticColors] for success/warning tones.
void showAppSnackBar(
  BuildContext context, {
  required String message,
  AppBannerTone tone = AppBannerTone.info,
  IconData? icon,
  SnackBarAction? action,
}) {
  final cs = context.colors;
  final semantic = context.semanticColors;

  final (Color bg, Color fg, IconData defaultIcon) = switch (tone) {
    AppBannerTone.info => (cs.inverseSurface, cs.onInverseSurface, Icons.info_outline_rounded),
    AppBannerTone.success => (semantic.success, semantic.onSuccess, Icons.check_circle_rounded),
    AppBannerTone.warning => (semantic.warning, semantic.onWarning, Icons.warning_amber_rounded),
    AppBannerTone.error => (cs.error, cs.onError, Icons.error_outline_rounded),
  };

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        backgroundColor: bg,
        content: Row(
          children: [
            Icon(icon ?? defaultIcon, color: fg, size: AppIconSize.standard),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: fg)),
            ),
          ],
        ),
        action: action,
      ),
    );
}

Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) async {
  final cs = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            confirmLabel,
            style: isDestructive ? TextStyle(color: cs.error) : null,
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
