// Part of the file_operation library — do not import this file directly.
// All imports, the library declaration, and the `part` directive live in
// file_operation.dart. Consumer code imports only file_operation.dart.

part of '../models/file_operation.dart';

// ── Internal exceptions ───────────────────────────────────────────────────────

class _DiskFullException implements Exception {
  const _DiskFullException();
}

class _CancelledException implements Exception {
  const _CancelledException();
}

// ── Bounded concurrency semaphore ─────────────────────────────────────────────

class _CopySemaphore {
  final int maxConcurrent;
  int _running = 0;
  final _queue = <Completer<void>>[];

  _CopySemaphore(this.maxConcurrent);

  Future<void> acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _running = (_running - 1).clamp(0, maxConcurrent);
    }
  }
}

// ── FileOperationService ──────────────────────────────────────────────────────

/// Singleton service that owns all file copy/move/delete operations.
///
/// Import `file_operation.dart` to get both this service and [FileOperation].
/// Do NOT import this file directly.
class FileOperationService extends ChangeNotifier {
  FileOperationService._();
  static final instance = FileOperationService._();

  static const _maxConcurrentItems = 4;
  static const _chunkSize = 256 * 1024; // 256 KB

  // ── State ─────────────────────────────────────────────────────────────────

  int _nextId = 1;
  final List<FileOperation> _operations = [];

  List<FileOperation> get operations => List.unmodifiable(_operations);

  List<FileOperation> get activeOperations => _operations
      .where(
        (op) =>
            op.status == FileOperationStatus.pending ||
            op.status == FileOperationStatus.running,
      )
      .toList();

  int get activeCount => activeOperations.length;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Creates and enqueues a copy/move operation, returning it immediately so
  /// callers can attach listeners or display progress.
  FileOperation enqueue({
    required bool isCut,
    required MountedContainer source,
    required MountedContainer dest,
    required String destDirPath,
    required List<ClipboardItem> items,
    ConflictPlan? conflictPlan,
    required AppLocalizations l10n,
  }) {
    final op = FileOperation._internal(
      id: _nextId++,
      isCut: isCut,
      sourceVolId: source.volId,
      sourceDisplayName: source.displayName,
      destVolId: dest.volId,
      destDisplayName: dest.displayName,
      destDirPath: destDirPath,
      items: items,
      l10n: l10n,
    );
    _operations.add(op);
    notifyListeners();
    _run(op, source, dest, conflictPlan ?? {});
    return op;
  }
  FileOperation enqueueImport({
    required MountedContainer dest,
    required String destDirPath,
    required bool isFolder,
    required Future<int> Function(int opId) performImport,
    required AppLocalizations l10n,
  }) {
    final op = FileOperation._internal(
      id: _nextId++,
      isCut: false,
      sourceVolId: 0,
      sourceDisplayName: 'Device',
      destVolId: dest.volId,
      destDisplayName: dest.displayName,
      destDirPath: destDirPath,
      items: [
        ClipboardItem(
          path: isFolder ? 'Folder' : 'Files',
          isDir: isFolder,
          sizeBytes: 0,
        )
      ],
      isImport: true,
      l10n: l10n,
    );
    _operations.add(op);
    notifyListeners();
    _runImport(op, performImport);
    return op;
  }

  /// Standalone batch delete — no clipboard involved.
  ///
  /// Creates and enqueues a tracked [FileOperation] (like [enqueue] and
  /// [enqueueImport]) so the delete shows up in [OperationActivityPill] and
  /// the file operations sheet instead of running silently. This matters
  /// most for slow, block-encrypted backends like cryFS, where deleting a
  /// large folder can take long enough that, without any visible progress,
  /// it can look like the app has frozen.
  ///
  /// [locationLabel] is shown in the operations sheet as where the delete
  /// is happening (e.g. the folder it was triggered from) — purely
  /// cosmetic, pass '' to fall back to a generic label.
  FileOperation enqueueDelete({
    required MountedContainer container,
    required List<ClipboardItem> items,
    String locationLabel = '',
    required AppLocalizations l10n,
  }) {
    final op = FileOperation._internal(
      id: _nextId++,
      isCut: false,
      sourceVolId: container.volId,
      sourceDisplayName: container.displayName,
      destVolId: container.volId,
      destDisplayName: container.displayName,
      destDirPath: locationLabel,
      items: items,
      isDelete: true,
      l10n: l10n,
    );
    _operations.add(op);
    notifyListeners();
    _runDelete(op, container);
    return op;
  }

