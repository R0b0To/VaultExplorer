import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/library/index/library_index.dart';
import 'package:vaultexplorer/features/library/index/library_scanner.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';

/// The two operations the scanner needs from a container, bundled so a test
/// can supply a fake tree and the app can supply the vault engine.
class LibraryFileAccess {
  final LibraryDirectoryLister list;
  final LibraryChunkReader read;

  const LibraryFileAccess({required this.list, required this.read});
}

enum LibraryPhase {
  /// No container opened yet.
  idle,

  /// Reading the saved index.
  loading,

  /// Walking folders and reading tags (the saved index, if any, is already
  /// showing).
  scanning,

  /// Idle with an up-to-date index.
  ready,
}

/// Owns the library of one container: loads the saved index, keeps it current
/// with an incremental scan of the chosen folders, and exposes it for the
/// screens.
///
/// Lives as long as the file manager tab that created it. [dispose] cancels any
/// running scan and drops the in-memory index, so nothing about a vault's
/// contents outlives the tab (the saved copy is encrypted).
class LibraryController extends ChangeNotifier {
  final LibraryFileAccess Function(MountedContainer container) _access;
  final LibraryIndexStore _store;
  final bool Function(String fileName) _isAudioFile;
  final int _readConcurrency;

  /// Shortest gap between index rebuilds while scanning (it grows with the
  /// index; see `_scan`).
  final int _minApplyGapMs;

  /// During a long scan the index is saved after this many new tracks, or this
  /// much time, so a first scan of a huge library that is interrupted (the
  /// vault locks, the app is killed) resumes instead of starting over.
  final int _checkpointTracks;
  final int _checkpointMillis;

  LibraryController({
    required this._access,
    required this._store,
    required this._isAudioFile,
    this._readConcurrency = 6,
    this._minApplyGapMs = 1500,
    this._checkpointTracks = 1500,
    this._checkpointMillis = 45000,
  });

  MountedContainer? _container;
  List<String> _folders = const [];
  LibraryIndex _index = LibraryIndex.empty();
  LibraryPhase _phase = LibraryPhase.idle;
  LibraryScanProgress? _progress;
  bool _loadedSaved = false;
  int _readFailures = 0;
  bool _walkIncomplete = false;
  bool _disposed = false;

  int _generation = 0;
  CancellationToken? _token;

  MountedContainer? get container => _container;
  LibraryIndex get index => _index;
  LibraryPhase get phase => _phase;
  LibraryScanProgress? get progress => _progress;

  /// The folders being indexed; empty means the whole container.
  List<String> get folders => _folders;

  /// Where the index is saved for this container.
  LibraryLocation? get location =>
      _container == null ? null : LibraryIndexStore.locationFor(_container!);

  /// True when a saved index was found at open (the library appeared instantly).
  bool get loadedFromSaved => _loadedSaved;

  /// Files whose tags could not be read in the last scan.
  int get readFailures => _readFailures;

  /// True when the last scan could not list every folder or was cut short, so
  /// deleted files were deliberately left in the index.
  bool get walkIncomplete => _walkIncomplete;

  bool get isScanning => _phase == LibraryPhase.scanning;

  /// Opens [container]: shows its saved index at once, then refreshes it.
  /// [folders] limits what is indexed; empty means the whole container.
  Future<void> open(
    MountedContainer container, {
    List<String> folders = const [],
  }) async {
    _cancelRunning();
    final gen = ++_generation;
    _container = container;
    _folders = List.unmodifiable(folders);
    _index = LibraryIndex.empty();
    _progress = null;
    _loadedSaved = false;
    _readFailures = 0;
    _walkIncomplete = false;
    _phase = LibraryPhase.loading;
    _notify();

    final saved = await _store.loadIndex(container);
    if (_stale(gen)) return;
    if (saved != null) {
      _index = LibraryIndex([for (final t in saved) t.withSource(container.uri)]);
      _loadedSaved = true;
    }
    await _scan(gen, ignoreExisting: false);
  }

  /// Changes which folders are indexed and rescans. Tracks from folders no
  /// longer chosen leave the index once the scan has seen everything.
  Future<void> setFolders(List<String> folders) async {
    if (_container == null) return;
    _folders = List.unmodifiable(folders);
    await rescan();
  }

  /// Looks for new, changed and deleted files. With [rebuild] every file's
  /// tags are re-read, which picks up edits that left size and date alone.
  Future<void> rescan({bool rebuild = false}) async {
    final c = _container;
    if (c == null || _phase == LibraryPhase.loading) return;
    _cancelRunning();
    await _scan(++_generation, ignoreExisting: rebuild);
  }

  /// Stops a running scan. What was found so far is kept and saved.
  void cancelScan() => _token?.cancel();

