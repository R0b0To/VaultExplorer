import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

class DeleteOriginalsDialog {
  const DeleteOriginalsDialog._();

  /// Shows the "delete original files after import?" confirmation, with a
  /// "don't ask again" checkbox. Returns `null` if dismissed without
  /// picking either button -- the caller should treat that exactly like
  /// the original's `if (confirm == null) return;`, discarding whatever
  /// the checkbox was set to. Otherwise returns the button choice plus
  /// whether "don't ask again" was checked at the moment it was pressed.
  static Future<({bool confirmed, bool dontAskAgain})?> show(
    BuildContext context, {
    required bool isFolder,
  }) async {
    bool dontAskAgain = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text(context.l10n.deleteOriginalTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isFolder
                    ? context.l10n.deleteOriginalFolderMessage
                    : context.l10n.deleteOriginalFilesMessage,
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setDialogState(() {
                    dontAskAgain = !dontAskAgain;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: dontAskAgain,
                          onChanged: (val) {
                            setDialogState(() {
                              dontAskAgain = val ?? false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.dontAskAgain,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(context.l10n.keepOriginal),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(context.l10n.deleteOriginalButton),
            ),
          ],
        ),
      ),
    );
    if (confirm == null) return null;
    return (confirmed: confirm, dontAskAgain: dontAskAgain);
  }
}
