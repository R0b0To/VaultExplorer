library;

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Cancellation flag shared between a [VaultSyncService.scanDiff] caller
/// and its in-flight scan. Kept as its own type (rather than reusing
/// DuplicateFinderService's token) so a token from one tool can't
/// accidentally be handed to the other -- see [CancellationToken]'s doc
/// comment for the shared bool-flag implementation this delegates to.
class VaultSyncCancellationToken extends CancellationToken {}

/// Core service behind the Vault Sync / Diff tool.
///
/// Either side can be a vault, device storage, or a document-provider (SAF)
/// folder -- they all go through [VaultFileIoApi], which dispatches on the
/// container type.
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

  /// How a file present on both sides compares. Shared by the full-tree scan
  /// and the folder explorer so both always agree.
  ///
  /// SMART GUARD: files with the same size count as identical. Target
  /// storage backends / SAF / cryptors on Android often reset modification
  /// timestamps to "now" when writing, which used to make freshly synced
  /// files look "newer" on the destination and get overwritten in a loop.
  /// A size mismatch means the contents differ for certain, so the modified
  /// times then decide which side is newer.
  static VaultDiffStatus classifyFilePair(RawEntry l, RawEntry r) {
    if (l.sizeBytes == r.sizeBytes) return VaultDiffStatus.identical;
    // A modified time of 0 means the storage didn't report one (some
    // document providers don't). Guessing "newer" from a missing timestamp
    // could overwrite the wrong side, so leave it for the user to resolve.
    if (l.modifiedSecs <= 0 || r.modifiedSecs <= 0) {
      return VaultDiffStatus.conflicted;
    }
    if (l.modifiedSecs > r.modifiedSecs + _mtimeToleranceSecs) {
      return VaultDiffStatus.leftNewer;
    }
    if (r.modifiedSecs > l.modifiedSecs + _mtimeToleranceSecs) {
      return VaultDiffStatus.rightNewer;
    }
    // Different sizes but the same (or near-same) modified time.
    return VaultDiffStatus.conflicted;
  }

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
  /// [VaultSyncScanProgress.stage] of [VaultSyncScanStage.complete],
  /// [VaultSyncScanStage.cancelled] if [cancelToken] was cancelled, or
  /// [VaultSyncScanStage.failed] if a folder in a vault couldn't be read.
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
    // Set when a vault folder can't be read. Diffing against a folder that
    // merely failed to list would make every file on the other side look
    // "only on Right/Left", and Sync Now overwrites same-named files.
    String? unreadablePath;

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
      var leftThrew = false;
      var rightThrew = false;
      try {
        leftRaw = await _fileIoApi.listDirectory(
          left.container,
          _absPath(left.relativePath, relDir),
          // Raw file-system listings are cached briefly; native SAF copies
          // into them bypass that cache, so always read fresh.
          refresh: left.container.isRawLocal,
        );
      } catch (_) {
        // Device storage / document providers: unreadable on the left is
        // treated as empty, so everything on the right under this path
        // shows up as "only on Right". Vaults fail the scan instead (below).
        leftThrew = true;
      }
      if (cancelToken?.isCancelled ?? false) return;
      try {
        rightRaw = await _fileIoApi.listDirectory(
          right.container,
          _absPath(right.relativePath, relDir),
          refresh: right.container.isRawLocal,
        );
      } catch (_) {
        // Same for the right side.
        rightThrew = true;
      }
      if (cancelToken?.isCancelled ?? false) return;

      // A null/throwing listing of a vault means the folder couldn't be read
      // (a real empty folder lists as an empty array).
      final leftUnreadable =
          left.kind == VaultSyncTargetKind.vault &&
          (leftThrew || leftRaw == null);
      final rightUnreadable =
          right.kind == VaultSyncTargetKind.vault &&
          (rightThrew || rightRaw == null);
      if (leftUnreadable || rightUnreadable) {
        unreadablePath ??= relDir;
        return;
      }

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

        final status = classifyFilePair(l, r);
        if (status == VaultDiffStatus.identical) {
          identicalCount++;
          continue;
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
        if ((cancelToken?.isCancelled ?? false) || unreadablePath != null) {
          return;
        }
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

      if (unreadablePath != null) {
        controller.add(
          VaultSyncScanUpdate(
            progress: VaultSyncScanProgress(
              stage: VaultSyncScanStage.failed,
              dirsScanned: dirsScanned,
              currentPath: unreadablePath,
            ),
            entries: const [],
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
  /// folder or vice versa -- and so is anything that needs no change.
  ///
  /// The mirror directions are the only ones that ever delete: they make one
  /// side an exact copy of the other, so whatever exists only on the target
  /// side is deleted and every other difference is overwritten from the
  /// source side, whichever copy is newer.
  EntryAction defaultAction(VaultDiffEntry e, SyncDirection direction) {
    if (e.typeMismatch) return EntryAction.skip;
    switch (e.status) {
      case VaultDiffStatus.identical:
      case VaultDiffStatus.bothFolders:
        return EntryAction.skip;
      case VaultDiffStatus.onlyLeft:
        return switch (direction) {
          SyncDirection.rightToLeft => EntryAction.skip,
          SyncDirection.mirrorToLeft => EntryAction.deleteLeft,
          _ => EntryAction.copyToRight,
        };
      case VaultDiffStatus.onlyRight:
        return switch (direction) {
          SyncDirection.leftToRight => EntryAction.skip,
          SyncDirection.mirrorToRight => EntryAction.deleteRight,
          _ => EntryAction.copyToLeft,
        };
      case VaultDiffStatus.leftNewer:
        return switch (direction) {
          SyncDirection.rightToLeft => EntryAction.skip,
          SyncDirection.mirrorToLeft => EntryAction.copyToLeft,
          _ => EntryAction.copyToRight,
        };
      case VaultDiffStatus.rightNewer:
        return switch (direction) {
          SyncDirection.leftToRight => EntryAction.skip,
          SyncDirection.mirrorToRight => EntryAction.copyToRight,
          _ => EntryAction.copyToLeft,
        };
      case VaultDiffStatus.conflicted:
        return switch (direction) {
          SyncDirection.mirrorToRight => EntryAction.copyToRight,
          SyncDirection.mirrorToLeft => EntryAction.copyToLeft,
          _ => EntryAction.skip,
        };
    }
  }

  /// The sides that would receive plain files copied out of an encrypted
  /// vault, given the [actions] chosen for each diff entry.
  ///
  /// Copying from a vault to device storage or a document provider (which
  /// may be a cloud drive) leaves those files unencrypted, so callers use
  /// this to warn before a sync starts.
  List<VaultSyncSide> plaintextDestinations({
    required VaultSyncSide left,
    required VaultSyncSide right,
    required Iterable<EntryAction> actions,
  }) {
    final toRight = actions.contains(EntryAction.copyToRight);
    final toLeft = actions.contains(EntryAction.copyToLeft);
    return [
      if (toRight && left.isEncrypted && !right.isEncrypted) right,
      if (toLeft && right.isEncrypted && !left.isEncrypted) left,
    ];
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
    final deleteFromLeft = <VaultDiffEntry>[];
    final deleteFromRight = <VaultDiffEntry>[];
    for (final e in entries) {
      switch (plan[e.id] ?? EntryAction.skip) {
        case EntryAction.copyToRight:
          toRight.add(e);
        case EntryAction.copyToLeft:
          toLeft.add(e);
        case EntryAction.deleteLeft:
          deleteFromLeft.add(e);
        case EntryAction.deleteRight:
          deleteFromRight.add(e);
        case EntryAction.skip:
          break;
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
      ?deleteEntries(
        side: left,
        sideIsLeft: true,
        entries: deleteFromLeft,
        l10n: l10n,
        fileOperationService: fileOperationService,
      ),
      ?deleteEntries(
        side: right,
        sideIsLeft: false,
        entries: deleteFromRight,
        l10n: l10n,
        fileOperationService: fileOperationService,
      ),
    ];
  }

  /// Enqueues one permanent delete of [entries] from [side] through the
  /// shared [FileOperationService] queue (so progress, cancellation and the
  /// transfer button work like any other file operation). Returns null when
  /// there is nothing to delete.
  ///
  /// A folder inside another selected folder is dropped from the request --
  /// deleting the parent already removes it, and deleting it twice would
  /// report a bogus failure. Callers must check [VaultSyncSide.container]'s
  /// `readOnly` first; this method does not.
  FileOperation? deleteEntries({
    required VaultSyncSide side,
    required bool sideIsLeft,
    required List<VaultDiffEntry> entries,
    required AppLocalizations l10n,
    required FileOperationService fileOperationService,
  }) {
    final items = deleteItemsFor(side, entries, sideIsLeft: sideIsLeft);
    if (items.isEmpty) return null;
    return fileOperationService.enqueueDelete(
      container: side.container,
      items: items,
      locationLabel: side.relativePath,
      l10n: l10n,
    );
  }

  /// The [ClipboardItem]s a delete of [entries] on [side] would remove, with
  /// entries nested inside another selected folder dropped.
  ///
  /// For a type-mismatched entry (a file on one side, a folder on the other)
  /// [VaultDiffEntry.isDir] describes the left side, so the right side's type
  /// is the opposite -- the delete engine needs the real type to decide
  /// whether to recurse.
  @visibleForTesting
  List<ClipboardItem> deleteItemsFor(
    VaultSyncSide side,
    List<VaultDiffEntry> entries, {
    required bool sideIsLeft,
  }) {
    bool isDirOnSide(VaultDiffEntry e) =>
        e.typeMismatch && !sideIsLeft ? !e.isDir : e.isDir;

    final sorted = [...entries]
      ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    final kept = <VaultDiffEntry>[];
    for (final e in sorted) {
      final insideKept = kept.any(
        (k) => isDirOnSide(k) && e.relativePath.startsWith('${k.relativePath}/'),
      );
      if (!insideKept) kept.add(e);
    }
    return [
      for (final e in kept)
        ClipboardItem(
          path: _absPath(side.relativePath, e.relativePath),
          isDir: isDirOnSide(e),
        ),
    ];
  }

  /// Lists the direct children of [relDir] on both sides, merged and
  /// compared, for the folder explorer. Unlike [scanDiff] this does not
  /// recurse, and it includes entries that are already in sync
  /// ([VaultDiffStatus.identical]) and folders present on both sides
  /// ([VaultDiffStatus.bothFolders]) -- so the person can see everything,
  /// not just what differs.
  ///
  /// Like the scan, a vault folder that can't be read fails the listing
  /// ([VaultSyncFolderListing.unreadable]) instead of being shown as empty,
  /// which would make everything on the other side look one-sided.
  Future<VaultSyncFolderListing> listFolder({
    required VaultSyncSide left,
    required VaultSyncSide right,
    required String relDir,
  }) async {
    Future<List<String>?> read(VaultSyncSide side) async {
      try {
        return await _fileIoApi.listDirectory(
          side.container,
          _absPath(side.relativePath, relDir),
          refresh: side.container.isRawLocal,
        );
      } catch (_) {
        return null;
      }
    }

    final leftRaw = await read(left);
    final rightRaw = await read(right);
    if ((left.kind == VaultSyncTargetKind.vault && leftRaw == null) ||
        (right.kind == VaultSyncTargetKind.vault && rightRaw == null)) {
      return const VaultSyncFolderListing(entries: [], unreadable: true);
    }

    final leftEntries = <String, RawEntry>{
      for (final e in RawEntry.parseAll(leftRaw ?? const [])) e.name: e,
    };
    final rightEntries = <String, RawEntry>{
      for (final e in RawEntry.parseAll(rightRaw ?? const [])) e.name: e,
    };

    final entries = <VaultDiffEntry>[];
    for (final name in {...leftEntries.keys, ...rightEntries.keys}) {
      final l = leftEntries[name];
      final r = rightEntries[name];
      final fullPath = relDir.isEmpty ? name : '$relDir/$name';

      if (r == null) {
        entries.add(
          VaultDiffEntry(
            relativePath: fullPath,
            name: name,
            isDir: l!.isDir,
            status: VaultDiffStatus.onlyLeft,
            leftSizeBytes: l.isDir ? null : l.sizeBytes,
            leftModifiedSecs: l.modifiedSecs,
          ),
        );
      } else if (l == null) {
        entries.add(
          VaultDiffEntry(
            relativePath: fullPath,
            name: name,
            isDir: r.isDir,
            status: VaultDiffStatus.onlyRight,
            rightSizeBytes: r.isDir ? null : r.sizeBytes,
            rightModifiedSecs: r.modifiedSecs,
          ),
        );
      } else {
        final mismatch = l.isDir != r.isDir;
        final status = mismatch
            ? VaultDiffStatus.conflicted
            : l.isDir
            ? VaultDiffStatus.bothFolders
            : classifyFilePair(l, r);
        entries.add(
          VaultDiffEntry(
            relativePath: fullPath,
            name: name,
            isDir: l.isDir,
            status: status,
            typeMismatch: mismatch,
            leftSizeBytes: l.isDir ? null : l.sizeBytes,
            leftModifiedSecs: l.modifiedSecs,
            rightSizeBytes: r.isDir ? null : r.sizeBytes,
            rightModifiedSecs: r.modifiedSecs,
          ),
        );
      }
    }

    // Folders first, then by name, so the listing reads like a file manager.
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return VaultSyncFolderListing(entries: entries);
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

      final destCaseSensitive = namesAreCaseSensitive(dest.container);
      final conflictPlan = <String, ConflictResolution>{
        for (final e in group.value)
          foldEntryName(e.name, caseSensitive: destCaseSensitive):
              ConflictResolution.overwrite,
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
