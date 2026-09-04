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
  static const _chunkSize = 2 * 1024 * 1024; // 2 MB
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

  List<RawEntry> getActivePlaceholders(int volId, String dirPath) {
    final placeholders = <RawEntry>[];
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
            modifiedSecs: 0,
            isPlaceholder: true,
          ),
        );
      }
    }
    return placeholders;
  }

  Set<String> getPendingDeletedNames(int volId, String dirPath) {
    final deletedNames = <String>{};
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
    _runLocal(op, source, dest, conflictPlan ?? {});
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

  /// Enqueues background archive creation.
  FileOperation enqueueArchiveCreate({
    required MountedContainer source,
    required MountedContainer dest,
    required String destDirPath,
    required String archiveName,
    required List<ClipboardItem> items,
    required ArchiveFormatType format,
    String? passphrase,
    bool deleteSourceAfter = false,
    required AppLocalizations l10n,
  }) {
    final op = FileOperation._internal(
      id: _nextId++,
      isCut: false,
      sourceVolId: source.volId,
      sourceDisplayName: source.displayName,
      destVolId: dest.volId,
      destDisplayName: dest.displayName,
      destDirPath: destDirPath,
      items: items,
      isArchiveCreate: true,
      l10n: l10n,
      cancelNativeOperation: _cancelNativeOperation,
    );
    _operations.add(op);
    _bindOperationListener(op);
    notifyListeners();
    _syncNotificationProgress();
    _runArchiveCreate(
      op,
      source,
      dest,
      destDirPath,
      archiveName,
      items,
      format,
      passphrase,
      deleteSourceAfter,
    );
    return op;
  }

 FileOperation enqueueArchiveExtract({
    required MountedContainer source,
    required MountedContainer dest,
    required String destDirPath,
    required String archivePath,
    required String archiveName,
    required ArchiveContext archiveContext,
    List<String>? selectedEntryPaths,
    int totalEntries = 0,
    String subPath = '',
    bool deleteArchiveAfter = false,
    required AppLocalizations l10n,
  }) {
    final op = FileOperation._internal(
      id: _nextId++,
      isCut: false,
      sourceVolId: source.volId,
      sourceDisplayName: source.displayName,
      destVolId: dest.volId,
      destDisplayName: dest.displayName,
      destDirPath: destDirPath,
      items: [
        ClipboardItem(
          path: archivePath,
          isDir: false,
          sizeBytes: 0,
        ),
      ],
      isArchiveExtract: true,
      l10n: l10n,
      cancelNativeOperation: _cancelNativeOperation,
    );
    _operations.add(op);
    _bindOperationListener(op);
    notifyListeners();
    _syncNotificationProgress();
    _runArchiveExtract(
      op,
      source,
      dest,
      destDirPath,
      archivePath,
      archiveName,
      archiveContext,
      selectedEntryPaths,
      totalEntries,
      subPath,
      deleteArchiveAfter,
    );
    return op;
  }
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
      } else if ((op.isImport || op.isArchiveExtract) && op.totalCount > 0) {
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

  // ── Size measurement ──────────────────────────────────────────────────────

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

  // ── Operation runner: Archive Create ──────────────────────────────────────

  Future<void> _runArchiveCreate(
    FileOperation op,
    MountedContainer source,
    MountedContainer dest,
    String destDirPath,
    String archiveName,
    List<ClipboardItem> items,
    ArchiveFormatType format,
    String? passphrase,
    bool deleteSourceAfter,
  ) async {
    op._setStatus(FileOperationStatus.running);
    op._setActivity(op.l10n.verbArchiving);

    void onProgress(SplitJoinProgress p) {
      if (p.opId != op.id) return;
      op._setArchiveCreateBytesWritten(p.bytesDone);
    }

    _engineEvents.addSplitJoinProgressListener(onProgress);

    try {
      final destVaultPath = destDirPath.isEmpty
          ? archiveName
          : '$destDirPath/$archiveName';

      final srcPaths = <String>[];
      final entryNames = <String>[];

      Future<void> collect(String containerPath, String archivePath) async {
        if (op.cancelRequested) throw const _CancelledException();
        final rawList = await _fileIoApi.listDirectory(source, containerPath);
        final children = RawEntry.parseAll(rawList ?? const []);
        for (final child in children) {
          if (child.name.startsWith('System:')) continue;
          final childContainerPath = '$containerPath/${child.name}';
          final childArchivePath = '$archivePath/${child.name}';
          if (child.isDir) {
            await collect(childContainerPath, childArchivePath);
          } else {
            srcPaths.add(
              source.isLocalStorage
                  ? p.join(source.uri, childContainerPath)
                  : childContainerPath,
            );
            entryNames.add(childArchivePath);
          }
        }
      }

      for (final item in items) {
        if (op.cancelRequested) throw const _CancelledException();
        if (item.isDir) {
          await collect(item.path, item.name);
        } else {
          srcPaths.add(
            source.isLocalStorage
                ? p.join(source.uri, item.path)
                : item.path,
          );
          entryNames.add(item.name);
        }
      }

      if (op.cancelRequested) throw const _CancelledException();

      if (srcPaths.isEmpty) {
        op._setStatus(FileOperationStatus.completed);
        return;
      }

      await _fileIoApi.deleteFile(dest, destVaultPath);

      final ok = await ArchiveService.createArchive(
        format: format,
        srcPaths: srcPaths,
        entryNames: entryNames,
        srcUri: source.isLocalStorage ? source.uri : source.uri,
        destUri: dest.isLocalStorage ? dest.uri : dest.uri,
        destVaultPath: destVaultPath,
        destFilePath: dest.isLocalStorage ? p.join(dest.uri, destVaultPath) : null,
        passphrase: passphrase,
        opId: op.id,
      );

      if (op.cancelRequested) {
        op._setStatus(FileOperationStatus.cancelled);
      } else if (ok) {
        op._setDoneCount(srcPaths.length);
        if (deleteSourceAfter) {
          for (final item in items) {
            await _deleteEntryRecursive(source, item.path, item.isDir);
          }
        }
        op._setStatus(FileOperationStatus.completed);
      } else {
        op._setError(op.l10n.failedToArchiveGeneric('Create failed'));
        op._setStatus(FileOperationStatus.failed);
      }
    } on _CancelledException {
      op._setStatus(FileOperationStatus.cancelled);
    } catch (e) {
      if (op.cancelRequested) {
        op._setStatus(FileOperationStatus.cancelled);
      } else {
        op._setError(e.toString());
        op._setStatus(FileOperationStatus.failed);
      }
    } finally {
      _engineEvents.removeSplitJoinProgressListener(onProgress);
      await _fileIoApi.clearCopyState(op.id);
      _unbindOperationListener(op);
      notifyListeners();
      _syncNotificationProgress();
    }
  }

  // ── Operation runner: Archive Extract ──────────────────────────────────────

   Future<void> _runArchiveExtract(
    FileOperation op,
    MountedContainer source,
    MountedContainer dest,
    String destDirPath,
    String archivePath,
    String archiveName,
    ArchiveContext archiveContext,
    List<String>? selectedEntryPaths,
    int totalEntries,
    String subPath,
    bool deleteArchiveAfter,
  ) async {
    op._setStatus(FileOperationStatus.running);
    op._setActivity(op.l10n.fileOpExtractingArchive);

    void onProgress(SplitJoinProgress p) {
      if (p.opId != op.id) return;
      op._setImportProgress(
        done: p.bytesDone,
        total: totalEntries > 0 ? totalEntries : p.bytesDone,
        currentName: archiveName,
      );
    }

    _engineEvents.addSplitJoinProgressListener(onProgress);

    try {
      final int count;
      if (selectedEntryPaths != null && selectedEntryPaths.isNotEmpty) {
        count = await ArchiveService.extractSelectedToContainer(
          container: dest,
          archiveContext: archiveContext,
          entryPaths: selectedEntryPaths,
          targetDirInContainer: destDirPath,
          onProgress: (doneCount, currentPath) {
            op._setImportProgress(
              done: doneCount,
              total: totalEntries > 0 ? totalEntries : doneCount,
              currentName: currentPath,
            );
          },
          opId: op.id,
        );
      } else {
        count = await ArchiveService.extractAllToContainer(
          container: dest,
          archiveContext: archiveContext,
          targetDirInContainer: destDirPath,
          subPath: subPath,
          opId: op.id,
        );
      }

      if (op.cancelRequested) {
        op._setStatus(FileOperationStatus.cancelled);
      } else if (count > 0 || totalEntries == 0) {
        op._setDoneCount(count);
        if (deleteArchiveAfter) {
          await _deleteEntryRecursive(source, archivePath, false);
        }
        op._setStatus(FileOperationStatus.completed);
      } else {
        op._setError(op.l10n.failedToExtractGeneric('Extract failed'));
        op._setStatus(FileOperationStatus.failed);
      }
    } on _CancelledException {
      op._setStatus(FileOperationStatus.cancelled);
    } catch (e) {
      if (op.cancelRequested) {
        op._setStatus(FileOperationStatus.cancelled);
      } else {
        op._setError(e.toString());
        op._setStatus(FileOperationStatus.failed);
      }
    } finally {
      _engineEvents.removeSplitJoinProgressListener(onProgress);
      await _fileIoApi.clearCopyState(op.id);
      _unbindOperationListener(op);
      notifyListeners();
      _syncNotificationProgress();
    }
  }

  // ── Operation runner: Import ──────────────────────────────────────────────

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
      } else if (e.code == 'INSUFFICIENT_SPACE') {
        final details = e.details;
        final needed = details is Map ? details['neededBytes'] as int? : null;
        final available = details is Map ? details['availableBytes'] as int? : null;
        op._setError(
          (needed != null && available != null)
              ? op.l10n.fileOpNotEnoughSpace(
                  formatBytes(needed),
                  formatBytes(available),
                )
              : e.message ?? e.toString(),
        );
        op._setStatus(FileOperationStatus.failed);
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

  // ── Operation runner: Export ──────────────────────────────────────────────

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
        op._setStatus(
          op.failCount > 0
              ? FileOperationStatus.completedWithErrors
              : FileOperationStatus.completed,
        );
      } else if (op.cancelRequested) {
        op._setStatus(FileOperationStatus.cancelled);
      } else if (op._itemStatuses.isNotEmpty &&
          op._itemStatuses.every((s) => s.result == FileItemResult.failed)) {
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

  // ── Operation runner: Copy / Move ─────────────────────────────────────────

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

        if (src.volId == dest.volId && item.path == destPath) {
          resolved.add((
            item: item,
            destPath: destPath,
            skip: true,
            mergeOverwrite: false,
          ));
          continue;
        }
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

  // ── Operation runner: Local Transfer ──────────────────────────────────────

  Future<void> _runLocal(
    FileOperation op,
    MountedContainer source,
    MountedContainer dest,
    ConflictPlan conflictPlan,
  ) async {
    op._setStatus(FileOperationStatus.running);
    try {
      op._setActivity(op.l10n.fileOpResolvingConflicts);
      final destDirAbs = _resolveLocal(dest.uri, op.destDirPath);
      final destDir = Directory(destDirAbs);
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

      final resolved =
          <({ClipboardItem item, String srcPath, String destPath, bool skip})>[];
      for (final item in op.items) {
        final fileName = item.name;
        final srcPath = _resolveLocal(source.uri, item.path);
        String destPath = p.join(destDirAbs, fileName);

        if (srcPath == destPath) {
          resolved.add((item: item, srcPath: srcPath, destPath: destPath, skip: true));
          continue;
        }
        if (item.isDir && p.isWithin(srcPath, destPath)) {
          resolved.add((item: item, srcPath: srcPath, destPath: destPath, skip: true));
          continue;
        }

        if (existingNames.contains(fileName.toLowerCase())) {
          final resolution =
              conflictPlan[fileName.toLowerCase()] ??
              ConflictResolution.keepBoth;
          switch (resolution) {
            case ConflictResolution.skip:
              resolved.add((item: item, srcPath: srcPath, destPath: destPath, skip: true));
              continue;
            case ConflictResolution.overwrite:
              await _deleteLocalRecursive(destPath);
            case ConflictResolution.keepBoth:
              final unique = makeUniqueName(fileName, existingNames);
              existingNames.add(unique.toLowerCase());
              destPath = p.join(destDirAbs, unique);
          }
        }
        resolved.add((item: item, srcPath: srcPath, destPath: destPath, skip: false));
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
            await _moveLocalEntry(r.srcPath, r.destPath, r.item.isDir);
          } else {
            await _copyLocalEntry(r.srcPath, r.destPath, r.item.isDir);
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

  String _resolveLocal(String rootPath, String relativePath) =>
      relativePath.isEmpty ? rootPath : p.join(rootPath, relativePath);

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

  // ── Operation runner: Delete ──────────────────────────────────────────────

  Future<void> _runDelete(FileOperation op, MountedContainer container) async {
    if (container.volId == kDecoyLocalVolId) {
      return _runDeleteLocal(op, container);
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

  Future<void> _runDeleteLocal(
    FileOperation op,
    MountedContainer container,
  ) async {
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
          await _deleteLocalRecursive(_resolveLocal(container.uri, item.path));
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