import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Asks whether to throw away the unsaved edits when leaving the audio or
/// video editor. Resolves to true only if the user confirmed the discard.
Future<bool> confirmDiscardEditorChanges(BuildContext context) async {
  final l10n = context.l10n;
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.videoEditorDiscardTitle),
      content: Text(l10n.videoEditorDiscardMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ctx.colors.error,
            foregroundColor: ctx.colors.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.videoEditorDiscardAction),
        ),
      ],
    ),
  );
  return confirm == true;
}
