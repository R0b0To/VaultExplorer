library;

import 'dart:async';

import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Cancellation flag shared between a [VaultSyncService.scanDiff] caller
/// and its in-flight scan. Kept as its own type (rather than reusing
/// DuplicateFinderService's token) so a token from one tool can't
/// accidentally be handed to the other -- see [CancellationToken]'s doc
/// comment for the shared bool-flag implementation this delegates to.
class VaultSyncCancellationToken extends CancellationToken {}

/// Core service behind the Vault-to-Vault Synchronizer / Diff tool.
///
/// [scanDiff] walks two [VaultSyncSide]s in lock-step using
/// [VaultFileIoApi.listDirectory], descending into subfolders that exist
/// as a directory on both sides and recording every path that differs by
/// size or modified time. [executeSync] then turns a resolved diff and a
/// per-entry action plan into [FileOperationService] copy batches, reusing
/// the app's existing cross-container batch copy engine rather than moving
/// bytes itself.
class VaultSyncService {
  static const _maxDepth = 24;

  final VaultFileIoApi _fileIoApi;

  VaultSyncService(this._fileIoApi);

  /// Time tolerance (in seconds) when comparing modification timestamps
  /// for files with different sizes.
  static const int _mtimeToleranceSecs = 2;

  /// Live free-space query for [container], in bytes. Queries the
  /// platform directly rather than trusting [MountedContainer.freeSpace]
  /// (a snapshot from mount time that won't reflect writes since). Returns
  /// null when the platform can't report it, so callers can treat "unknown"
  /// as "don't block" rather than as "zero" -- same leniency
  /// [FileOperationService]'s own pre-flight check uses.
  Future<int?> freeSpaceBytes(MountedContainer container) async {
    try {
      final info = await _fileIoApi.getSpaceInfo(container);
      if (info != null && info.length > 1 && info[1] >= 0) return info[1];
    } catch (_) {
      // Treated as unknown below.
    }
    return null;
  }

  /// Compares [left] and [right] and streams progress + results as the
  /// walk proceeds. The final update always has
  /// [VaultSyncScanProgress.stage] of [VaultSyncScanStage.complete] (or
  /// [VaultSyncScanStage.cancelled] if [cancelToken] was cancelled).
  Stream<VaultSyncScanUpdate> scanDiff({
    required VaultSyncSide left,
    required VaultSyncSide right,
    VaultSyncCancellationToken? cancelToken,
  }) {
    final controller = StreamController<VaultSyncScanUpdate>();
    unawaited(_runScan(left, right, cancelToken, controller));
    return controller.stream;
  }

