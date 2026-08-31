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

/// Long-lived service that owns all file copy/move/delete operations.
///
/// Import `file_operation.dart` to get both this service and [FileOperation].
/// Do NOT import this file directly.
class FileOperationService extends ChangeNotifier {
  FileOperationService._(
    this._engineEvents,
    this._fileIoApi,
    this._lifecycleApi,
  ) {
    _engineEvents.addImportItemFinishedListener((event) {
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
    _engineEvents.addExportItemFinishedListener((event) {
      final op = _operations.cast<FileOperation?>().firstWhere(
        (o) => o?.id == event.opId,
        orElse: () => null,
      );
      if (op != null) {
        op._recordExportItemFinished(
          sourceName: event.sourceName,
          success: event.success,
        );
        notifyListeners();
      }
    });
  }
  static const _legacyEngineChannel = MethodChannel(
    'com.aeidolon.vaultexplorer/engine',
  );

  /// Transitional compatibility for consumers outside the Riverpod graph.
  /// New code should resolve [fileOperationServiceProvider].
  FileOperationService.withEngineEvents(VaultEngineEvents engineEvents)
    : this._(
        engineEvents,
        VaultFileIoApi(_legacyEngineChannel),
        VaultLifecycleApi(_legacyEngineChannel, engineEvents),
      );

  FileOperationService.withEngineApis({
    required VaultEngineEvents engineEvents,
    required VaultFileIoApi fileIoApi,
    required VaultLifecycleApi lifecycleApi,
  }) : this._(engineEvents, fileIoApi, lifecycleApi);

  final VaultEngineEvents _engineEvents;
  final VaultFileIoApi _fileIoApi;
  final VaultLifecycleApi _lifecycleApi;

  Future<void> _cancelNativeOperation(
    int operationId,
    bool isImport,
    bool isExport,
  ) {
    if (isImport) return _fileIoApi.cancelImport(operationId);
    if (isExport) return _fileIoApi.cancelExport(operationId);
    return _fileIoApi.cancelCopy(operationId);
  }

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
    // Keep placeholders active through 'completed' state until the directory reload
    // finishes and dismisses the operation, preventing items from blinking out of view.
    final active = _operations.where(
      (op) =>
          !op.isDelete &&
          op.destVolId == volId &&
          op.destDirPath == dirPath &&
          op.status != FileOperationStatus.cancelled &&
          op.status != FileOperationStatus.failed,
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

  /// Returns a set of lowercased item names currently being deleted from
  /// [volId] and [dirPath], allowing the directory view to optimistically
  /// filter them out in a single frame instead of shifting item-by-item.
  Set<String> getPendingDeletedNames(int volId, String dirPath) {
    final deletedNames = <String>{};
    // Keep filtering pending, running, AND completed operations until they are dismissed,
    // preventing the deleted items from flickering back on screen before the directory reloads.
    final activeDeletes = _operations.where(
      (op) =>
          op.isDelete &&
          op.sourceVolId == volId &&
          op.status != FileOperationStatus.cancelled &&
          op.status != FileOperationStatus.failed,
    );

    final normalizedDir = dirPath.trim().replaceAll(r'\', '/');
    final cleanDir = normalizedDir.startsWith('/')
        ? normalizedDir.substring(1)
        : normalizedDir;

    for (final op in activeDeletes) {
      for (int i = 0; i < op.items.length; i++) {
        final status = i < op.itemStatuses.length ? op.itemStatuses[i] : null;
        final result = status?.result ?? FileItemResult.pending;
        if (result == FileItemResult.failed) continue;

        final item = op.items[i];
        final itemPath = item.path.replaceAll(r'\', '/');
        final cleanItemPath = itemPath.startsWith('/')
            ? itemPath.substring(1)
            : itemPath;

        final lastSlash = cleanItemPath.lastIndexOf('/');
        final itemParent = lastSlash != -1
            ? cleanItemPath.substring(0, lastSlash)
            : '';
        final itemName = lastSlash != -1
            ? cleanItemPath.substring(lastSlash + 1)
            : cleanItemPath;

        if (itemParent == cleanDir) {
          deletedNames.add(itemName.toLowerCase());
        }
      }
    }
    return deletedNames;
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
      cancelNativeOperation: _cancelNativeOperation,
    );
    _operations.add(op);
    _bindOperationListener(op);
    notifyListeners();
    _syncNotificationProgress();
    _run(op, source, dest, conflictPlan ?? {});
    return op;
  }

  /// Local-storage counterpart to [enqueue]: same [FileOperation] progress
  /// tracking, [ClipboardItem] model, and conflict-resolution flow as a
  /// regular container-to-container copy/move, but for a transfer that's
  /// entirely within local phone storage ([source] and [dest] both carry
  /// [kDecoyLocalVolId]). There's no encrypted container on either end, so
  /// [_runLocal] performs plain dart:io I/O instead of the native
  /// chunked-copy path [_run] uses.
  FileOperation enqueueLocalTransfer({
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
      cancelNativeOperation: _cancelNativeOperation,
    );
    _operations.add(op);
    _bindOperationListener(op);
    notifyListeners();
    _syncNotificationProgress();
    _runLocal(op, conflictPlan ?? {});
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
      cancelNativeOperation: _cancelNativeOperation,
    );
    _operations.add(op);
    _bindOperationListener(op);
    notifyListeners();
    _syncNotificationProgress();
    _runImport(op, performImport);
    return op;
  }

  /// Export counterpart to [enqueueImport]: multi-item export-to-folder is
  /// also a single opaque native call (see ImportExportHandlers.kt's
  /// handleExportFilesFolder), so it's tracked the same way -- progress
  /// streams in via "onExportProgress"/"onExportItemFinished" instead of a
  /// Dart-driven per-item loop. Unlike import, [items] is always the real
  /// selection from the file browser (never a synthetic placeholder),
  /// since the source-side metadata is already known before the native
  /// call starts.
  FileOperation enqueueExport({
    required MountedContainer source,
    required List<ClipboardItem> items,
    required Future<int> Function(int opId) performExport,
    required AppLocalizations l10n,
  }) {
    final op = FileOperation._internal(
      id: _nextId++,
      isCut: false,
      sourceVolId: source.volId,
      sourceDisplayName: source.displayName,
      destVolId: 0,
      destDisplayName: 'Device',
      destDirPath: '',
      items: items,
      isExport: true,
      l10n: l10n,
      cancelNativeOperation: _cancelNativeOperation,
    );
    _operations.add(op);
    _bindOperationListener(op);
    notifyListeners();
    _syncNotificationProgress();
    _runExport(op, performExport);
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
      cancelNativeOperation: _cancelNativeOperation,
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
    _operations.removeWhere(
      (op) => op.sourceVolId == volId || op.destVolId == volId,
    );
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
        _lifecycleApi.updateBackgroundServiceProgress(hasActive: false),
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
        _lifecycleApi.updateBackgroundServiceProgress(hasActive: false),
      );
      return;
    }

    _lastNotificationPushTime = DateTime.now();

    final fraction = _calculateAggregateProgress();
    // Use a 1000x multiplier to match Kotlin's max progress resolution
    final progress = fraction != null
        ? (fraction * 1000).round().clamp(0, 1000)
        : null;
    final indeterminate = fraction == null;

    String title;
    String text;

    if (active.length == 1) {
      final op = active.first;
      title = op.shortSummary;

      final parts = <String>[];
      if (op.currentActivity.isNotEmpty &&
          op.currentActivity != op.shortSummary) {
        parts.add(op.currentActivity);
      }
      if (op.totalBytes > 0) {
        parts.add(
          '${formatBytes(op.transferredBytes)} / ${formatBytes(op.totalBytes)}',
        );
        if (op.bytesPerSecond != null && op.bytesPerSecond! > 0) {
          parts.add(
            op.l10n.fileOpsSpeedLabel(formatBytes(op.bytesPerSecond!.round())),
          );
        }
        if (op.estimatedTimeRemaining != null) {
          parts.add(
            op.l10n.fileOpsEtaLabel(formatDuration(op.estimatedTimeRemaining!)),
          );
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
        parts.add(
          '${formatBytes(transferredBytes)} / ${formatBytes(totalBytes)}',
        );
      }
      text = parts.join(' · ');
    }

    unawaited(
      _lifecycleApi.updateBackgroundServiceProgress(
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
    final entries = await _fileIoApi.listDirectory(container, dirPath) ?? [];
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
          : _fileIoApi.getFileSize(container, item.path);
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

    _engineEvents.addImportProgressListener(onProgress);
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
      _engineEvents.removeImportProgressListener(onProgress);
      _unbindOperationListener(op);
      notifyListeners();
      _syncNotificationProgress();
    }
  }

  /// Export counterpart to [_runImport]. See that method's comments for
  /// the shared reasoning; differences are called out below.
  Future<void> _runExport(
    FileOperation op,
    Future<int> Function(int opId) performExport,
  ) async {
    op._setStatus(FileOperationStatus.running);
    op._setActivity(op.l10n.fileOpExporting);

    void onProgress(ExportProgress p) {
      if (p.opId != op.id) return;
      op._setImportProgress(
        done: p.done,
        total: p.total,
        currentName: p.currentName,
        transferredBytes: p.transferredBytes,
        totalBytes: p.totalBytes,
      );
    }

    _engineEvents.addExportProgressListener(onProgress);
    try {
      final count = await performExport(op.id);
      if (count > 0) {
        if (op._itemStatuses.length == 1 &&
            op._itemStatuses[0].result == FileItemResult.pending) {
          op._recordItemResult(0, FileItemResult.success);
        }
        op._setDoneCount(count);
        // Unlike import, a partial export (some items failed) is common
        // enough (permission errors, disk full mid-way on the SAF side)
        // to distinguish from a fully clean run.
        op._setStatus(
          op.failCount > 0
              ? FileOperationStatus.completedWithErrors
              : FileOperationStatus.completed,
        );
      } else if (op.cancelRequested) {
        op._setStatus(FileOperationStatus.cancelled);
      } else if (op._itemStatuses.isNotEmpty &&
          op._itemStatuses.every((s) => s.result == FileItemResult.failed)) {
        // Every item was attempted (the destination picker wasn't
        // dismissed) but none succeeded -- distinct from the picker
        // simply being backed out of, which also returns count == 0 but
        // leaves every item still pending.
        op._setDoneCount(0);
        op._setStatus(FileOperationStatus.completedWithErrors);
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
      _engineEvents.removeExportProgressListener(onProgress);
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

    _engineEvents.addCopyProgressListener(onCopyProgress);
    _engineEvents.beginBatch(dest.volId);
    await _fileIoApi.beginBatchWrite(dest);
    try {
      // Fetched up front (rather than after the space check) because the
      // required-bytes estimate below needs to know which items land on a
      // directory-vs-directory overwrite conflict: those go through the
      // merge path further down and need real byte headroom even for an
      // otherwise-free same-volume move -- see the mergeOverwrite comment
      // in the conflict-resolution loop.
      op._setActivity(op.l10n.fileOpResolvingConflicts);
      final existingRaw =
          await _fileIoApi.listDirectory(dest, op.destDirPath) ?? [];
      if (op.cancelRequested) throw const _CancelledException();

      final existingNames = <String>{};
      final existingDirs = <String>{};
      for (final raw in existingRaw) {
        if (raw.startsWith('System:')) continue;
        final e = RawEntry.parse(raw);
        existingNames.add(e.name.toLowerCase());
        if (e.isDir) existingDirs.add(e.name.toLowerCase());
      }

      bool needsRealCopy(ClipboardItem item) {
        if (!(op.isCut && src.volId == dest.volId)) return true;
        if (!item.isDir) return false;
        if (!existingNames.contains(item.name.toLowerCase())) return false;
        if (!existingDirs.contains(item.name.toLowerCase())) return false;
        final resolution =
            conflictPlan[item.name.toLowerCase()] ??
            ConflictResolution.keepBoth;
        return resolution == ConflictResolution.overwrite;
      }

      op._setActivity(op.l10n.fileOpCheckingSpace);
      int requiredBytes = 0;
      for (final item in op.items) {
        if (!needsRealCopy(item)) continue;
        requiredBytes += await measureItemBytes(src, item);
        if (op.cancelRequested) throw const _CancelledException();
      }
      op._setTotalBytes(requiredBytes);
      final spaceInfo = await _fileIoApi.getSpaceInfo(dest);
      final freeBytes =
          (spaceInfo != null && spaceInfo.length > 1 && spaceInfo[1] >= 0)
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

      // Pair each item with its resolved destination path.
      final resolved =
          <
            ({
              ClipboardItem item,
              String destPath,
              bool skip,
              bool mergeOverwrite,
            })
          >[];

      for (final item in op.items) {
        final fileName = item.name;
        String destPath = op.destDirPath.isEmpty
            ? fileName
            : '${op.destDirPath}/$fileName';

        // Same location → skip.
        if (src.volId == dest.volId && item.path == destPath) {
          resolved.add((
            item: item,
            destPath: destPath,
            skip: true,
            mergeOverwrite: false,
          ));
          continue;
        }
        // Moving a dir into itself → skip.
        if (src.volId == dest.volId &&
            item.isDir &&
            destPath.startsWith('${item.path}/')) {
          resolved.add((
            item: item,
            destPath: destPath,
            skip: true,
            mergeOverwrite: false,
          ));
          continue;
        }

        bool mergeOverwrite = false;
        if (existingNames.contains(fileName.toLowerCase())) {
          final resolution =
              conflictPlan[fileName.toLowerCase()] ??
              ConflictResolution.keepBoth;
          final destIsDir = existingDirs.contains(fileName.toLowerCase());

          switch (resolution) {
            case ConflictResolution.skip:
              resolved.add((
                item: item,
                destPath: destPath,
                skip: true,
                mergeOverwrite: false,
              ));
              continue;
            case ConflictResolution.overwrite:
              if (op.isCut && item.isDir && destIsDir) {
                // Both sides are directories: recursively wiping the
                // destination here (like the file case below) would delete
                // every file already in it before the incoming folder lands,
                // so if the move that follows doesn't restore an identical
                // set, that content is gone for good. Instead, leave the
                // destination folder in place and merge into it via the
                // per-file copy-then-delete-source path below, which only
                // overwrites the names that actually collide -- the same
                // merge behavior a plain (non-cut) overwrite already gets.
                mergeOverwrite = true;
              } else if (op.isCut) {
                await _deleteEntryRecursive(dest, destPath, destIsDir);
              }
            case ConflictResolution.keepBoth:
              final unique = makeUniqueName(fileName, existingNames);
              existingNames.add(unique.toLowerCase());
              destPath = op.destDirPath.isEmpty
                  ? unique
                  : '${op.destDirPath}/$unique';
          }
        }

        resolved.add((
          item: item,
          destPath: destPath,
          skip: false,
          mergeOverwrite: mergeOverwrite,
        ));
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
              // mergeOverwrite items always go through the copy-then-
              // delete-source path below, even on a same-volume cut: a
              // flat rename can't merge two directories that both already
              // have content, only replace one with the other.
              if (op.isCut && src.volId == dest.volId && !r.mergeOverwrite) {
                ok = await _fileIoApi.renameFile(src, r.item.path, r.destPath);
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
        // Every per-item task above already catches its own exceptions and
        // records a per-item result, rethrowing only the two sentinels that
        // short-circuit the whole batch. Anything else reaching here means a
        // task escaped that handling — that's a bug elsewhere, not an
        // expected outcome, so it's worth knowing about even though there's
        // nothing more useful to do with it at this point in the batch.
        if (e is! _DiskFullException && e is! _CancelledException) {
          VeLog.e(
            'FileOperationService',
            'Unexpected exception escaped batch item handling',
            e,
          );
        }
      }
      final diskFull = op.itemStatuses.any(
        (s) =>
            s.errorMessage == 'Disk full' ||
            s.errorMessage == op.l10n.fileOpDiskFull,
      );
      if (diskFull) {
        for (final path in createdDestPaths.reversed) {
          try {
            await _deleteEntryRecursive(dest, path, false);
          } catch (e) {
            // Best-effort rollback of a partial disk-full write. If this
            // fails too, the user is told partial files were removed when
            // some may not have been -- worth logging so it's diagnosable.
            VeLog.e(
              'FileOperationService',
              'Disk-full rollback: failed to remove partial entry ${VeLog.censorUri(path)}',
              e,
            );
          }
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
      _engineEvents.removeCopyProgressListener(onCopyProgress);
      await _fileIoApi.clearCopyState(op.id);
      await _fileIoApi.endBatchWrite(dest);
      _engineEvents.endBatch(dest.volId);
      _unbindOperationListener(op);
      notifyListeners();
      _syncNotificationProgress();
    }
  }

  /// Local-storage counterpart to [_run]. See [enqueueLocalTransfer].
  ///
  /// Deliberately simpler than [_run]: `dart:io`'s `File.copy()`/`rename()`
  /// are already single fast syscalls (no encryption or Binder/JNI
  /// round-trip in the way), so there's no need for [_CopySemaphore]-bounded
  /// concurrency or a chunked read/write loop with a cancellation check
  /// between every chunk -- items are processed one at a time, with a
  /// cancellation check between each. There's also no cross-platform
  /// free-space API to preflight against, so a genuine out-of-space write
  /// surfaces as a per-item failure instead of an upfront check the way
  /// [_run]'s [vaultExplorerApi.getSpaceInfo] call does.
  Future<void> _runLocal(FileOperation op, ConflictPlan conflictPlan) async {
    op._setStatus(FileOperationStatus.running);
    try {
      op._setActivity(op.l10n.fileOpResolvingConflicts);
      final destDir = Directory(op.destDirPath);
      final existingEntities = await destDir.exists()
          ? await destDir.list(followLinks: false).toList()
          : const <FileSystemEntity>[];
      final existingNames = <String>{};
      final existingDirs = <String>{};
      for (final entity in existingEntities) {
        final name = p.basename(entity.path).toLowerCase();
        existingNames.add(name);
        if (entity is Directory) existingDirs.add(name);
      }

      op._setTotalBytes(op.items.fold(0, (sum, item) => sum + item.sizeBytes));

      final resolved = <({ClipboardItem item, String destPath, bool skip})>[];
      for (final item in op.items) {
        final fileName = item.name;
        String destPath = p.join(op.destDirPath, fileName);

        if (item.path == destPath) {
          resolved.add((item: item, destPath: destPath, skip: true));
          continue;
        }
        if (item.isDir && p.isWithin(item.path, destPath)) {
          // Moving/copying a folder into its own descendant.
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
              await _deleteLocalRecursive(destPath);
            case ConflictResolution.keepBoth:
              final unique = makeUniqueName(fileName, existingNames);
              existingNames.add(unique.toLowerCase());
              destPath = p.join(op.destDirPath, unique);
          }
        }
        resolved.add((item: item, destPath: destPath, skip: false));
      }

      for (int i = 0; i < resolved.length; i++) {
        op._setResolvedDestName(i, p.basename(resolved[i].destPath));
      }
      notifyListeners();

      for (int i = 0; i < resolved.length; i++) {
        if (op.cancelRequested) {
          op._recordItemResult(
            i,
            FileItemResult.skipped,
            errorMessage: op.l10n.statusCancelled,
          );
          continue;
        }
        final r = resolved[i];
        if (r.skip) {
          op._recordItemResult(i, FileItemResult.skipped);
          continue;
        }
        op._setActivity(
          op.isCut
              ? op.l10n.fileOpMovingName(r.item.name)
              : op.l10n.fileOpCopyingName(r.item.name),
        );
        try {
          if (op.isCut) {
            await _moveLocalEntry(r.item.path, r.destPath, r.item.isDir);
          } else {
            await _copyLocalEntry(r.item.path, r.destPath, r.item.isDir);
          }
          op._addTransferredBytes(r.item.sizeBytes);
          op._recordItemResult(i, FileItemResult.success);
        } catch (e) {
          op._recordItemResult(
            i,
            FileItemResult.failed,
            errorMessage: e.toString(),
          );
        }
      }

      if (op.cancelRequested) {
        op._setStatus(FileOperationStatus.cancelled);
      } else if (op.failCount > 0) {
        op._setStatus(FileOperationStatus.completedWithErrors);
      } else {
        op._setStatus(FileOperationStatus.completed);
      }
    } catch (e) {
      op._setError(e.toString());
      op._setStatus(FileOperationStatus.failed);
    } finally {
      _unbindOperationListener(op);
      notifyListeners();
      _syncNotificationProgress();
    }
  }

  Future<void> _copyLocalEntry(
    String sourcePath,
    String destPath,
    bool isDir,
  ) async {
    if (isDir) {
      await Directory(destPath).create(recursive: true);
      await for (final entity in Directory(
        sourcePath,
      ).list(followLinks: false)) {
        final childDest = p.join(destPath, p.basename(entity.path));
        if (entity is Directory) {
          await _copyLocalEntry(entity.path, childDest, true);
        } else if (entity is File) {
          await entity.copy(childDest);
        }
      }
    } else {
      await Directory(p.dirname(destPath)).create(recursive: true);
      await File(sourcePath).copy(destPath);
    }
  }

  Future<void> _moveLocalEntry(
    String sourcePath,
    String destPath,
    bool isDir,
  ) async {
    try {
      await Directory(p.dirname(destPath)).create(recursive: true);
      final entity = isDir ? Directory(sourcePath) : File(sourcePath);
      await entity.rename(destPath);
    } on FileSystemException {
      // Cross-volume (e.g. internal storage → SD card): rename() can't
      // cross a filesystem boundary, so fall back to copy-then-delete.
      await _copyLocalEntry(sourcePath, destPath, isDir);
      await _deleteLocalRecursive(sourcePath);
    }
  }

  Future<void> _deleteLocalRecursive(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  Future<void> _runDelete(FileOperation op, MountedContainer container) async {
    if (container.volId == kDecoyLocalVolId) {
      return _runDeleteLocal(op);
    }
    op._setStatus(FileOperationStatus.running);
    op._setActivity(op.l10n.fileOpDeleting);

    _engineEvents.beginBatch(container.volId);
    await _fileIoApi.beginBatchDelete(container);
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
      await _fileIoApi.endBatchDelete(container);
      _engineEvents.endBatch(container.volId);
      _unbindOperationListener(op);
      notifyListeners();
      _syncNotificationProgress();
    }
  }

  /// Local-storage counterpart to [_runDelete]. See [enqueueLocalTransfer]
  /// for why this is a separate, simpler path: no native container batch
  /// calls, just per-item dart:io deletes.
  Future<void> _runDeleteLocal(FileOperation op) async {
    op._setStatus(FileOperationStatus.running);
    op._setActivity(op.l10n.fileOpDeleting);
    try {
      for (int i = 0; i < op.items.length; i++) {
        if (op.cancelRequested) {
          op._recordItemResult(i, FileItemResult.skipped);
          continue;
        }
        final item = op.items[i];
        try {
          await _deleteLocalRecursive(item.path);
          op._recordItemResult(i, FileItemResult.success);
        } catch (_) {
          op._recordItemResult(
            i,
            FileItemResult.failed,
            errorMessage: op.l10n.fileOpDeleteFailed,
          );
        }
      }
      if (op.cancelRequested) {
        op._setStatus(FileOperationStatus.cancelled);
      } else if (op.failCount > 0) {
        op._setStatus(FileOperationStatus.completedWithErrors);
      } else {
        op._setStatus(FileOperationStatus.completed);
      }
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
      return _copyFile(
        src,
        dest,
        srcPath,
        destPath,
        createdDestPaths,
        op,
        modifiedSecs,
      );
    }

    final children = await _fileIoApi.listDirectory(src, srcPath) ?? [];
    await _fileIoApi.createDirectory(dest, destPath);
    createdDestPaths.add(destPath);
    if (modifiedSecs > 0) {
      await _fileIoApi.setLastModifiedTime(dest, destPath, modifiedSecs);
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
      final size = await _fileIoApi.getFileSize(src, srcPath);
      if (size < 0) return false;

      await _fileIoApi.deleteFile(dest, destPath);

      if (size == 0) {
        final ok = await _fileIoApi.writeFileChunk(
          dest,
          destPath,
          0,
          Uint8List(0),
        );
        if (ok) {
          await _lifecycleApi.finishWrite(dest, destPath);
          createdDestPaths.add(destPath);
          if (modifiedSecs > 0) {
            await _fileIoApi.setLastModifiedTime(dest, destPath, modifiedSecs);
          }
        }
        return ok;
      }

      // Try fast native direct stream copy first:
      final directCopied = await _fileIoApi.copyFile(
        src,
        srcPath,
        dest,
        destPath,
        opId: op.id,
      );
      if (directCopied) {
        createdDestPaths.add(destPath);
        if (modifiedSecs > 0) {
          await _fileIoApi.setLastModifiedTime(dest, destPath, modifiedSecs);
        }
        return true;
      }

      // Fallback to chunked copy with 2 MB chunks if direct copy is unsupported:
      int offset = 0;
      while (offset < size) {
        if (op.cancelRequested) throw const _CancelledException();
        final chunkLen = min(size - offset, _chunkSize);
        final readSw = Stopwatch()..start();
        final chunk = await _fileIoApi.readFileChunk(
          src,
          srcPath,
          offset,
          chunkLen,
        );
        readMicros += readSw.elapsedMicroseconds;
        if (chunk == null || chunk.isEmpty) return false;
        final writeSw = Stopwatch()..start();
        final ok = await _fileIoApi.writeFileChunk(
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
      await _lifecycleApi.finishWrite(dest, destPath);
      createdDestPaths.add(destPath);
      if (modifiedSecs > 0) {
        await _fileIoApi.setLastModifiedTime(dest, destPath, modifiedSecs);
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
        final ok = await _fileIoApi.deleteFile(container, path);
        if (ok) op?._recordDeletedEntry(path.split('/').last);
        return ok;
      } catch (_) {
        return false;
      }
    }

    List<String> children;
    try {
      children = await _fileIoApi.listDirectory(container, path) ?? [];
    } catch (_) {
      try {
        final ok = await _fileIoApi.deleteFile(container, path);
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
      final ok = await _deleteEntryRecursive(
        container,
        '$path/${e.name}',
        e.isDir,
        op: op,
      );
      if (!ok) allOk = false;
    }

    try {
      final deletedSelf = await _fileIoApi.deleteFile(container, path);
      if (deletedSelf) op?._recordDeletedEntry(path.split('/').last);
      return deletedSelf && allOk;
    } catch (_) {
      return false;
    }
  }
}
