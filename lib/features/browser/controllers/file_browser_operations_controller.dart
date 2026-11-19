import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/perf_trace.dart';
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
    bool sourceItemsValidated = false,
    required Future<ConflictPlan?> Function(List<ConflictEntry> conflicts)
    resolveConflicts,
    required AppLocalizations l10n,
  }) async {
    final preEnqueueT0 = PerfTrace.begin();
    PerfTrace.count('paste.controller.items', items.length);
    final validItems = <ClipboardItem>[];
    final sourceCheckT0 = PerfTrace.begin();
    if (sourceItemsValidated) {
      validItems.addAll(items);
      PerfTrace.count('paste.controller.source_check_reused');
    } else {
      final sourceExists = await _fileIoApi.entryExistsBatch(srcContainer, [
        for (final item in items) (path: item.path, isDir: item.isDir),
      ]);
      for (var index = 0; index < items.length; index++) {
        if (sourceExists[index]) validItems.add(items[index]);
      }
    }
    PerfTrace.end('paste.controller.source_check', sourceCheckT0, slowMs: 250);
    PerfTrace.count('paste.controller.valid_items', validItems.length);
    if (validItems.isEmpty) {
      PerfTrace.count('paste.controller.no_valid_items');
      PerfTrace.end('paste.controller.pre_enqueue', preEnqueueT0, slowMs: 1000);
      return null;
    }

    final destListT0 = PerfTrace.begin();
    final existingRaw =
        await _fileIoApi.listDirectory(destContainer, destDirPath) ?? [];
    PerfTrace.end('paste.controller.dest_list', destListT0, slowMs: 250);
    final caseSensitive = namesAreCaseSensitive(destContainer);
    final existingNames = <String>{};
    final existingDirs = <String>{};
    for (final raw in existingRaw) {
      if (raw.startsWith('System:')) continue;
      final e = RawEntry.parse(raw);
      final key = foldEntryName(e.name, caseSensitive: caseSensitive);
      existingNames.add(key);
      if (e.isDir) existingDirs.add(key);
    }
    final conflictScanT0 = PerfTrace.begin();
    final conflicts = detectPasteConflicts(
      items: validItems,
      existingNamesLower: existingNames,
      existingDirsLower: existingDirs,
      isCrossContainer: isCrossContainer,
      isCutOperation: isCut,
      currentDirPath: destDirPath,
      caseSensitive: caseSensitive,
    );
    PerfTrace.end(
      'paste.controller.conflict_scan',
      conflictScanT0,
      slowMs: 100,
    );
    PerfTrace.count('paste.controller.conflicts', conflicts.length);
    ConflictPlan conflictPlan = const {};
    if (conflicts.isNotEmpty) {
      final conflictSheetT0 = PerfTrace.begin();
      final result = await resolveConflicts(conflicts);
      PerfTrace.end(
        'paste.controller.conflict_sheet',
        conflictSheetT0,
        slowMs: 500,
      );
      if (result == null) {
        PerfTrace.count('paste.controller.conflict_cancelled');
        PerfTrace.end(
          'paste.controller.pre_enqueue',
          preEnqueueT0,
          slowMs: 1000,
        );
        return null;
      }
      conflictPlan = result;
    }
    // enqueueLocalTransfer takes a raw dart:io shortcut -- it resolves
    // *both* source and dest paths as plain filesystem paths under their
    // .uri root, which only holds when both ends are raw POSIX local storage.
    // If either side is a SAF Document Provider (content://), route through
    // the general runner to use VaultFileIoApi.
    final bothAreRawLocal = destContainer.isRawLocal && srcContainer.isRawLocal;
    final enqueueT0 = PerfTrace.begin();
    final op = bothAreRawLocal
        ? _opSvc.enqueueLocalTransfer(
            isCut: isCut,
            source: srcContainer,
            dest: destContainer,
            destDirPath: destDirPath,
            items: validItems,
            conflictPlan: conflictPlan,
            l10n: l10n,
          )
        : _opSvc.enqueue(
            isCut: isCut,
            source: srcContainer,
            dest: destContainer,
            destDirPath: destDirPath,
            items: validItems,
            conflictPlan: conflictPlan,
            l10n: l10n,
          );
    PerfTrace.end('paste.controller.enqueue', enqueueT0, slowMs: 100);
    PerfTrace.end('paste.controller.pre_enqueue', preEnqueueT0, slowMs: 1000);
    return op;
  }
}