  /// Removes operations associated with a specific volume ID (used on container lock).
  void clearForVolume(int volId) {
    _operations.removeWhere((op) => op.sourceVolId == volId || op.destVolId == volId);
    notifyListeners();
  }

  /// Removes completed / failed / cancelled operations from history.
  void clearFinished() {
    _operations.removeWhere(
      (op) =>
          op.status != FileOperationStatus.pending &&
          op.status != FileOperationStatus.running,
    );
    notifyListeners();
  }

  // ── Size measurement (public — used by the screen for pre-flight UI) ──────

  Future<int> measureTreeBytes(
    MountedContainer container,
    String dirPath,
  ) async {
    int total = 0;
    final entries =
        await vaultExplorerApi.listDirectory(container, dirPath) ?? [];
    for (final entry in entries) {
      if (entry.startsWith('System:')) continue;
      final e = RawEntry.parse(entry);
      if (e.isDir) {
        total += await measureTreeBytes(container, '$dirPath/${e.name}');
      } else {
        total += e.sizeBytes;
      }
    }
    return total;
  }

  Future<int> measureItemBytes(
    MountedContainer container,
    ClipboardItem item,
  ) async {
    if (!item.isDir) {
      return item.sizeBytes > 0
          ? item.sizeBytes
          : vaultExplorerApi.getFileSize(container, item.path);
    }
    return measureTreeBytes(container, item.path);
  }

  // ── Unique-name helper ────────────────────────────────────────────────────

  static String makeUniqueName(String fileName, Set<String> existingNames) {
    if (!existingNames.contains(fileName.toLowerCase())) return fileName;
    final dotIdx = fileName.lastIndexOf('.');
    final stem = dotIdx != -1 ? fileName.substring(0, dotIdx) : fileName;
    final ext = dotIdx != -1 ? fileName.substring(dotIdx) : '';
    for (int i = 1; i < 9999; i++) {
      final candidate = '$stem ($i)$ext';
      if (!existingNames.contains(candidate.toLowerCase())) return candidate;
    }
    return '$fileName-${DateTime.now().millisecondsSinceEpoch}';
  }

  // ── Operation runner ──────────────────────────────────────────────────────

