// Decoy-identity counterpart of lib/features/share_import/share_import_flow.dart.
//
// Deliberately much simpler than the vault version: there's only ever one
// possible *local* destination (real device storage, via the same
// LocalStorageContainer/kDecoyLocalVolId pseudo-container
// DecoyFileManagerScreen already browses with -- see
// local_storage_container.dart), so there's no "which vault?" step, no
// conflict-resolution sheet, and no FileOperationService-backed progress
// tracking -- just a folder pick and a plain-storage copy, matching what
// a real file manager receiving a shared file would do.
//
// There IS still a way into a real vault from here: VaultFolderPickerSheet's
// own app bar title carries a HiddenVaultTrigger (same 2-second hold used
// throughout the decoy identity -- DecoyFileManagerScreen's title, the
// storage-access prompt), via VaultBrowserScaffold's wrapAppBarTitle hook.
// Its onBeforeReveal hands the buffered share over to the real
// share-import pipeline before LockGateScreen ever shows -- someone who
// leaves Mask Mode on permanently isn't limited to local storage, they
// just need to know the gesture, and there's no separate screen for it:
// the same folder picker serves both the oblivious "tap through, pick a
// folder" path and the "hold the title" one. See
// ShareIntentHandlers.handleHandoffLocalShareToVault's doc comment for
// the full reasoning. See LocalIncomingShareBridge.kt/ShareIntentHandlers.kt
// for the native half generally, and
// DisguiseModeHandlers.syncShareTargetIdentity for why the system Share
// Sheet itself already presents the decoy identity by the time any of
// this runs.
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/local_file_io_backend.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_folder_picker_sheet.dart';

/// Presents the decoy's own "where should this go?" flow for a shared
/// file that arrived while Mask Mode's decoy identity was active, then
/// saves it there in plain storage. [localContainer] should be the same
/// [MountedContainer] (built by `buildLocalStorageContainer`)
/// [DecoyFileManagerScreen] is already browsing.
Future<void> presentDecoyIncomingShareImport(
  BuildContext context,
  IncomingShareRequest request,
  MountedContainer localContainer, {
  void Function(Route<CryptoDestination> route)? onRouteCreated,
  bool Function()? isCurrent,
}) async {
  if (request.items.isEmpty) {
    if (isCurrent == null || isCurrent()) {
      await disguiseModeApi.cancelPendingLocalShareRequest();
    }
    return;
  }

  final route = MaterialPageRoute<CryptoDestination>(
    builder: (_) => VaultFolderPickerSheet(
      mountedContainers: [localContainer],
      wrapAppBarTitle: (title) => HiddenVaultTrigger(
        onBeforeReveal: disguiseModeApi.handoffLocalShareToVault,
        child: title,
      ),
    ),
  );
  onRouteCreated?.call(route);
  final destination = await Navigator.push<CryptoDestination>(context, route);
  if (isCurrent != null && !isCurrent()) {
    return;
  }
  if (destination == null) {
    await disguiseModeApi.cancelPendingLocalShareRequest();
    return;
  }
  final container = destination.container;
  final relativePath = destination.relativePath;
  if (container == null || relativePath == null) {
    await disguiseModeApi.cancelPendingLocalShareRequest();
    return;
  }

  final destDirPath = const LocalFileIoBackend().resolve(container.uri, relativePath);
  final result = await disguiseModeApi.importSharedUrisToLocal(destDirPath);

  if (!context.mounted) return;
  if (result.savedCount > 0) {
    showAppSnackBar(
      context,
      message: context.l10n.sharedFileSavedMessage(
        result.savedCount,
        destination.displayName,
      ),
      tone: AppBannerTone.info,
    );
  } else {
    showAppSnackBar(
      context,
      message: context.l10n.sharedFileSaveFailedMessage,
      tone: AppBannerTone.warning,
    );
  }
}
