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
  }) {
    // FileOperation._internal() is accessible here because this file is
    // declared `part of 'file_operation.dart'`.
    final op = FileOperation._internal(
      id: _nextId++,
      isCut: isCut,
      sourceVolId: source.volId,
      sourceDisplayName: source.displayName,
      destVolId: dest.volId,
      destDisplayName: dest.displayName,
      destDirPath: destDirPath,
      items: items,
    );
    _operations.add(op);
    notifyListeners();

    _run(op, source, dest, conflictPlan ?? {});
    return op;
  }

  /// Enqueues and starts a background native import operation.
  ///
  /// [performImport] receives the new operation's [FileOperation.id] as
  /// `opId` — the caller threads it into the native `importFile`/
  /// `importFolder` call so progress pushes and [VaultExplorerApi.cancelImport]
  /// can be matched back to this operation.
  FileOperation enqueueImport({
    required MountedContainer dest,
    required String destDirPath,
    required bool isFolder,
    required Future<int> Function(int opId) performImport,
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
    );
    _operations.add(op);
    notifyListeners();

    _runImport(op, performImport);
    return op;
  }

  /// Standalone batch delete — no clipboard involved.
  /// Returns the number of items successfully deleted.
  Future<int> deleteItems({
    required MountedContainer container,
    required List<ClipboardItem> items,
    void Function(int done, int total)? onProgress,
  }) async {
    int deleted = 0;
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final ok = await _deleteEntryRecursive(container, item.path, item.isDir);
      if (ok) deleted++;
      onProgress?.call(i + 1, items.length);
    }
    return deleted;
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
    op._setActivity('Importing…');

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

    try {
      // ── Space pre-flight ────────────────────────────────────────────────
      op._setActivity('Checking available space…');

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
    : null; // destination doesn't report free space — skip the check

if (freeBytes != null && requiredBytes > (freeBytes * 0.95).floor()) {
  op._setError(
    'Not enough space — need ${formatBytes(requiredBytes)}, '
    'only ${formatBytes(freeBytes)} free',
  );
  op._setStatus(FileOperationStatus.failed);
  notifyListeners();
  return;
}

      // ── Resolve destination names ─────────────────────────────────────
      op._setActivity('Resolving conflicts…');

      final existingRaw =
          await vaultExplorerApi.listDirectory(dest, op.destDirPath) ?? [];
      if (op.cancelRequested) throw const _CancelledException();

      final existingNames = <String>{};
      final existingDirs = <String>{};
      for (final raw in existingRaw) {
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
                '${op.isCut ? "Moving" : "Copying"} ${r.item.name}…',
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
                    errorMessage: 'Move failed',
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
                    errorMessage: 'Copy failed',
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
                errorMessage: 'Disk full',
              );
              rethrow;
            } on _CancelledException {
              op._recordItemResult(
                idx,
                FileItemResult.skipped,
                errorMessage: 'Cancelled',
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
          debugPrint('FileOperationService unhandled: $e');
        }
      }

      // ── Final status ──────────────────────────────────────────────────
      final diskFull = op.itemStatuses.any(
        (s) => s.errorMessage == 'Disk full',
      );

      if (diskFull) {
        for (final path in createdDestPaths.reversed) {
          try {
            await _deleteEntryRecursive(dest, path, false);
          } catch (_) {}
        }
        op._setError('Disk full — partial files removed');
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
      vaultExplorerApi.endBatch(dest.volId);
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

Future<bool> _deleteEntryRecursive(
    MountedContainer container,
    String path,
    bool isDir,
  ) async {
    if (!isDir) {
      try {
        return await vaultExplorerApi.deleteFile(container, path);
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
        return await vaultExplorerApi.deleteFile(container, path);
      } catch (_) {
        return false;
      }
    }

    bool allOk = true;
    for (final entry in children) {
      if (entry.startsWith('System:')) continue;
      final e = RawEntry.parse(entry);
      final ok = await _deleteEntryRecursive(container, '$path/${e.name}', e.isDir);
      if (!ok) allOk = false;
    }

    try {
      final deletedSelf = await vaultExplorerApi.deleteFile(container, path);
      return deletedSelf && allOk;
    } catch (_) {
      return false;
    }
  }
}
