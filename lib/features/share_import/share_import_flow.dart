import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/features/share_import/share_destination_sheet.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

Future<void> presentIncomingShareImport(
  BuildContext context,
  WidgetRef ref,
  IncomingShareRequest request, {
  void Function(Route<CryptoDestination> route)? onRouteCreated,
  bool Function()? isCurrent,
}) async {
  final vaultFileIoApi = ref.read(vaultFileIoApiProvider);

  final route = MaterialPageRoute<CryptoDestination>(
    builder: (_) => const ShareDestinationSheet(),
  );
  onRouteCreated?.call(route);
  final destination = await Navigator.push<CryptoDestination>(context, route);
  if (isCurrent != null && !isCurrent()) {
    return;
  }
  if (destination == null) {
    await vaultFileIoApi.cancelPendingShareRequest();
    return;
  }
  final container = destination.container;
  final relativePath = destination.relativePath;
  if (!destination.isVault || container == null || relativePath == null) {
    await vaultFileIoApi.cancelPendingShareRequest();
    return;
  }

  final pick = await vaultFileIoApi.prepareShareImport(
    container,
    relativePath,
  );
  if (pick == null) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.shareImportExpiredMessage,
        tone: AppBannerTone.warning,
      );
    }
    return;
  }

  ConflictPlan conflictPlan = const {};
  if (pick.conflicts.isNotEmpty) {
    if (!context.mounted) {
      await vaultFileIoApi.cancelPickedImport(pick.pickToken);
      return;
    }
    final entries = pick.conflicts
        .map(
          (c) => ConflictEntry(
            item: pick.items.firstWhere(
              (i) => i.path == c.name,
              orElse: () => ClipboardItem(
                path: c.name,
                isDir: c.destIsDir,
                sizeBytes: 0,
              ),
            ),
            destIsDir: c.destIsDir,
          ),
        )
        .toList();
    final resolved = await ConflictResolutionSheet.show(
      context,
      conflicts: entries,
      cancelLabel: context.l10n.cancelImportButton,
    );
    if (resolved == null) {
      await vaultFileIoApi.cancelPickedImport(pick.pickToken);
      return;
    }
    conflictPlan = resolved;
  }

  if (!context.mounted) return;
  final opSvc = ref.read(fileOperationServiceProvider);
  final op = opSvc.enqueueImport(
    dest: container,
    destDirPath: relativePath,
    items: pick.items,
    isFolder: false,
    sourceDisplayName: context.l10n.sharedFileDefaultDisplayName,
    performImport: (opId) => vaultFileIoApi.importFiles(
      container,
      relativePath,
      opId,
      pick.pickToken,
      conflictPlan: conflictPlan.map((k, v) => MapEntry(k, v.name)),
    ),
    l10n: context.l10n,
  );
  _attachCompletionListener(opSvc, op);

  if (context.mounted) {
    final count = pick.items.length;
    showAppSnackBar(
      context,
      message: context.l10n.importingSharedFilesMessage(count, destination.displayName),
      tone: AppBannerTone.info,
    );
  }
}

void _attachCompletionListener(FileOperationService opSvc, FileOperation op) {
  void listener() {
    final done =
        op.status != FileOperationStatus.running &&
        op.status != FileOperationStatus.pending;
    if (!done) return;
    op.removeListener(listener);
    final needsAttention =
        op.status == FileOperationStatus.failed ||
        op.status == FileOperationStatus.diskFull ||
        op.status == FileOperationStatus.completedWithErrors;
    if (!needsAttention) {
      opSvc.dismiss(op.id);
    }
  }

  op.addListener(listener);
}