  Future<void> _runScan(
    VaultSyncSide left,
    VaultSyncSide right,
    VaultSyncCancellationToken? cancelToken,
    StreamController<VaultSyncScanUpdate> controller,
  ) async {
    final entries = <VaultDiffEntry>[];
    var dirsScanned = 0;
    var identicalCount = 0;

    controller.add(
      const VaultSyncScanUpdate(
        progress: VaultSyncScanProgress(stage: VaultSyncScanStage.comparing),
        entries: [],
        identicalCount: 0,
      ),
    );

    Future<void> walk(String relDir, int depth) async {
      if (depth > _maxDepth || (cancelToken?.isCancelled ?? false)) return;

      List<String>? leftRaw;
      List<String>? rightRaw;
      try {
        leftRaw = await _fileIoApi.listDirectory(
          left.container,
          _absPath(left.relativePath, relDir),
        );
      } catch (_) {
        // Unreadable on the left -- treated as empty, so everything on the
        // right under this path shows up as "only on Right".
      }
      if (cancelToken?.isCancelled ?? false) return;
      try {
        rightRaw = await _fileIoApi.listDirectory(
          right.container,
          _absPath(right.relativePath, relDir),
        );
      } catch (_) {
        // Same for the right side.
      }
      if (cancelToken?.isCancelled ?? false) return;

      dirsScanned++;

      final leftEntries = <String, RawEntry>{
        for (final e in RawEntry.parseAll(leftRaw ?? const [])) e.name: e,
      };
      final rightEntries = <String, RawEntry>{
        for (final e in RawEntry.parseAll(rightRaw ?? const [])) e.name: e,
      };

      final names = {...leftEntries.keys, ...rightEntries.keys}.toList()
        ..sort();
      final subDirs = <String>[];

      for (final name in names) {
        final l = leftEntries[name];
        final r = rightEntries[name];
        final fullPath = relDir.isEmpty ? name : '$relDir/$name';

        if (l != null && r == null) {
          int? folderSize;
          if (l.isDir) {
            try {
              folderSize = await _fileIoApi.getFolderSize(
                left.container,
                _absPath(left.relativePath, fullPath),
              );
            } catch (_) {
              // folderSize stays null; the entry below is still added with
              // an unknown size rather than dropping it from the diff.
            }
          }

          entries.add(
            VaultDiffEntry(
              relativePath: fullPath,
              name: name,
              isDir: l.isDir,
              status: VaultDiffStatus.onlyLeft,
              leftSizeBytes: l.isDir ? folderSize : l.sizeBytes,
              leftModifiedSecs: l.modifiedSecs,
            ),
          );
          continue;
        }

        if (l == null && r != null) {
          int? folderSize;
          if (r.isDir) {
            try {
              folderSize = await _fileIoApi.getFolderSize(
                right.container,
                _absPath(right.relativePath, fullPath),
              );
            } catch (_) {
              // Same reasoning as the left-only branch above: unknown size
              // is fine, dropping the entry from the diff wouldn't be.
            }
          }

          entries.add(
            VaultDiffEntry(
              relativePath: fullPath,
              name: name,
              isDir: r.isDir,
              status: VaultDiffStatus.onlyRight,
              rightSizeBytes: r.isDir ? folderSize : r.sizeBytes,
              rightModifiedSecs: r.modifiedSecs,
            ),
          );
          continue;
        }

        // Present on both sides from here on.
        if (l!.isDir != r!.isDir) {
          entries.add(
            VaultDiffEntry(
              relativePath: fullPath,
              name: name,
              isDir: l.isDir,
              status: VaultDiffStatus.conflicted,
              typeMismatch: true,
              leftSizeBytes: l.sizeBytes,
              leftModifiedSecs: l.modifiedSecs,
              rightSizeBytes: r.sizeBytes,
              rightModifiedSecs: r.modifiedSecs,
            ),
          );
          continue;
        }

        if (l.isDir) {
          // Both sides have this as a folder -- descend instead of
          // recording the folder itself as a diff entry.
          subDirs.add(fullPath);
          continue;
        }

        // SMART GUARD: If file sizes match on both sides, consider the files
        // identical and in-sync. Target storage backends/SAF/cryptors on Android
        // often reset modification timestamps to 'now' upon writing, which
        // previously caused newly synced files to be falsely flagged as
        // 'newer' on the destination and repeatedly overwritten in a loop.
        if (l.sizeBytes == r.sizeBytes) {
          identicalCount++;
          continue;
        }

        // File sizes differ -- the file contents are definitely different.
        // Compare modification times to determine which side is newer.
        final VaultDiffStatus status;
        if (l.modifiedSecs > r.modifiedSecs + _mtimeToleranceSecs) {
          status = VaultDiffStatus.leftNewer;
        } else if (r.modifiedSecs > l.modifiedSecs + _mtimeToleranceSecs) {
          status = VaultDiffStatus.rightNewer;
        } else {
          // Different file sizes but same/near-same modification date
          status = VaultDiffStatus.conflicted;
        }

        entries.add(
          VaultDiffEntry(
            relativePath: fullPath,
            name: name,
            isDir: false,
            status: status,
            leftSizeBytes: l.sizeBytes,
            leftModifiedSecs: l.modifiedSecs,
            rightSizeBytes: r.sizeBytes,
            rightModifiedSecs: r.modifiedSecs,
          ),
        );
      }

      if (dirsScanned % 4 == 0 && !controller.isClosed) {
        controller.add(
          VaultSyncScanUpdate(
            progress: VaultSyncScanProgress(
              stage: VaultSyncScanStage.comparing,
              dirsScanned: dirsScanned,
              entriesCompared: entries.length,
              currentPath: relDir,
            ),
            entries: List.unmodifiable(entries),
            identicalCount: identicalCount,
          ),
        );
      }

      for (final sub in subDirs) {
        if (cancelToken?.isCancelled ?? false) return;
        await walk(sub, depth + 1);
      }
    }

    try {
      await walk('', 0);

      if (cancelToken?.isCancelled ?? false) {
        controller.add(
          const VaultSyncScanUpdate(
            progress: VaultSyncScanProgress(
              stage: VaultSyncScanStage.cancelled,
            ),
            entries: [],
            identicalCount: 0,
          ),
        );
        return;
      }

      entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
      controller.add(
        VaultSyncScanUpdate(
          progress: VaultSyncScanProgress(
            stage: VaultSyncScanStage.complete,
            dirsScanned: dirsScanned,
            entriesCompared: entries.length,
          ),
          entries: List.unmodifiable(entries),
          identicalCount: identicalCount,
        ),
      );
    } finally {
      await controller.close();
    }
  }

