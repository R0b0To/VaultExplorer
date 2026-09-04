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
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
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

  int _importDone = 0;
  int _importTotal = 0;

  int _transferredBytes = 0;
  int get transferredBytes =>
      (isImport || isExport) ? _importTransferredBytes : _transferredBytes;

  int _totalBytes = 0;
  int get totalBytes =>
      (isImport || isExport) ? _importTotalBytes : _totalBytes;

  int _archiveBytesWritten = 0;
  int get archiveBytesWritten => _archiveBytesWritten;

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

  String? completionFocusPath;

  // ── Public API ────────────────────────────────────────────────────────────

  void requestCancel() {
    if (_status == FileOperationStatus.pending ||
        _status == FileOperationStatus.running) {
      _cancelRequested = true;
      if (isImport || isExport || isArchiveCreate || isArchiveExtract || !isDelete) {
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
      return null;
    }
    if (_totalBytes > 0) {
      return (_transferredBytes / _totalBytes).clamp(0.0, 1.0);
    }
    if (isDelete && _itemStatuses.length <= 1) {
      return null;
    }
    if (_itemStatuses.isNotEmpty) {
      final done = _doneCount + _failCount + _skipCount;
      return done / _itemStatuses.length;
    }
    return null;
  }

  double? get bytesPerSecond {
    if (_status != FileOperationStatus.running || transferredBytes == 0) {
      return null;
    }
    final start = _runStartTime;
    if (start == null) return null;
    final elapsed = DateTime.now().difference(start);
    if (elapsed.inMilliseconds < 500) return null;
    final seconds = elapsed.inMicroseconds / 1000000.0;
    if (seconds <= 0) return null;
    return transferredBytes / seconds;
  }

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
    if (_doneCount > 0) {
      parts.add(l10n.fileOpSummaryCount(_doneCount, verbPast.toLowerCase()));
    }
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
    this._cancelNativeOperation,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now(),
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