  Future<void> _runImport(
    FileOperation op,
    Future<int> Function(int opId) performImport,
  ) async {
    op._setStatus(FileOperationStatus.running);
    op._setActivity(op.l10n.fileOpImporting);

void onProgress(ImportProgress p) {
      if (p.opId != op.id) return;
      op._setImportProgress(
        done: p.done,
        total: p.total,
        currentName: p.currentName,
        transferredBytes: p.transferredBytes,
        totalBytes: p.totalBytes,
      );
    }

    VaultExplorerApi.addImportProgressListener(onProgress);
    try {
      final count = await performImport(op.id);
      if (count > 0) {
        op._recordItemResult(0, FileItemResult.success);
        op._setDoneCount(count);
        op._setStatus(FileOperationStatus.completed);
      } else {
        op._setStatus(FileOperationStatus.cancelled);
      }
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') {
        // Native noticed op.requestCancel()'s cancelImport() call. Files
        // written before that point stay put — keep whatever _importDone
        // reached as the final count rather than reporting a fail/blank.
        op._setDoneCount(op._importDone);
        op._setStatus(FileOperationStatus.cancelled);
      } else {
        op._setError(e.message ?? e.toString());
        op._setStatus(FileOperationStatus.failed);
      }
    } catch (e) {
      op._setError(e.toString());
      op._setStatus(FileOperationStatus.failed);
    } finally {
      VaultExplorerApi.removeImportProgressListener(onProgress);
      notifyListeners();
    }
  }

  Future<void> _run(
    FileOperation op,
    MountedContainer src,
    MountedContainer dest,
    ConflictPlan conflictPlan,
  ) async {
    // _setStatus / _setActivity / etc. are accessible because this file is
    // part of the same library as FileOperation.
    op._setStatus(FileOperationStatus.running);
    vaultExplorerApi.beginBatch(dest.volId);
    await vaultExplorerApi.beginBatchWrite(dest);
    try {
      op._setActivity(op.l10n.fileOpCheckingSpace);
      int requiredBytes = 0;
if (!(op.isCut && src.volId == dest.volId)) {
        for (final item in op.items) {
          requiredBytes += await measureItemBytes(src, item);
          if (op.cancelRequested) throw const _CancelledException();
        }
      }
      op._setTotalBytes(requiredBytes);
final spaceInfo = await vaultExplorerApi.getSpaceInfo(dest);
final freeBytes = (spaceInfo != null && spaceInfo.length > 1 && spaceInfo[1] >= 0)
    ? spaceInfo[1]
    : null;
if (freeBytes != null && requiredBytes > (freeBytes * 0.95).floor()) {
  op._setError(
    op.l10n.fileOpNotEnoughSpace(
      formatBytes(requiredBytes),
      formatBytes(freeBytes),
    ),
  );
  op._setStatus(FileOperationStatus.failed);
  notifyListeners();
  return;
}
      op._setActivity(op.l10n.fileOpResolvingConflicts);

      final existingRaw =
          await vaultExplorerApi.listDirectory(dest, op.destDirPath) ?? [];
      if (op.cancelRequested) throw const _CancelledException();

      final existingNames = <String>{};
      final existingDirs = <String>{};
      for (final raw in existingRaw) {
        if (raw.startsWith('System:')) continue;
        final e = RawEntry.parse(raw);
        existingNames.add(e.name.toLowerCase());
        if (e.isDir) existingDirs.add(e.name.toLowerCase());
      }

      // Pair each item with its resolved destination path.
      final resolved = <({ClipboardItem item, String destPath, bool skip})>[];

      for (final item in op.items) {
        final fileName = item.name;
        String destPath = op.destDirPath.isEmpty
            ? fileName
            : '${op.destDirPath}/$fileName';

        // Same location → skip.
        if (src.volId == dest.volId && item.path == destPath) {
          resolved.add((item: item, destPath: destPath, skip: true));
          continue;
        }
        // Moving a dir into itself → skip.
        if (src.volId == dest.volId &&
            item.isDir &&
            destPath.startsWith('${item.path}/')) {
          resolved.add((item: item, destPath: destPath, skip: true));
          continue;
        }

        if (existingNames.contains(fileName.toLowerCase())) {
          final resolution =
              conflictPlan[fileName.toLowerCase()] ??
              ConflictResolution.keepBoth;

          switch (resolution) {
            case ConflictResolution.skip:
              resolved.add((item: item, destPath: destPath, skip: true));
              continue;
            case ConflictResolution.overwrite:
              if (op.isCut) {
                await _deleteEntryRecursive(
                  dest,
                  destPath,
                  existingDirs.contains(fileName.toLowerCase()),
                );
              }
            case ConflictResolution.keepBoth:
              final unique = makeUniqueName(fileName, existingNames);
              existingNames.add(unique.toLowerCase());
              destPath = op.destDirPath.isEmpty
                  ? unique
                  : '${op.destDirPath}/$unique';
          }
        }

        resolved.add((item: item, destPath: destPath, skip: false));
      }

      // ── Parallel copy ─────────────────────────────────────────────────
      final semaphore = _CopySemaphore(_maxConcurrentItems);
      final createdDestPaths = <String>[];

      try {
        await Future.wait(
          resolved.asMap().entries.map((entry) async {
            final idx = entry.key;
            final r = entry.value;

            await semaphore.acquire();
            try {
              if (op.cancelRequested) throw const _CancelledException();

              if (r.skip) {
                op._recordItemResult(idx, FileItemResult.skipped);
                return;
              }

             op._setActivity(
                op.isCut
                    ? op.l10n.fileOpMovingName(r.item.name)
                    : op.l10n.fileOpCopyingName(r.item.name),
              );
              bool ok = false;
              if (op.isCut && src.volId == dest.volId) {
                ok = await vaultExplorerApi.renameFile(
                  src,
                  r.item.path,
                  r.destPath,
                );
                if (!ok) {
                  op._recordItemResult(
                    idx,
                    FileItemResult.failed,
                    errorMessage: op.l10n.fileOpMoveFailed,
                  );
                } else {
                  op._recordItemResult(idx, FileItemResult.success);
                }
              } else {
                ok = await _copyEntry(
                  src,
                  dest,
                  r.item.path,
                  r.destPath,
                  r.item.isDir,
                  createdDestPaths,
                  op,
                  r.item.modifiedSecs,
                );
                if (!ok) {
                  op._recordItemResult(
                    idx,
                    FileItemResult.failed,
                    errorMessage: op.l10n.fileOpCopyFailed,
                  );
                } else if (op.isCut) {
                  await _deleteEntryRecursive(src, r.item.path, r.item.isDir);
                  op._recordItemResult(idx, FileItemResult.success);
                } else {
                  op._recordItemResult(idx, FileItemResult.success);
                }
              }
            } on _DiskFullException {
              op._recordItemResult(
                idx,
                FileItemResult.failed,
                errorMessage: op.l10n.fileOpDiskFull,
              );
              rethrow;
            } on _CancelledException {
              op._recordItemResult(
                idx,
                FileItemResult.skipped,
                errorMessage: op.l10n.statusCancelled,
              );
              rethrow;
            } catch (e) {
              op._recordItemResult(
                idx,
                FileItemResult.failed,
                errorMessage: e.toString(),
              );
            } finally {
              semaphore.release();
            }
          }),
        );
      } catch (e) {
        if (e is! _DiskFullException && e is! _CancelledException) {

        }
      }
      final diskFull = op.itemStatuses.any(
        (s) => s.errorMessage == 'Disk full' || s.errorMessage == op.l10n.fileOpDiskFull,
      );
      if (diskFull) {
        for (final path in createdDestPaths.reversed) {
          try {
            await _deleteEntryRecursive(dest, path, false);
          } catch (_) {}
        }
        op._setError(op.l10n.fileOpDiskFullPartialRemoved);
        op._setStatus(FileOperationStatus.diskFull);
      } else if (op.cancelRequested) {
        op._setStatus(FileOperationStatus.cancelled);
      } else if (op.failCount > 0) {
        op._setStatus(FileOperationStatus.completedWithErrors);
      } else {
        op._setStatus(FileOperationStatus.completed);
      }
    } on _CancelledException {
      op._setStatus(FileOperationStatus.cancelled);
    } on _DiskFullException {
      if (op.status != FileOperationStatus.diskFull) {
        op._setStatus(FileOperationStatus.diskFull);
      }
    } catch (e) {
      op._setError(e.toString());
      op._setStatus(FileOperationStatus.failed);
    } finally {
      await vaultExplorerApi.endBatchWrite(dest);
      vaultExplorerApi.endBatch(dest.volId);
      notifyListeners();
    }
  }

  Future<void> _runDelete(FileOperation op, MountedContainer container) async {
    op._setStatus(FileOperationStatus.running);
    op._setActivity(op.l10n.fileOpDeleting);
    try {
      // Sequential, not parallel like copy's semaphore: deletion on a
      // block-encrypted volume (e.g. cryFS) is already bound by the
      // underlying crypto/IO work per block, and running several tree
      // deletes at once against the same volume risks contention rather
      // than a real speedup.
      for (int i = 0; i < op.items.length; i++) {
        if (op.cancelRequested) {
          op._recordItemResult(i, FileItemResult.skipped);
          continue;
        }
        final item = op.items[i];
        bool ok;
        try {
          ok = await _deleteEntryRecursive(
            container,
            item.path,
            item.isDir,
            op: op,
          );
        } on _CancelledException {
          op._recordItemResult(i, FileItemResult.skipped);
          continue;
        }
        op._recordItemResult(
          i,
          ok ? FileItemResult.success : FileItemResult.failed,
          errorMessage: ok ? null : op.l10n.fileOpDeleteFailed,
        );
      }
      if (op.cancelRequested) {
        op._setStatus(FileOperationStatus.cancelled);
      } else if (op.failCount > 0) {
        op._setStatus(FileOperationStatus.completedWithErrors);
      } else {
        op._setStatus(FileOperationStatus.completed);
      }
    } on _CancelledException {
      op._setStatus(FileOperationStatus.cancelled);
    } catch (e) {
      op._setError(e.toString());
      op._setStatus(FileOperationStatus.failed);
    } finally {
      notifyListeners();
    }
  }

  // ── Recursive copy ────────────────────────────────────────────────────────

  Future<bool> _copyEntry(
    MountedContainer src,
    MountedContainer dest,
    String srcPath,
    String destPath,
    bool isDir,
    List<String> createdDestPaths,
    FileOperation op,
    int modifiedSecs,
  ) async {
    if (op.cancelRequested) throw const _CancelledException();

    if (!isDir) {
      return _copyFile(src, dest, srcPath, destPath, createdDestPaths, op, modifiedSecs);
    }

    final children = await vaultExplorerApi.listDirectory(src, srcPath) ?? [];
    await vaultExplorerApi.createDirectory(dest, destPath);
    createdDestPaths.add(destPath);
    if (modifiedSecs > 0) {
      await vaultExplorerApi.setLastModifiedTime(dest, destPath, modifiedSecs);
    }

    bool allOk = true;
    for (final entry in children) {
      if (entry.startsWith('System:')) continue;
      // Always use RawEntry.parse() — never entry.split('|').first.
      final e = RawEntry.parse(entry);
      final ok = await _copyEntry(
        src,
        dest,
        '$srcPath/${e.name}',
        '$destPath/${e.name}',
        e.isDir,
        createdDestPaths,
        op,
        e.modifiedSecs,
      );
      if (!ok) allOk = false;
    }
    return allOk;
  }

  Future<bool> _copyFile(
    MountedContainer src,
    MountedContainer dest,
    String srcPath,
    String destPath,
    List<String> createdDestPaths,
    FileOperation op,
    int modifiedSecs,
  ) async {
    op._setActivity(
      op.isCut
          ? op.l10n.fileOpMovingName(destPath.split('/').last)
          : op.l10n.fileOpCopyingName(destPath.split('/').last),
    );
    try {
      final size = await vaultExplorerApi.getFileSize(src, srcPath);
      if (size < 0) return false;

      await vaultExplorerApi.deleteFile(dest, destPath);

      if (size == 0) {
        final ok = await vaultExplorerApi.createEmptyFile(dest, destPath);
        if (ok) {
          createdDestPaths.add(destPath);
          if (modifiedSecs > 0) {
            await vaultExplorerApi.setLastModifiedTime(dest, destPath, modifiedSecs);
          }
        }
        return ok;
      }

      int offset = 0;
while (offset < size) {
  if (op.cancelRequested) throw const _CancelledException();
  final chunkLen = min(size - offset, _chunkSize);
  final chunk = await vaultExplorerApi.readFileChunk(
    src,
    srcPath,
    offset,
    chunkLen,
  );
  if (chunk == null || chunk.isEmpty) return false;
final ok = await vaultExplorerApi.writeFileChunk(
          dest,
          destPath,
          offset,
          chunk,
        );
        if (!ok) throw const _DiskFullException();
        offset += chunk.length;
        op._addTransferredBytes(chunk.length);
      }
      await vaultExplorerApi.finishWriteIfCryptomator(dest, destPath);
      createdDestPaths.add(destPath);
      if (modifiedSecs > 0) {
        await vaultExplorerApi.setLastModifiedTime(dest, destPath, modifiedSecs);
      }
      return true;
    } catch (e) {
      if (e is _DiskFullException || e is _CancelledException) rethrow;
      return false;
    }
  }

  // ── Recursive delete ──────────────────────────────────────────────────────

  /// [op] is optional: when a tracked [FileOperation] is driving this delete
  /// (see [_runDelete]), every entry actually removed is reported back to
  /// it — this is what lets the pill keep showing live progress ("Deleting
  /// <name>…", a running count) instead of going silent for the whole
  /// recursive walk. Internal callers (conflict-overwrite, disk-full
  /// rollback) pass no op and just get the plain recursive delete.
  Future<bool> _deleteEntryRecursive(
    MountedContainer container,
    String path,
    bool isDir, {
    FileOperation? op,
  }) async {
    if (op != null && op.cancelRequested) throw const _CancelledException();
    if (!isDir) {
      try {
        final ok = await vaultExplorerApi.deleteFile(container, path);
        if (ok) op?._recordDeletedEntry(path.split('/').last);
        return ok;
      } catch (_) {
        return false;
      }
    }

    List<String> children;
    try {
      children = await vaultExplorerApi.listDirectory(container, path) ?? [];
    } catch (_) {
      // A corrupted/undecryptable entry inside this folder can make
      // listing throw instead of returning. Don't let that abort the
      // whole batch delete — just try to remove this node itself and
      // report accordingly.
      try {
        final ok = await vaultExplorerApi.deleteFile(container, path);
        if (ok) op?._recordDeletedEntry(path.split('/').last);
        return ok;
      } catch (_) {
        return false;
      }
    }

    bool allOk = true;
    for (final entry in children) {
      if (entry.startsWith('System:')) continue;
      final e = RawEntry.parse(entry);
      final ok = await _deleteEntryRecursive(container, '$path/${e.name}', e.isDir, op: op);
      if (!ok) allOk = false;
    }

    try {
      final deletedSelf = await vaultExplorerApi.deleteFile(container, path);
      if (deletedSelf) op?._recordDeletedEntry(path.split('/').last);
      return deletedSelf && allOk;
    } catch (_) {
      return false;
    }
  }
}