  /// The action [direction] assigns a diff entry by default, before any
  /// per-entry override from the user. Type-mismatched entries are always
  /// skipped -- there's no safe automatic way to replace a file with a
  /// folder or vice versa.
  EntryAction defaultAction(VaultDiffEntry e, SyncDirection direction) {
    if (e.typeMismatch) return EntryAction.skip;
    switch (e.status) {
      case VaultDiffStatus.onlyLeft:
        return direction == SyncDirection.rightToLeft
            ? EntryAction.skip
            : EntryAction.copyToRight;
      case VaultDiffStatus.onlyRight:
        return direction == SyncDirection.leftToRight
            ? EntryAction.skip
            : EntryAction.copyToLeft;
      case VaultDiffStatus.leftNewer:
        return direction == SyncDirection.rightToLeft
            ? EntryAction.skip
            : EntryAction.copyToRight;
      case VaultDiffStatus.rightNewer:
        return direction == SyncDirection.leftToRight
            ? EntryAction.skip
            : EntryAction.copyToLeft;
      case VaultDiffStatus.conflicted:
        return EntryAction.skip;
    }
  }

  /// Enqueues [FileOperationService] copy batches for every entry [plan]
  /// marks as [EntryAction.copyToRight] or [EntryAction.copyToLeft].
  ///
  /// File entries are grouped by destination folder so each folder becomes
  /// a single batch copy, and whole missing folders ([VaultDiffEntry.isDir])
  /// are copied recursively in one call rather than file by file. Returns
  /// the enqueued [FileOperation]s so the caller can track completion (the
  /// app's global [AppBarTransferButton] also picks these up automatically
  /// since they go through the shared [FileOperationService] queue).
  ///
  /// [fileOperationService] is threaded in by the caller (see
  /// `VaultSync.executeSync`, which reads it from
  /// `fileOperationServiceProvider`) rather than reached for via
  /// `FileOperationService` directly here -- this class is still
  /// receives the engine API through its constructor and the queue service
  /// through this method call, so both dependencies remain overrideable in
  /// controller tests.
  List<FileOperation> executeSync({
    required VaultSyncSide left,
    required VaultSyncSide right,
    required List<VaultDiffEntry> entries,
    required Map<String, EntryAction> plan,
    required AppLocalizations l10n,
    required FileOperationService fileOperationService,
  }) {
    final toRight = <VaultDiffEntry>[];
    final toLeft = <VaultDiffEntry>[];
    for (final e in entries) {
      final action = plan[e.id] ?? EntryAction.skip;
      if (action == EntryAction.copyToRight) {
        toRight.add(e);
      } else if (action == EntryAction.copyToLeft) {
        toLeft.add(e);
      }
    }

    return [
      ..._enqueueDirection(
        source: left,
        dest: right,
        entries: toRight,
        sourceIsLeft: true,
        l10n: l10n,
        fileOperationService: fileOperationService,
      ),
      ..._enqueueDirection(
        source: right,
        dest: left,
        entries: toLeft,
        sourceIsLeft: false,
        l10n: l10n,
        fileOperationService: fileOperationService,
      ),
    ];
  }

