import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart'
    show AppBannerTone;

/// Puts [path] on the clipboard and confirms it with a snackbar. [context]
/// is read for the snackbar after the clipboard write, so it only needs to
/// still be mounted at that point.
Future<void> copyPathToClipboard(BuildContext context, String path) async {
  await Clipboard.setData(ClipboardData(text: path));
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    message: context.l10n.copiedSuffix(context.l10n.fullPathLabel),
    tone: AppBannerTone.success,
  );
}