  /// Deletes the saved copy of the index. The in-memory one stays until the
  /// tab closes.
  Future<void> clearSavedIndex() async {
    final c = _container;
    if (c == null) return;
    await _store.deleteIndex(c);
    _loadedSaved = false;
    _notify();
  }

  /// Forgets the container: cancels any scan and drops the in-memory index.
  ///
  /// Called when music mode is switched off or the vault is locked, so nothing
  /// about a vault's contents stays in memory after it is gone.
  void close() {
    _cancelRunning();
    _generation++;
    _container = null;
    _folders = const [];
    _index = LibraryIndex.empty();
    _phase = LibraryPhase.idle;
    _progress = null;
    _loadedSaved = false;
    _readFailures = 0;
    _walkIncomplete = false;
    _notify();
  }

  bool _stale(int gen) => _disposed || gen != _generation;

  void _cancelRunning() {
    _token?.cancel();
    _token = null;
  }

  Future<void> _scan(int gen, {required bool ignoreExisting}) async {
    final container = _container;
    if (container == null || _stale(gen)) return;

    final token = CancellationToken();
    _token = token;
    _phase = LibraryPhase.scanning;
    _progress = null;
    _notify();

    final access = _access(container);
    final scanner = LibraryScanner(
      listDirectory: access.list,
      readChunk: access.read,
      isAudioFile: _isAudioFile,
      readConcurrency: _readConcurrency,
    );

    final baseline = {for (final t in _index.tracks) t.path: t};
    final existing = ignoreExisting ? <String, LibraryTrack>{} : baseline;
    final pending = <LibraryTrack>[];
    var changed = false;
    final clock = Stopwatch()..start();
    var lastApplyAt = 0;
    var lastApplyCost = 0;
    var appliedSinceSave = 0;
    var lastSaveAt = 0;
    Future<bool>? saving;

    void applyPending() {
      if (pending.isEmpty) return;
      final cost = Stopwatch()..start();
      appliedSinceSave += pending.length;
      _index = _index.withChanges(upserts: pending);
      pending.clear();
      changed = true;
      lastApplyCost = cost.elapsedMilliseconds;
      lastApplyAt = clock.elapsedMilliseconds;
    }

    // One save in flight at a time; a checkpoint that finds one running just
    // waits for the next opportunity.
    void checkpoint() {
      if (saving != null || _stale(gen)) return;
      if (appliedSinceSave < _checkpointTracks &&
          clock.elapsedMilliseconds - lastSaveAt < _checkpointMillis) {
        return;
      }
      appliedSinceSave = 0;
      lastSaveAt = clock.elapsedMilliseconds;
      saving = _store.saveIndex(container, _index.tracks).whenComplete(() {
        saving = null;
      });
    }

    final LibraryScanResult result;
    try {
      result = await scanner.scan(
        startPaths: _folders.isEmpty ? const [''] : _folders,
        existing: existing,
        token: token,
        onTracks: (batch) {
          if (_stale(gen)) return;
          pending.addAll([for (final t in batch) t.withSource(container.uri)]);
          // Rebuilding the index costs time proportional to its size, so the
          // gap between rebuilds grows with that cost instead of being fixed.
          final gap = math.max(_minApplyGapMs, lastApplyCost * 10);
          if (clock.elapsedMilliseconds - lastApplyAt >= gap) {
            applyPending();
            checkpoint();
            _notify();
          }
        },
        onProgress: (p) {
          if (_stale(gen)) return;
          _progress = p;
          _notify();
        },
      );
    } catch (_) {
      if (!_stale(gen)) {
        _phase = LibraryPhase.ready;
        _progress = null;
        _walkIncomplete = true;
        _notify();
      }
      return;
    }
    if (_stale(gen)) return;

    // Deletions only count from a walk that saw everything.
    var removed = const <String>[];
    if (result.walkComplete) {
      removed = [
        for (final t in _index.tracks)
          if (!result.seenPaths.contains(t.path)) t.key,
      ];
    }
    applyPending();
    if (removed.isNotEmpty) {
      _index = _index.withChanges(removedKeys: removed);
      changed = true;
    }

    _readFailures = result.readFailures;
    _walkIncomplete = !result.walkComplete && !result.cancelled;
    _phase = LibraryPhase.ready;
    _progress = null;
    _token = null;
    _notify();

    // Let a running checkpoint finish so the final write is the last one.
    await saving;
    if (_stale(gen)) return;
    if (changed || !_loadedSaved) {
      final saved = await _store.saveIndex(container, _index.tracks);
      if (!_stale(gen)) {
        _loadedSaved = saved;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRunning();
    _index = LibraryIndex.empty();
    super.dispose();
  }
}
