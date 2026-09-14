import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/paste_conflict_detection.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'file_browser_operations_controller.g.dart';

/// No internal mutable state of its own -> pure keep-alive provider per the
/// migration plan's Phase 3 rule, matching [MediaScanService]'s shape.
@Riverpod(keepAlive: true)
FileBrowserOperationsController fileBrowserOperationsController(Ref ref) =>
    FileBrowserOperationsController(
      opSvc: ref.watch(fileOperationServiceProvider),
      fileIoApi: ref.watch(vaultFileIoApiProvider),
    );

/// Decision logic pulled out of `_FileBrowserScreenState._paste()`
/// (file-browser-screen decomposition, tech-debt audit, Sept 2026) --
/// specifically just its "Standard Copy / Move Paste" branch: list the
/// destination, run [detectPasteConflicts] (already a separately tested
/// pure function -- this controller doesn't duplicate that), and choose
/// between [FileOperationService.enqueueLocalTransfer] (the raw dart:io
/// shortcut, correct only when *both* ends are local storage -- see the
/// comment on [pasteStandardTransfer] itself) and the general
/// [FileOperationService.enqueue].
///
/// `_paste`'s other two branches -- archive-create and archive-extract --
/// were left in the widget: each is already just "show one options sheet,
/// forward its fields into one `_opSvc.enqueueXxx` call", with no
/// comparable branching to test. Moving them for line-count alone would
/// have added surface area without adding testability, the same call made
/// for `MediaViewerScreen`'s animation-bound methods in this same audit.
///
/// [resolveConflicts] is how this stays BuildContext-free while still
/// being able to show `ConflictResolutionSheet` mid-flow: the widget
/// passes a callback that shows the sheet and returns its result, matching
/// the `isStillWanted`-callback shape already used for
/// [MediaPrefetchController] and the `l10n`-parameter shape
/// [RealPasswordGateController] already established for this exact
/// "controller needs something only BuildContext can give it" case.
class FileBrowserOperationsController {
  final FileOperationService _opSvc;
  final VaultFileIoApi _fileIoApi;

  FileBrowserOperationsController({
    required FileOperationService opSvc,
    required VaultFileIoApi fileIoApi,
  }) : _opSvc = opSvc,
       _fileIoApi = fileIoApi;

  /// Returns the enqueued [FileOperation], or `null` if conflicts were
  /// found and the user cancelled resolving them (mirrors `_paste`'s old
  /// early `return` in that case exactly).
  Future<FileOperation?> pasteStandardTransfer({
    required MountedContainer destContainer,
    required MountedContainer srcContainer,
    required String destDirPath,
    required List<ClipboardItem> items,
    required bool isCut,
    required bool isCrossContainer,
    required Future<ConflictPlan?> Function(List<ConflictEntry> conflicts) resolveConflicts,
    required AppLocalizations l10n,
  }) async {
    final existingRaw = await _fileIoApi.listDirectory(destContainer, destDirPath) ?? [];
    final existingNames = <String>{};
    final existingDirs = <String>{};
    for (final raw in existingRaw) {
      if (raw.startsWith('System:')) continue;
      final e = RawEntry.parse(raw);
      existingNames.add(e.name.toLowerCase());
      if (e.isDir) existingDirs.add(e.name.toLowerCase());
    }
    final conflicts = detectPasteConflicts(
      items: items,
      existingNamesLower: existingNames,
      existingDirsLower: existingDirs,
      isCrossContainer: isCrossContainer,
      isCutOperation: isCut,
      currentDirPath: destDirPath,
    );
    ConflictPlan conflictPlan = const {};
    if (conflicts.isNotEmpty) {
      final result = await resolveConflicts(conflicts);
      if (result == null) return null;
      conflictPlan = result;
    }
    // enqueueLocalTransfer takes a raw dart:io shortcut -- it resolves
    // *both* source and dest paths as plain filesystem paths under their
    // .uri root, which only holds when both ends are local storage.
    // enqueue()/the general runner goes through VaultFileIoApi on both
    // ends instead, which already branches on isLocalStorage per call, so
    // it's correct for vault<->local in either direction too (and for
    // vault<->vault, unaffected here).
    final bothLocalStorage = destContainer.isLocalStorage && srcContainer.isLocalStorage;
    return bothLocalStorage
        ? _opSvc.enqueueLocalTransfer(
            isCut: isCut,
            source: srcContainer,
            dest: destContainer,
            destDirPath: destDirPath,
            items: items,
            conflictPlan: conflictPlan,
            l10n: l10n,
          )
        : _opSvc.enqueue(
            isCut: isCut,
            source: srcContainer,
            dest: destContainer,
            destDirPath: destDirPath,
            items: items,
            conflictPlan: conflictPlan,
            l10n: l10n,
          );
  }
}
