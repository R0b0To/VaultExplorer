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
  FileOperationService._() {
    VaultExplorerApi.addImportItemFinishedListener((event) {
      final op = _operations.cast<FileOperation?>().firstWhere(
        (o) => o?.id == event.opId,
        orElse: () => null,
      );
      if (op != null) {
        op._recordImportItemFinished(
          sourceName: event.sourceName,
          resolvedName: event.resolvedName,
          isDir: event.isDir,
          success: event.success,
        );
        notifyListeners();
      }
    });
  }
  static final instance = FileOperationService._();

  static const _maxConcurrentItems = 4;
  static const _chunkSize = 2 * 1024 * 1024; // 256 KB
  static const _kNotificationThrottleDuration = Duration(milliseconds: 100);

  // ── State ─────────────────────────────────────────────────────────────────

  int _nextId = 1;
  final List<FileOperation> _operations = [];
  final Map<FileOperation, VoidCallback> _opListeners = {};

  Timer? _notificationThrottleTimer;
  DateTime? _lastNotificationPushTime;

  List<FileOperation> get operations => List.unmodifiable(_operations);

  List<FileOperation> get activeOperations => _operations
      .where(
        (op) =>
            op.status == FileOperationStatus.pending ||
            op.status == FileOperationStatus.running,
      )
      .toList();

  int get activeCount => activeOperations.length;

  /// Returns visual placeholder [RawEntry]s for all pending/running items
  /// currently being transferred into [volId] and [dirPath].
  List<RawEntry> getActivePlaceholders(int volId, String dirPath) {
    final placeholders = <RawEntry>[];
    final active = activeOperations.where(
      (op) =>
          !op.isDelete &&
          op.destVolId == volId &&
          op.destDirPath == dirPath &&
          (op.status == FileOperationStatus.pending ||
              op.status == FileOperationStatus.running),
    );
    for (final op in active) {
      for (int i = 0; i < op.items.length; i++) {
        final status = i < op.itemStatuses.length ? op.itemStatuses[i] : null;
        final result = status?.result ?? FileItemResult.pending;
        // A failed or skipped item has no file coming, so it's dropped
        // outright. A pending OR already-succeeded item keeps its
        // placeholder alive: the destination folder's own reload is
        // throttled, so if we stopped placeholder-ing the moment the
        // transfer succeeded, the item would vanish for that gap and then
        // reappear once the real listing catches up -- a visible shift.
        // Keeping the placeholder through success (now under its resolved
        // name, which is already known at that point) means the browser's
        // name-based dedup swaps it for the real entry in place, with no
        // gap and no separate re-sort.
        if (result == FileItemResult.failed ||
            result == FileItemResult.skipped) {
          continue;
        }
        final item = op.items[i];
        final name = op.resolvedDestName(i) ?? item.name;
        placeholders.add(
          RawEntry(
            name: name,
            isDir: item.isDir,
            sizeBytes: item.sizeBytes,
            // Left at 0 (rendered as "—") rather than "now": a live
            // timestamp would otherwise flip to the real, differently
            // shaped modified date the moment the real entry loads,
            // shifting the date column's width for no benefit -- nobody
            // needs a transfer-in-progress item's "date".
            modifiedSecs: 0,
            isPlaceholder: true,
          ),
        );
      }
    }
    return placeholders;
  }

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
    _bindOperationListener(op);
    notifyListeners();
    _syncNotificationProgress();
    _run(op, source, dest, conflictPlan ?? {});
    return op;
  }

  FileOperation enqueueImport({
    required MountedContainer dest,
    required String destDirPath,
    List<ClipboardItem> items = const [],
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
      items: items.isNotEmpty
          ? items
          : [
              ClipboardItem(
                path: isFolder ? 'Folder' : 'Files',
                isDir: isFolder,
                sizeBytes: 0,
              ),
            ],
      isImport: true,
      l10n: l10n,
    );
    _operations.add(op);
    _bindOperationListener(op);
    notifyListeners();
    _syncNotificationProgress();
    _runImport(op, performImport);
    return op;
  }

  /// Standalone batch delete — no clipboard involved.
  ///
  /// Creates and enqueues a tracked [FileOperation] (like [enqueue] and
  /// [enqueueImport]) so the delete shows up in [AppBarTransferButton] and
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
    _bindOperationListener(op);
    notifyListeners();
    _syncNotificationProgress();
    _runDelete(op, container);
    return op;
  }

  /// Removes operations associated with a specific volume ID (used on container lock).
  void clearForVolume(int volId) {
    final toRemove = _operations
        .where((op) => op.sourceVolId == volId || op.destVolId == volId)
        .toList();
    for (final op in toRemove) {
      _unbindOperationListener(op);
    }
    _operations.removeWhere((op) => op.sourceVolId == volId || op.destVolId == volId);
    notifyListeners();
    _syncNotificationProgress();
  }

  /// Removes completed / failed / cancelled operations from history.
  void clearFinished() {
    final toRemove = _operations
        .where(
          (op) =>
              op.status != FileOperationStatus.pending &&
              op.status != FileOperationStatus.running,
        )
        .toList();
    for (final op in toRemove) {
      _unbindOperationListener(op);
    }
    _operations.removeWhere(
      (op) =>
          op.status != FileOperationStatus.pending &&
          op.status != FileOperationStatus.running,
    );
    notifyListeners();
    _syncNotificationProgress();
  }

  /// Removes a single finished operation from history by [id]. No-op if the
  /// operation is still active (pending/running) or no longer present —
  /// callers don't need to guard against either case themselves.
  void dismiss(int id) {
    final op = _operations.cast<FileOperation?>().firstWhere(
      (o) => o?.id == id,
      orElse: () => null,
    );
    if (op == null) return;
    if (op.status == FileOperationStatus.pending ||
        op.status == FileOperationStatus.running) {
      return;
    }
    _unbindOperationListener(op);
    _operations.remove(op);
    notifyListeners();
    _syncNotificationProgress();
  }

  // ── Notification Progress Synchronization ─────────────────────────────────

  void _bindOperationListener(FileOperation op) {
    void onOpChanged() {
      _syncNotificationProgress();
    }

    op.addListener(onOpChanged);
    _opListeners[op] = onOpChanged;
  }

  void _unbindOperationListener(FileOperation op) {
    final listener = _opListeners.remove(op);
    if (listener != null) {
      op.removeListener(listener);
    }
  }

  double? _calculateAggregateProgress() {
    final active = activeOperations;
    if (active.isEmpty) return 1.0;

    int totalBytes = 0;
    int transferredBytes = 0;
    bool hasByteTracked = false;

    for (final op in active) {
      if (op.totalBytes > 0) {
        hasByteTracked = true;
        totalBytes += op.totalBytes;
        transferredBytes += op.transferredBytes;
      }
    }

    if (hasByteTracked && totalBytes > 0) {
      return (transferredBytes / totalBytes).clamp(0.0, 1.0);
    }

    final fractions = active.map((op) => op.progressFraction).toList();
    if (fractions.every((f) => f == null)) return null;

    double sum = 0;
    int count = 0;
    for (final f in fractions) {
      if (f != null) {
        sum += f;
        count++;
      }
    }
    return count > 0 ? (sum / active.length).clamp(0.0, 1.0) : null;
  }

  void _syncNotificationProgress() {
    final active = activeOperations;
    if (active.isEmpty) {
      _notificationThrottleTimer?.cancel();
      _notificationThrottleTimer = null;
      _lastNotificationPushTime = null;
      unawaited(
        vaultExplorerApi.updateBackgroundServiceProgress(
          hasActive: false,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final lastPush = _lastNotificationPushTime;
    final timeSinceLastPush = lastPush == null
        ? const Duration(seconds: 1)
        : now.difference(lastPush);

    if (timeSinceLastPush < _kNotificationThrottleDuration) {
      if (_notificationThrottleTimer == null) {
        final remaining = _kNotificationThrottleDuration - timeSinceLastPush;
        _notificationThrottleTimer = Timer(remaining, () {
          _notificationThrottleTimer = null;
          _pushNotificationProgress();
        });
      }
      return;
    }

    _notificationThrottleTimer?.cancel();
    _notificationThrottleTimer = null;
    _pushNotificationProgress();
  }

  void _pushNotificationProgress() {
    final active = activeOperations;
    if (active.isEmpty) {
      _lastNotificationPushTime = null;
      unawaited(
        vaultExplorerApi.updateBackgroundServiceProgress(
          hasActive: false,
        ),
      );
      return;
    }

    _lastNotificationPushTime = DateTime.now();

    final fraction = _calculateAggregateProgress();
    // Use a 1000x multiplier to match Kotlin's max progress resolution
    final progress = fraction != null ? (fraction * 1000).round().clamp(0, 1000) : null;
    final indeterminate = fraction == null;

    String title;
    String text;

    if (active.length == 1) {
      final op = active.first;
      title = op.shortSummary;

      final parts = <String>[];
      if (op.currentActivity.isNotEmpty && op.currentActivity != op.shortSummary) {
        parts.add(op.currentActivity);
      }
      if (op.totalBytes > 0) {
        parts.add('${formatBytes(op.transferredBytes)} / ${formatBytes(op.totalBytes)}');
        if (op.bytesPerSecond != null && op.bytesPerSecond! > 0) {
          parts.add(op.l10n.fileOpsSpeedLabel(formatBytes(op.bytesPerSecond!.round())));
        }
        if (op.estimatedTimeRemaining != null) {
          parts.add(op.l10n.fileOpsEtaLabel(formatDuration(op.estimatedTimeRemaining!)));
        }
      } else if (op.isDelete && op.removedCount > 0) {
        parts.add(op.l10n.fileOpDeletedSoFar(op.removedCount));
      } else if (op.isImport && op.totalCount > 0) {
        parts.add('${op.doneCount} / ${op.totalCount}');
      }
      text = parts.isNotEmpty ? parts.join(' · ') : op.shortSummary;
    } else {
      final l10n = active.first.l10n;
      title = l10n.fileOpsTransfersInProgressTitle;

      final parts = <String>[];
      parts.add(l10n.multiOpLabel(active.length));
      int totalBytes = 0;
      int transferredBytes = 0;
      for (final op in active) {
        if (op.totalBytes > 0) {
          totalBytes += op.totalBytes;
          transferredBytes += op.transferredBytes;
        }
      }
      if (totalBytes > 0) {
        parts.add('${formatBytes(transferredBytes)} / ${formatBytes(totalBytes)}');
      }
      text = parts.join(' · ');
    }

    unawaited(
      vaultExplorerApi.updateBackgroundServiceProgress(
        hasActive: true,
        title: title,
        text: text,
        progress: progress,
        max: 1000,
        indeterminate: indeterminate,
      ),
    );
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
        // Real per-item results already arrive live via "onImportItemFinished"
        // (see the addImportItemFinishedListener hookup in this service's
        // constructor), so by the time performImport's future resolves every
        // item passed in `items` should already be resolved. The only case
        // left unresolved here is the synthetic single-item placeholder
        // enqueueImport creates when no real `items` list was supplied --
        // native has no matching name to report a finish against, so it's
        // still pending. Guard on that instead of unconditionally
        // overwriting index 0, which would double-count (or silently flip a
        // real failure to success) whenever real items were passed.
        if (op._itemStatuses.length == 1 &&
            op._itemStatuses[0].result == FileItemResult.pending) {
          op._recordItemResult(0, FileItemResult.success);
        }
        op._setDoneCount(count);
        op._setStatus(FileOperationStatus.completed);
      } else {
        op._setStatus(FileOperationStatus.cancelled);
      }
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') {
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
      _unbindOperationListener(op);
      notifyListeners();
      _syncNotificationProgress();
    }
  }

  Future<void> _run(
    FileOperation op,
    MountedContainer src,
    MountedContainer dest,
    ConflictPlan conflictPlan,
  ) async {
    op._setStatus(FileOperationStatus.running);

    void onCopyProgress(CopyProgress p) {
      if (p.opId != op.id) return;
      op._addTransferredBytes(p.bytesDelta);
    }

    VaultExplorerApi.addCopyProgressListener(onCopyProgress);
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

      for (int i = 0; i < resolved.length; i++) {
        op._setResolvedDestName(i, resolved[i].destPath.split('/').last);
      }
      notifyListeners();

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
        if (e is! _DiskFullException && e is! _CancelledException) {}
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
      VaultExplorerApi.removeCopyProgressListener(onCopyProgress);
      await vaultExplorerApi.clearCopyState(op.id);
      await vaultExplorerApi.endBatchWrite(dest);
      vaultExplorerApi.endBatch(dest.volId);
      _unbindOperationListener(op);
      notifyListeners();
      _syncNotificationProgress();
    }
  }

  Future<void> _runDelete(FileOperation op, MountedContainer container) async {
    op._setStatus(FileOperationStatus.running);
    op._setActivity(op.l10n.fileOpDeleting);
    try {
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
      _unbindOperationListener(op);
      notifyListeners();
      _syncNotificationProgress();
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
    final copyStopwatch = Stopwatch()..start();
    var readMicros = 0;
    var writeMicros = 0;
    var chunkCount = 0;
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

      // Try fast native direct stream copy first:
      final directCopied = await vaultExplorerApi.copyFile(
        src,
        srcPath,
        dest,
        destPath,
        opId: op.id,
      );
      if (directCopied) {
        createdDestPaths.add(destPath);
        if (modifiedSecs > 0) {
          await vaultExplorerApi.setLastModifiedTime(dest, destPath, modifiedSecs);
        }
        return true;
      }

      // Fallback to chunked copy with 2 MB chunks if direct copy is unsupported:
      int offset = 0;
      while (offset < size) {
        if (op.cancelRequested) throw const _CancelledException();
        final chunkLen = min(size - offset, _chunkSize);
        final readSw = Stopwatch()..start();
        final chunk = await vaultExplorerApi.readFileChunk(
          src,
          srcPath,
          offset,
          chunkLen,
        );
        readMicros += readSw.elapsedMicroseconds;
        if (chunk == null || chunk.isEmpty) return false;
        final writeSw = Stopwatch()..start();
        final ok = await vaultExplorerApi.writeFileChunk(
          dest,
          destPath,
          offset,
          chunk,
        );
        writeMicros += writeSw.elapsedMicroseconds;
        if (!ok) throw const _DiskFullException();
        offset += chunk.length;
        chunkCount++;
        op._addTransferredBytes(chunk.length);
      }
      await vaultExplorerApi.finishWrite(dest, destPath);
      createdDestPaths.add(destPath);
      if (modifiedSecs > 0) {
        await vaultExplorerApi.setLastModifiedTime(dest, destPath, modifiedSecs);
      }
      return true;
    } catch (e) {
      if (e is _DiskFullException || e is _CancelledException) rethrow;
      return false;
    } finally {
      copyStopwatch.stop();
      if (chunkCount > 0) {
        final totalMs = copyStopwatch.elapsedMilliseconds;
        final readMs = readMicros / 1000;
        final writeMs = writeMicros / 1000;
        VeLog.d(
          'FileOperationService',
          'INTRA_VAULT_COPY dest=${VeLog.censorName(destPath.split('/').last)} '
              'chunks=$chunkCount chunkSize=$_chunkSize totalMs=$totalMs '
              'readMs=${readMs.toStringAsFixed(0)} writeMs=${writeMs.toStringAsFixed(0)} '
              'otherMs=${(totalMs - readMs - writeMs).toStringAsFixed(0)}',
        );
      }
    }
  }

  // ── Recursive delete ──────────────────────────────────────────────────────

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