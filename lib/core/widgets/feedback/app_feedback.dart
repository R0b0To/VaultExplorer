import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart' show AppBannerTone;

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
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
        duration: const Duration(seconds: 3),
        content: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.full),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon ?? defaultIcon, color: fg, size: AppIconSize.standard),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      action.onPressed();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: action.textColor ?? cs.inversePrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(action.label),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
}

Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool isDestructive = false,
}) async {
  final cs = context.colors;
  final resolvedConfirmLabel = confirmLabel ?? context.l10n.confirm;
  final resolvedCancelLabel = cancelLabel ?? context.l10n.cancel;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(resolvedCancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            resolvedConfirmLabel,
            style: isDestructive ? TextStyle(color: cs.error) : null,
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}