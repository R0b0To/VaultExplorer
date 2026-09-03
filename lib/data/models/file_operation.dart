library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part '../services/file_operation_service.dart';

// ── Operation status ──────────────────────────────────────────────────────────

enum FileOperationStatus {
  /// Queued but not yet running (space check / conflict resolution pending).
  pending,

  /// Actively copying/moving items.
  running,

  /// Finished with no errors.
  completed,

  /// Finished but some items failed.
  completedWithErrors,

  /// Aborted by the user before it started.
  cancelled,

  /// Stopped mid-operation due to disk full; partial writes rolled back.
  diskFull,

  /// Unexpected error that prevented the operation from starting.
  failed,
}

// ── Per-item result ───────────────────────────────────────────────────────────

enum FileItemResult { pending, success, skipped, failed }

@immutable
class FileItemStatus {
  final ClipboardItem item;
  final FileItemResult result;
  final String? errorMessage;

  const FileItemStatus({
    required this.item,
    this.result = FileItemResult.pending,
    this.errorMessage,
  });

  FileItemStatus copyWith({FileItemResult? result, String? errorMessage}) =>
      FileItemStatus(
        item: item,
        result: result ?? this.result,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Conflict resolution plan ──────────────────────────────────────────────────

enum ConflictResolution { skip, overwrite, keepBoth }

/// Maps a destination leaf-name (lowercased) to the chosen resolution.
/// Built by the conflict-resolution UI before the operation starts.
typedef ConflictPlan = Map<String, ConflictResolution>;

// ── FileOperation ─────────────────────────────────────────────────────────────

/// A single copy or move job exposed to the UI as a read-only ChangeNotifier.
///
/// **Construction and mutation are intentionally package-private.**
/// Only [FileOperationService] (same Dart library via `part of`) creates
/// instances and calls mutation methods. UI code only reads state and calls
/// [requestCancel].
///
/// Widgets listen for changes with:
/// ```dart
/// ListenableBuilder(
///   listenable: op,
///   builder: (context, _) { … },
/// )
/// ```
class FileOperation extends ChangeNotifier {
  // ── Identity ───────────────────────────────────────────────────────────────

  final int id;
  final bool isCut;
  final int sourceVolId;
  final String sourceDisplayName;
  final int destVolId;
  final String destDisplayName;
  final String destDirPath;
  final List<ClipboardItem> items;
  final bool isImport;
  final bool isExport;
  final bool isDelete;
  final bool isArchiveCreate;
  final bool isArchiveExtract;
  final AppLocalizations l10n;
  final DateTime createdAt;
  FileOperationStatus _status = FileOperationStatus.pending;
  FileOperationStatus get status => _status;

  DateTime? _runStartTime;
  DateTime? get runStartTime => _runStartTime;

  DateTime? _completedAt;
  DateTime? get completedAt => _completedAt;

  int _doneCount = 0;
  int get doneCount =>
      (isImport || isExport || isArchiveExtract) ? _importDone : _doneCount;

  int _failCount = 0;
  int get failCount => _failCount;

  int _skipCount = 0;
  int get skipCount => _skipCount;

  int get totalCount => (isImport || isExport || isArchiveExtract)
      ? _importTotal
      : _itemStatuses.length;

  // Native imports and exports are each a single opaque call rather than a
  // Dart-driven per-item loop, so they can't be tracked via [_itemStatuses]
  // the way copy/move can. Instead native pushes "onImportProgress" /
  // "onExportProgress" events (see [FileOperationService._runImport]/
  // [_runExport]) that update these two directly. [_importTotal] stays 0
  // until native finishes its pre-count pass, which [progressFraction] and
  // [totalCount] both treat as "not yet known".
  //
  // Archive extraction reuses these same fields (see
  // [FileOperationService._runArchiveExtract]): bulk extraction is also a
  // single opaque native call, and native already reports per-entry
  // "onSplitJoinProgress" pushes of (entriesDone, 0) for it -- shaped
  // exactly like import/export's done/total, just missing the byte
  // component, which the archive engine doesn't track per-entry.
  int _importDone = 0;
  int _importTotal = 0;

  int _transferredBytes = 0;
  int get transferredBytes =>
      (isImport || isExport) ? _importTransferredBytes : _transferredBytes;

  int _totalBytes = 0;
  int get totalBytes =>
      (isImport || isExport) ? _importTotalBytes : _totalBytes;

  // Archive creation only ever gets a *cumulative compressed-bytes-written*
  // figure from native (see [FileOperationService._runArchiveCreate]) --
  // there's no companion "total" to pair it with (the final compressed size
  // isn't knowable ahead of the write), so unlike copy/import/export this
  // never feeds [progressFraction]. It exists purely to make
  // [currentActivity] show live movement instead of a static "Compressing…"
  // for however long the archive takes.
  int _archiveBytesWritten = 0;
  int get archiveBytesWritten => _archiveBytesWritten;

  // Deletes are Dart-driven like copy/move, but recurse through a tree
  // whose depth isn't known upfront — pre-scanning it to get an accurate
  // total would mean walking the tree twice, doubling the wait on a slow
  // backend (cryFS in particular decrypts/removes one block at a time, so
  // deleting a large folder can take a while). Instead this counts every
  // file/folder actually removed, live, so the UI has something moving to
  // show even when [progressFraction] can't be computed. See
  // [FileOperationService._deleteEntryRecursive].
  int _removedCount = 0;
  int get removedCount => _removedCount;

  int _importTransferredBytes = 0;
  int _importTotalBytes = 0;

  final List<FileItemStatus> _itemStatuses;
  final Future<void> Function(int operationId, bool isImport, bool isExport)?
  _cancelNativeOperation;
  List<FileItemStatus> get itemStatuses => List.unmodifiable(_itemStatuses);

  String _currentActivity = '';
  String get currentActivity => _currentActivity;

  String? _errorSummary;
  String? get errorSummary => _errorSummary;

  bool _cancelRequested = false;
  bool get cancelRequested => _cancelRequested;

  /// After completion, the service may set this so the browser can scroll
  /// to the newly created item.
  String? completionFocusPath;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Anyone may request cancellation; only the service honours it.
  ///
  /// For copy/move, setting [_cancelRequested] is enough — the Dart-driven
  /// loop in [FileOperationService._run] checks it between items. Native
  /// imports/exports run their own loop on the platform side, so there's
  /// nothing on this side to check it; instead this fires a best-effort
  /// cancellation callback so native can notice on its own.
  void requestCancel() {
    if (_status == FileOperationStatus.pending ||
        _status == FileOperationStatus.running) {
      _cancelRequested = true;
      if (isImport || isExport || !isDelete) {
        // Copy/move: the native fast-path copyFile call runs as one
        // blocking JNI call per file, so setting _cancelRequested alone
        // (checked only by the Dart-side chunked-copy fallback loop)
        // wouldn't stop an in-flight native transfer. This tells the
        // native buffer loop to bail within one chunk instead of only
        // between whole files.
        final cancelNativeOperation = _cancelNativeOperation;
        if (cancelNativeOperation != null) {
          unawaited(cancelNativeOperation(id, isImport, isExport));
        }
      }
      notifyListeners();
    }
  }

  // ── Derived display helpers ───────────────────────────────────────────────

  double? get progressFraction {
    if (isImport || isExport || isArchiveExtract) {
      if (_importTotalBytes > 0) {
        return (_importTransferredBytes / _importTotalBytes).clamp(0.0, 1.0);
      }
      if (_importTotal > 0) {
        return (_importDone / _importTotal).clamp(0.0, 1.0);
      }
      return null;
    }
    if (isArchiveCreate) {
      // Compressed output size can't be predicted from the uncompressed
      // input size, so there's no honest fraction to divide by here --
      // indeterminate keeps the ring spinning instead of showing a fraction
      // that's likely wrong (same rationale as the single-item delete case
      // below). [currentActivity]'s live bytes-written counter (see
      // [_setArchiveCreateBytesWritten]) carries the "still working" signal
      // instead.
      return null;
    }
    if (_totalBytes > 0) {
      return (_transferredBytes / _totalBytes).clamp(0.0, 1.0);
    }
    if (isDelete && _itemStatuses.length <= 1) {
      // A single selected item (almost always the case that matters —
      // one slow-to-delete folder) gives no meaningful fraction without
      // an expensive pre-scan. Indeterminate keeps the ring spinning
      // instead of sitting frozen at 0%; [removedCount] + [currentActivity]
      // carry the live progress instead.
      return null;
    }
    if (_itemStatuses.isNotEmpty) {
      final done = _doneCount + _failCount + _skipCount;
      return done / _itemStatuses.length;
    }
    return null;
  }

  /// Bytes transferred per second, or null if not enough data yet.
  /// Uses wall-clock elapsed time from when the operation started running.
  double? get bytesPerSecond {
    if (_status != FileOperationStatus.running || transferredBytes == 0)
      return null;
    final start = _runStartTime;
    if (start == null) return null;
    final elapsed = DateTime.now().difference(start);
    if (elapsed.inMilliseconds < 500) return null;
    final seconds = elapsed.inMicroseconds / 1000000.0;
    if (seconds <= 0) return null;
    return transferredBytes / seconds;
  }

  /// Estimated time remaining based on current throughput, or null.
  Duration? get estimatedTimeRemaining {
    final speed = bytesPerSecond;
    if (speed == null || speed < 1) return null;
    final remaining = totalBytes - transferredBytes;
    if (remaining <= 0) return null;
    return Duration(seconds: (remaining / speed).ceil());
  }

  void _setTotalBytes(int bytes) {
    _totalBytes = bytes;
    notifyListeners();
  }

  void _addTransferredBytes(int bytes) {
    _transferredBytes += bytes;
    notifyListeners();
  }

  bool get isCrossContainer =>
      !isImport &&
      !isExport &&
      !isDelete &&
      !isArchiveCreate &&
      !isArchiveExtract &&
      sourceVolId != destVolId;
  String get verb => isImport
      ? l10n.verbImport
      : isExport
      ? l10n.verbExport
      : isArchiveCreate
      ? l10n.verbArchive
      : isArchiveExtract
      ? l10n.verbExtract
      : isDelete
      ? l10n.verbDelete
      : (isCut ? l10n.verbMove : l10n.verbCopy);
  String get verbPast => isImport
      ? l10n.verbImported
      : isExport
      ? l10n.verbExported
      : isArchiveCreate
      ? l10n.verbArchived
      : isArchiveExtract
      ? l10n.verbExtracted
      : isDelete
      ? l10n.verbDeleted
      : (isCut ? l10n.verbMoved : l10n.verbCopied);
  String get verbIng => isImport
      ? l10n.verbImporting
      : isExport
      ? l10n.verbExporting
      : isArchiveCreate
      ? l10n.verbArchiving
      : isArchiveExtract
      ? l10n.verbExtracting
      : isDelete
      ? l10n.verbDeleting
      : (isCut ? l10n.verbMoving : l10n.verbCopying);
  String get shortSummary {
    final n = items.length;
    final label = n == 1 ? items.first.name : l10n.fileOpItemsCount(n);
    final isActive =
        _status == FileOperationStatus.pending ||
        _status == FileOperationStatus.running;
    return '${isActive ? verbIng : verbPast} $label';
  }

  String get completionSummary {
    final parts = <String>[];
    if (_doneCount > 0)
      parts.add(l10n.fileOpSummaryCount(_doneCount, verbPast.toLowerCase()));
    if (_skipCount > 0) parts.add(l10n.fileOpSummarySkipped(_skipCount));
    if (_failCount > 0) parts.add(l10n.fileOpSummaryFailed(_failCount));
    if (parts.isEmpty) {
      if (_status == FileOperationStatus.cancelled) return l10n.statusCancelled;
      if (_status == FileOperationStatus.failed) return l10n.statusFailed;
      return l10n.statusCompleted;
    }
    return parts.join(' · ');
  }

  FileOperation._internal({
    required this.id,
    required this.isCut,
    required this.sourceVolId,
    required this.sourceDisplayName,
    required this.destVolId,
    required this.destDisplayName,
    required this.destDirPath,
    required this.items,
    this.isImport = false,
    this.isExport = false,
    this.isDelete = false,
    this.isArchiveCreate = false,
    this.isArchiveExtract = false,
    required this.l10n,
    Future<void> Function(int operationId, bool isImport, bool isExport)?
    cancelNativeOperation,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       _cancelNativeOperation = cancelNativeOperation,
       _itemStatuses = items
           .map((i) => FileItemStatus(item: i))
           .toList(growable: false);
  void _setImportProgress({
    required int done,
    required int total,
    required String currentName,
    int transferredBytes = 0,
    int totalBytes = 0,
  }) {
    _importDone = done;
    _importTotal = total;
    _importTransferredBytes = transferredBytes;
    _importTotalBytes = totalBytes;
    _currentActivity = currentName.isNotEmpty
        ? (isArchiveExtract
              ? l10n.fileOpExtractingArchiveName(currentName)
              : isExport
              ? l10n.fileOpExportingName(currentName)
              : l10n.fileOpImportingName(currentName))
        : (isArchiveExtract
              ? l10n.fileOpExtractingArchive
              : isExport
              ? l10n.fileOpExporting
              : l10n.fileOpImporting);
    notifyListeners();
  }

  /// Applied on each "onSplitJoinProgress" push from native for an
  /// archive-create operation (see
  /// [FileOperationService._runArchiveCreate]). Unlike extraction's
  /// per-entry done/total (which [_setImportProgress] already models),
  /// creation only ever reports cumulative *compressed* bytes written --
  /// see [progressFraction]'s isArchiveCreate branch for why that never
  /// turns into a fraction. This only drives the live activity text.
  void _setArchiveCreateBytesWritten(int bytesWritten) {
    _archiveBytesWritten = bytesWritten;
    _currentActivity = l10n.fileOpArchivingBytes(formatBytes(bytesWritten));
    notifyListeners();
  }

  void _setStatus(FileOperationStatus s) {
    if (_status != FileOperationStatus.running &&
        s == FileOperationStatus.running) {
      _runStartTime = DateTime.now();
    }
    if (s != FileOperationStatus.pending &&
        s != FileOperationStatus.running &&
        _completedAt == null) {
      _completedAt = DateTime.now();
    }
    _status = s;
    notifyListeners();
  }

  void _setActivity(String msg) {
    _currentActivity = msg;
    notifyListeners();
  }

  void _setError(String summary) {
    _errorSummary = summary;
    notifyListeners();
  }

  void _setDoneCount(int count) {
    _doneCount = count;
    notifyListeners();
  }

  /// Called by [FileOperationService._deleteEntryRecursive] for every
  /// file/folder actually removed, at any depth. Folds the just-removed
  /// name into [currentActivity] and bumps [removedCount] so the pill and
  /// operations sheet have continuous, live proof the delete is still
  /// running rather than stuck.
  void _recordDeletedEntry(String name) {
    _removedCount++;
    _currentActivity = l10n.fileOpDeletingName(name);
    notifyListeners();
  }

  final Map<int, String> _resolvedDestNames = {};
  String? resolvedDestName(int index) => _resolvedDestNames[index];
  void _setResolvedDestName(int index, String name) {
    _resolvedDestNames[index] = name;
  }

  void _recordImportItemFinished({
    required String sourceName,
    required String resolvedName,
    required bool isDir,
    required bool success,
  }) {
    final idx = _itemStatuses.indexWhere(
      (s) =>
          s.item.name.toLowerCase() == sourceName.toLowerCase() ||
          s.item.name.toLowerCase() == resolvedName.toLowerCase(),
    );
    if (idx != -1) {
      _resolvedDestNames[idx] = resolvedName;
      _recordItemResult(
        idx,
        success ? FileItemResult.success : FileItemResult.failed,
      );
    } else {
      notifyListeners();
    }
  }

  /// Export counterpart to [_recordImportItemFinished]. Simpler: export
  /// never renames an entry (no conflict resolution happens on the way
  /// out), so there's no resolvedName to also match against.
  void _recordExportItemFinished({
    required String sourceName,
    required bool success,
  }) {
    final idx = _itemStatuses.indexWhere(
      (s) => s.item.name.toLowerCase() == sourceName.toLowerCase(),
    );
    if (idx != -1) {
      _recordItemResult(
        idx,
        success ? FileItemResult.success : FileItemResult.failed,
      );
    } else {
      notifyListeners();
    }
  }

  /// Applied on each "onImportProgress" push from native (see
  /// [FileOperationService._runImport]). [currentName] is folded straight
  /// into [_currentActivity] so the UI doesn't need a separate field.
  void _recordItemResult(
    int index,
    FileItemResult result, {
    String? errorMessage,
  }) {
    assert(index >= 0 && index < _itemStatuses.length);
    _itemStatuses[index] = _itemStatuses[index].copyWith(
      result: result,
      errorMessage: errorMessage,
    );
    switch (result) {
      case FileItemResult.success:
        _doneCount++;
      case FileItemResult.skipped:
        _skipCount++;
      case FileItemResult.failed:
        _failCount++;
      case FileItemResult.pending:
        break;
    }
    notifyListeners();
  }
}