import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    SystemNavigator.pop();
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
    final entries = buildShareImportConflictEntries(
      conflicts: pick.conflicts,
      items: pick.items,
    );
    final resolved = await ConflictResolutionSheet.show(
      context,
      conflicts: entries,
      cancelLabel: context.l10n.cancelImportButton,
    );
    if (resolved == null) {
      await vaultFileIoApi.cancelPickedImport(pick.pickToken);
      SystemNavigator.pop();
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

/// Builds the [ConflictResolutionSheet] entry list for a share-import pick's
/// reported [conflicts], looking up each conflicting name in [items] for its
/// size and directory-ness. Falls back to a zero-size synthetic item if a
/// conflicting name isn't found among [items] (e.g. it only exists in the
/// destination folder already, not among the freshly-shared items) rather
/// than throwing, matching [ImportPickResult]'s own permissive shape.
List<ConflictEntry> buildShareImportConflictEntries({
  required List<ImportPickConflict> conflicts,
  required List<ClipboardItem> items,
}) =>
    conflicts
        .map(
          (c) => ConflictEntry(
            item: items.firstWhere(
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

void _attachCompletionListener(FileOperationService opSvc, FileOperation op) {
  void listener() {
    final done =
        op.status != FileOperationStatus.running &&
        op.status != FileOperationStatus.pending;
    if (!done) return;
    op.removeListener(listener);
    if (!shareImportNeedsAttention(op.status)) {
      opSvc.dismiss(op.id);
      Future.delayed(const Duration(milliseconds: 600), () {
        SystemNavigator.pop();
      });
    }
  }

  op.addListener(listener);
}

/// Whether a just-finished share-import operation in [status] needs the
/// person's attention -- if so, [_attachCompletionListener] leaves it
/// visible in the active-transfers UI instead of auto-dismissing it and
/// closing the share-target activity.
bool shareImportNeedsAttention(FileOperationStatus status) =>
    status == FileOperationStatus.failed ||
    status == FileOperationStatus.diskFull ||
    status == FileOperationStatus.completedWithErrors;