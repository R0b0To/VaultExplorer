import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/controllers/library_controller.dart';
import 'package:vaultexplorer/features/library/index/library_index.dart';
import 'package:vaultexplorer/features/library/index/library_scanner.dart';

class _Source {
  final MountedContainer container;
  final LibraryController controller;
  int holders = 0;

  _Source(this.container, this.controller);
}

/// Every container that has music mode on, as one library.
///
/// Each container is indexed once no matter how many file manager tabs show it
/// (two tabs on the same vault share one scan and one index). The views read
/// [index], which merges all of them: the same album split between a vault and
/// the phone is one album, an artist's tracks from both appear together, and
/// search and sorting cover everything.
///
/// A container's library exists while at least one tab holds it with music mode
/// on. Releasing the last hold disposes its controller and drops its index from
/// memory.
class MusicHub extends ChangeNotifier {
  final LibraryController Function(MountedContainer container) _createController;

  /// Called when a container's library is dropped, so per-container things the
  /// hub does not own (cover caches) can be released too.
  final void Function(String uri)? _onSourceRemoved;

  MusicHub({
    required this._createController,
    this._onSourceRemoved,
  });

  final Map<String, _Source> _sources = {};
  bool _disposed = false;

  // Memo for the merged index: rebuilt only when one of its inputs changed.
  List<LibraryIndex> _mergedFrom = const [];
  LibraryIndex _merged = LibraryIndex.empty();

  /// Containers whose library is running, in the order they were added.
  List<MountedContainer> get containers => [for (final s in _sources.values) s.container];

  int get sourceCount => _sources.length;

  bool isAttached(String uri) => _sources.containsKey(uri);

  MountedContainer? containerOf(String uri) => _sources[uri]?.container;

  LibraryController? controllerOf(String uri) => _sources[uri]?.controller;

  /// Adds one more user of [container]'s library. The first one starts it: the
  /// saved index loads at once and a scan of [folders] (empty: everything)
  /// brings it up to date.
  void attach(MountedContainer container, {List<String> folders = const []}) {
    if (_disposed) return;
    final existing = _sources[container.uri];
    if (existing != null) {
      existing.holders++;
      return;
    }
    final controller = _createController(container);
    final source = _Source(container, controller)..holders = 1;
    _sources[container.uri] = source;
    controller.addListener(_onSourceChanged);
    unawaited(controller.open(container, folders: folders));
    _notify();
  }

  /// Releases one hold. The last release drops the library from memory.
  void detach(MountedContainer container) {
    final source = _sources[container.uri];
    if (source == null) return;
    source.holders--;
    if (source.holders > 0) return;
    _sources.remove(container.uri);
    source.controller.removeListener(_onSourceChanged);
    source.controller.dispose();
    _onSourceRemoved?.call(container.uri);
    _notify();
  }

  /// Changes which folders [container] contributes, and rescans it.
  Future<void> setFolders(MountedContainer container, List<String> folders) async {
    final c = _sources[container.uri]?.controller;
    if (c == null) return;
    if (listEquals(c.folders, folders)) return;
    await c.setFolders(folders);
  }

  /// Looks for changes in every container (or re-reads every file's tags).
  Future<void> rescanAll({bool rebuild = false}) => Future.wait([
        for (final s in _sources.values) s.controller.rescan(rebuild: rebuild),
      ]);

  void cancelAll() {
    for (final s in _sources.values) {
      s.controller.cancelScan();
    }
  }

  Future<void> clearSavedIndex(MountedContainer container) async {
    await _sources[container.uri]?.controller.clearSavedIndex();
  }

  // ── Merged view ──────────────────────────────────────────────────────────

  /// All containers' tracks as one index. With a single container this is that
  /// container's own index (no copy); with several it is rebuilt only when one
  /// of them changed.
  LibraryIndex get index {
    final inputs = [for (final s in _sources.values) s.controller.index];
    if (inputs.isEmpty) return LibraryIndex.empty();
    if (inputs.length == 1) return inputs.first;
    if (_sameInstances(inputs, _mergedFrom)) return _merged;
    _merged = LibraryIndex([for (final i in inputs) ...i.tracks]);
    _mergedFrom = inputs;
    return _merged;
  }

  static bool _sameInstances(List<LibraryIndex> a, List<LibraryIndex> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  // ── Status across all containers ─────────────────────────────────────────

  bool get isScanning => _sources.values.any((s) => s.controller.isScanning);

  /// Still reading saved indexes (nothing to show yet).
  bool get isLoading =>
      _sources.values.any((s) => s.controller.phase == LibraryPhase.loading);

  /// Progress of the first container that is scanning, if any.
  LibraryScanProgress? get progress {
    for (final s in _sources.values) {
      if (s.controller.isScanning && s.controller.progress != null) {
        return s.controller.progress;
      }
    }
    return null;
  }

  bool get walkIncomplete => _sources.values.any((s) => s.controller.walkIncomplete);

  int get readFailures =>
      _sources.values.fold(0, (sum, s) => sum + s.controller.readFailures);

  void _onSourceChanged() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _sources.values) {
      s.controller.removeListener(_onSourceChanged);
      s.controller.dispose();
      _onSourceRemoved?.call(s.container.uri);
    }
    _sources.clear();
    super.dispose();
  }
}
