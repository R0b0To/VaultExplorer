import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/app/app_navigator_key.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// What the person chose when a USB device refused to take the last buffered writes.
enum LockRefusalChoice {
  /// Try the write-back again (e.g. after reseating the cable).
  retry,

  /// Lock now and discard whatever could not be written.
  lockAnyway,

  /// Leave the container open.
  cancel,
}

/// Asks what to do about a lock that was refused because [displayName]'s device would
/// not accept the final write-back. Dismissing the dialog counts as
/// [LockRefusalChoice.cancel], so nothing is discarded by accident.
Future<LockRefusalChoice> showLockFlushRefusedDialog(
  BuildContext context, {
  required String displayName,
}) async {
  final choice = await showDialog<LockRefusalChoice>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      return AlertDialog(
        title: Text(l10n.lockFlushRefusedTitle),
        content: Text(l10n.lockFlushRefusedMessage(displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, LockRefusalChoice.cancel),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, LockRefusalChoice.lockAnyway),
            child: Text(
              l10n.lockAnywayButton,
              style: TextStyle(color: dialogContext.colors.error),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, LockRefusalChoice.retry),
            child: Text(l10n.retryButton),
          ),
        ],
      );
    },
  );
  return choice ?? LockRefusalChoice.cancel;
}

/// Locks the container at [uri]. If the device refuses the final write-back the
/// container stays open with its data pending, and the person is asked whether to
/// retry, lock anyway (discarding what could not be written) or cancel -- repeatedly
/// until the lock succeeds, fails for another reason, or they cancel.
///
/// Pass [firstResult] when the first attempt was already made by the caller (for
/// example in a lock-all loop that prompts only after every other vault is locked).
/// The caller keeps holding its own lock guard around this call.
///
/// Resolves with the final [LockResult]: [LockResult.flushRefused] means the
/// container was deliberately left open.
Future<LockResult> lockWithFlushPrompt({
  required BuildContext context,
  required VaultLifecycleApi lifecycle,
  required String uri,
  required String displayName,
  LockResult? firstResult,
}) async {
  var result = firstResult ?? await lifecycle.lockContainerDetailed(uri);
  while (result == LockResult.flushRefused) {
    final dialogContext = _usableContext(context);
    if (dialogContext == null) return result;
    final choice = await showLockFlushRefusedDialog(
      dialogContext,
      displayName: displayName,
    );
    switch (choice) {
      case LockRefusalChoice.retry:
        result = await lifecycle.lockContainerDetailed(uri);
      case LockRefusalChoice.lockAnyway:
        result = await lifecycle.lockContainerDetailed(uri, force: true);
      case LockRefusalChoice.cancel:
        return result;
    }
  }
  return result;
}

/// [context] if it is still in the tree; otherwise the app's root navigator, which
/// outlives the route that started the lock (the navigation drawer closes itself
/// before a lock-all runs).
BuildContext? _usableContext(BuildContext context) {
  if (context.mounted) return context;
  return appNavigatorKey.currentState?.overlay?.context;
}
