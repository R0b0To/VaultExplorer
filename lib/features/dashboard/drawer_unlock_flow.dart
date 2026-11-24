import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/layout/adaptive_page_route.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/unlock/unlock_sheet.dart';
import 'package:vaultexplorer/features/unlock/usb_unlock_sheet.dart';

/// Unlocks the vault [record] from a sidebar tap and hands the vault to
/// [onOpen] once it is mounted.
///
/// The sidebar is a navigation surface: tapping a locked vault means "take me
/// there", exactly like tapping a mounted one. It therefore always has one
/// unlock path (independent of whether a Dashboard is on screen) and always
/// opens the vault afterwards. It is shared by every window that has the
/// sidebar; [context] is the window's own, so the unlock page opens in it.
/// [isMounted] says whether the caller's widget is still in the tree.
Future<void> showDrawerUnlock({
  required BuildContext context,
  required WidgetRef ref,
  required ContainerRecord record,
  required bool Function() isMounted,
  required ValueChanged<MountedContainer> onOpen,
}) async {
  final state = ref.read(vaultDashboardControllerProvider);
  if (state.mounted.any((container) => container.uri == record.uri)) {
    showAppSnackBar(context, message: context.l10n.containerAlreadyMounted);
    return;
  }
  if (state.actionInFlight) return;

  final controller = ref.read(vaultDashboardControllerProvider.notifier);
  final repository = ref.read(containerRepositoryProvider);
  final navigator = Navigator.of(context);
  controller.setActionInFlight(true);

  MountedContainer? newlyMountedContainer;
  try {
    final rememberedPassword =
        record.unlockMethod == ContainerUnlockMethod.rememberPassword
        ? await repository.getPassword(record.uri)
        : null;
    if (!isMounted()) return;

    // Deliberately ignores the Dashboard's "auto-open on unlock" setting:
    // that setting means "stay on the Vaults page", which has no meaning
    // when the unlock was started from the drawer (often while browsing
    // another vault). Without this the unlock gave no visible feedback.
    if (record.isUsbSource) {
      await navigator.push<void>(
        adaptivePageRoute<void>(
          context,
          builder: (_) => SkinAreaScope(
            area: SkinArea.dashboard,
            child: UsbUnlockSheet(
              existingRecord: record,
              prefillPassword: rememberedPassword,
              documentProvider: record.documentProvider,
              autoMountFolders: record.documentProviderFolders
                  .where((folder) => folder.autoMount)
                  .map((folder) => folder.path)
                  .toList(),
              onMounted: (container, {record}) {
                controller.onContainerMounted(container, record: record);
                newlyMountedContainer = container;
                if (isMounted()) onOpen(container);
              },
              onReconnected: (container, migratedRecord, oldUri) {
                controller.onUsbContainerReconnected(
                  container,
                  migratedRecord,
                  oldUri,
                );
                newlyMountedContainer = container;
              },
            ),
          ),
        ),
      );
    } else {
      await navigator.push<void>(
        adaptivePageRoute<void>(
          context,
          builder: (_) => SkinAreaScope(
            area: SkinArea.dashboard,
            child: UnlockSheet(
              initialUri: record.uri,
              initialName: record.label,
              prefillPassword: rememberedPassword,
              documentProvider: record.documentProvider,
              autoMountFolders: record.documentProviderFolders
                  .where((folder) => folder.autoMount)
                  .map((folder) => folder.path)
                  .toList(),
              mountedUris: state.mounted
                  .map((container) => container.uri)
                  .toList(),
              onMounted: (container, {record}) {
                controller.onContainerMounted(container, record: record);
                newlyMountedContainer = container;
                if (isMounted()) onOpen(container);
              },
            ),
          ),
        ),
      );
    }

    await controller.loadAll();
    if (newlyMountedContainer != null) {
      await controller.refreshContainerSpace(newlyMountedContainer!.volId);
    }
  } finally {
    controller.setActionInFlight(false);
  }
}
