import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/lock_flush_prompt.dart';

/// Locks every unlocked vault, asking about any whose USB device refused the
/// final write-back. Shared by the side drawer and the desktop Home toolbar.
///
/// [currentVolId] is the vault the caller's screen is showing, if any: its
/// lock guard is taken first so that screen can leave before the lock lands,
/// and [onLeavingCurrentVault] runs once that guard is held (the drawer
/// closes itself there).
Future<void> lockAllVaults(
  BuildContext context,
  WidgetRef ref,
  List<MountedContainer> mounted, {
  int? currentVolId,
  VoidCallback? onLeavingCurrentVault,
}) async {
  final willLeaveCurrentScreen =
      currentVolId != null && mounted.any((c) => c.volId == currentVolId);
  final controller = ref.read(vaultDashboardControllerProvider.notifier);
  final currentVaultGuardAcquired =
      willLeaveCurrentScreen && controller.acquireLockGuard(currentVolId!);
  if (currentVaultGuardAcquired) {
    onLeavingCurrentVault?.call();
  }
  var currentVaultGuardHeld = currentVaultGuardAcquired;
  var skippedBusyVault = false;
  // Vaults whose USB device refused the final write-back. They stay open; the
  // person is asked about each one only after every other vault has been locked.
  final flushRefused = <MountedContainer>[];
  try {
    for (final c in mounted) {
      final guardAlreadyHeld =
          c.volId == currentVolId && currentVaultGuardHeld;
      if (!guardAlreadyHeld && !controller.acquireLockGuard(c.volId)) {
        skippedBusyVault = true;
        continue;
      }
      try {
        final result = await ref
            .read(vaultLifecycleApiProvider)
            .lockContainerDetailed(c.uri);
        if (result == LockResult.locked) {
          controller.onContainerLocked(c.volId);
        } else if (result == LockResult.flushRefused) {
          flushRefused.add(c);
        } else {
          skippedBusyVault = true;
        }
      } catch (_) {
        skippedBusyVault = true;
      } finally {
        controller.releaseLockGuard(c.volId);
        if (guardAlreadyHeld) currentVaultGuardHeld = false;
      }
    }
  } finally {
    if (currentVaultGuardHeld) {
      controller.releaseLockGuard(currentVolId!);
    }
  }
  for (final c in flushRefused) {
    if (!controller.acquireLockGuard(c.volId)) continue;
    try {
      final result = await lockWithFlushPrompt(
        context: context,
        lifecycle: ref.read(vaultLifecycleApiProvider),
        uri: c.uri,
        displayName: c.displayName,
        firstResult: LockResult.flushRefused,
      );
      if (result == LockResult.locked) {
        controller.onContainerLocked(c.volId);
      } else if (result == LockResult.failed) {
        skippedBusyVault = true;
      }
    } catch (_) {
      skippedBusyVault = true;
    } finally {
      controller.releaseLockGuard(c.volId);
    }
  }
  if (skippedBusyVault && context.mounted) {
    showAppSnackBar(
      context,
      message: context.l10n.operationInProgressWaitMessage,
      tone: AppBannerTone.warning,
    );
  }
}
