import 'package:flutter/services.dart';
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

  bool handedOffToVault = false;

  final route = MaterialPageRoute<CryptoDestination>(
    builder: (_) => VaultFolderPickerSheet(
      mountedContainers: [localContainer],
      wrapAppBarTitle: (title) => HiddenVaultTrigger(
        onBeforeReveal: () async {
          handedOffToVault = true;
          await disguiseModeApi.handoffLocalShareToVault();
        },
        child: title,
      ),
    ),
  );
  onRouteCreated?.call(route);
  final destination = await Navigator.push<CryptoDestination>(context, route);
  if (handedOffToVault) {
    return;
  }
  if (isCurrent != null && !isCurrent()) {
    return;
  }
  if (destination == null) {
    await disguiseModeApi.cancelPendingLocalShareRequest();
    SystemNavigator.pop();
    return;
  }
  final container = destination.container;
  final relativePath = destination.relativePath;
  if (container == null || relativePath == null) {
    await disguiseModeApi.cancelPendingLocalShareRequest();
    SystemNavigator.pop();
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
    Future.delayed(const Duration(milliseconds: 900), () {
      SystemNavigator.pop();
    });
  } else {
    showAppSnackBar(
      context,
      message: context.l10n.sharedFileSaveFailedMessage,
      tone: AppBannerTone.warning,
    );
  }
}
