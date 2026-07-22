library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

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

  // ── Mutable state (read-only externally) ──────────────────────────────────

  FileOperationStatus _status = FileOperationStatus.pending;
  FileOperationStatus get status => _status;

  int _doneCount = 0;
  int get doneCount => isImport ? _importDone : _doneCount;

  int _failCount = 0;
  int get failCount => _failCount;

  int _skipCount = 0;
  int get skipCount => _skipCount;

  int get totalCount => isImport ? _importTotal : _itemStatuses.length;

  // Native imports are a single opaque call rather than a Dart-driven
  // per-item loop, so they can't be tracked via [_itemStatuses] the way
  // copy/move can. Instead native pushes "onImportProgress" events (see
  // [FileOperationService._runImport]) that update these two directly.
  // [_importTotal] stays 0 until native finishes its pre-count pass, which
  // [progressFraction] and [totalCount] both treat as "not yet known".
  int _importDone = 0;
  int _importTotal = 0;

  final List<FileItemStatus> _itemStatuses;
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
  /// imports run their own loop on the platform side, so there's nothing
  /// on this side to check it; instead this fires a best-effort
  /// [VaultExplorerApi.cancelImport] call so native can notice on its own.
  void requestCancel() {
    if (_status == FileOperationStatus.pending ||
        _status == FileOperationStatus.running) {
      _cancelRequested = true;
      if (isImport) {
        vaultExplorerApi.cancelImport(id);
      }
      notifyListeners();
    }
  }

  // ── Derived display helpers ───────────────────────────────────────────────

  double? get progressFraction {
    if (isImport) {
      if (_importTotal <= 0) return null; // still counting — indeterminate
      return (_importDone / _importTotal).clamp(0.0, 1.0);
    }
    if (_itemStatuses.isEmpty) return null;
    final done = _doneCount + _failCount + _skipCount;
    return done / _itemStatuses.length;
  }

  bool get isCrossContainer => !isImport && sourceVolId != destVolId;
  String get verb => isImport ? 'Import' : (isCut ? 'Move' : 'Copy');
  String get verbPast => isImport ? 'Imported' : (isCut ? 'Moved' : 'Copied');
  String get verbIng => isImport ? 'Importing' : (isCut ? 'Moving' : 'Copying');

  String get shortSummary {
    final n = items.length;
    final label = n == 1 ? items.first.name : '$n items';
    final isActive = _status == FileOperationStatus.pending || _status == FileOperationStatus.running;
    return '${isActive ? verbIng : verbPast} $label';
  }

  String get completionSummary {
    final parts = <String>[];
    if (_doneCount > 0) parts.add('$_doneCount item${_doneCount == 1 ? '' : 's'} ${verbPast.toLowerCase()}');
    if (_skipCount > 0) parts.add('$_skipCount skipped');
    if (_failCount > 0) parts.add('$_failCount failed');
    
    if (parts.isEmpty) {
      if (_status == FileOperationStatus.cancelled) return 'Cancelled';
      if (_status == FileOperationStatus.failed) return 'Failed';
      return 'Completed';
    }
    return parts.join(' · ');
  }

  // ── Internal constructor — callable only from this library ────────────────
  //
  // Dart's library-privacy rules mean anything prefixed with `_` is accessible
  // anywhere within the same *library* (i.e. the same `part of` compilation
  // unit). Since FileOperationService is declared as `part of` this library
  // (see file_operation_service.dart), it can call FileOperation._internal()
  // and all _set* methods below. External code cannot.

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
  }) : _itemStatuses = items
           .map((i) => FileItemStatus(item: i))
           .toList(growable: false);

  // ── Mutation API — library-private ────────────────────────────────────────

  void _setStatus(FileOperationStatus s) {
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

  /// Applied on each "onImportProgress" push from native (see
  /// [FileOperationService._runImport]). [currentName] is folded straight
  /// into [_currentActivity] so the UI doesn't need a separate field.
  void _setImportProgress(int done, int total, String currentName) {
    _importDone = done;
    _importTotal = total;
    _currentActivity = currentName.isNotEmpty ? 'Importing $currentName…' : 'Importing…';
    notifyListeners();
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