  List<FileOperation> _enqueueDirection({
    required VaultSyncSide source,
    required VaultSyncSide dest,
    required List<VaultDiffEntry> entries,
    required bool sourceIsLeft,
    required AppLocalizations l10n,
    required FileOperationService fileOperationService,
  }) {
    if (entries.isEmpty) return const [];
    final ops = <FileOperation>[];

    final dirEntries = entries.where((e) => e.isDir).toList();
    final fileEntries = entries.where((e) => !e.isDir).toList();

    // Whole missing folders: one batch per folder, copied recursively by
    // the existing copy engine (it creates the destination folder and
    // walks the source tree itself).
    for (final e in dirEntries) {
      final srcAbsPath = _absPath(source.relativePath, e.relativePath);
      final destParentAbs = _absPath(
        dest.relativePath,
        _parentOf(e.relativePath),
      );
      final folderSize = sourceIsLeft
          ? (e.leftSizeBytes ?? 0)
          : (e.rightSizeBytes ?? 0);
      ops.add(
        fileOperationService.enqueue(
          isCut: false,
          source: source.container,
          dest: dest.container,
          destDirPath: destParentAbs,
          items: [
            ClipboardItem(
              path: srcAbsPath,
              isDir: true,
              sizeBytes: folderSize,
              modifiedSecs: sourceIsLeft
                  ? (e.leftModifiedSecs ?? 0)
                  : (e.rightModifiedSecs ?? 0),
            ),
          ],
          l10n: l10n,
        ),
      );
    }

    // New/modified files: grouped by their parent folder so files that
    // live together get copied together in one batch, same as a normal
    // multi-select copy from the file browser.
    final byParent = <String, List<VaultDiffEntry>>{};
    for (final e in fileEntries) {
      byParent.putIfAbsent(_parentOf(e.relativePath), () => []).add(e);
    }

    for (final group in byParent.entries) {
      final destParentAbs = _absPath(dest.relativePath, group.key);
      final items = group.value.map((e) {
        final srcAbsPath = _absPath(source.relativePath, e.relativePath);
        return ClipboardItem(
          path: srcAbsPath,
          isDir: false,
          sizeBytes: sourceIsLeft
              ? (e.leftSizeBytes ?? 0)
              : (e.rightSizeBytes ?? 0),
          modifiedSecs: sourceIsLeft
              ? (e.leftModifiedSecs ?? 0)
              : (e.rightModifiedSecs ?? 0),
        );
      }).toList();

      final conflictPlan = <String, ConflictResolution>{
        for (final e in group.value)
          e.name.toLowerCase(): ConflictResolution.overwrite,
      };

      ops.add(
        fileOperationService.enqueue(
          isCut: false,
          source: source.container,
          dest: dest.container,
          destDirPath: destParentAbs,
          items: items,
          conflictPlan: conflictPlan,
          l10n: l10n,
        ),
      );
    }

    return ops;
  }

  String _absPath(String root, String rel) {
    if (root.isEmpty) return rel;
    if (rel.isEmpty) return root;
    return '$root/$rel';
  }

  String _parentOf(String relPath) {
    final idx = relPath.lastIndexOf('/');
    return idx < 0 ? '' : relPath.substring(0, idx);
  }
}
