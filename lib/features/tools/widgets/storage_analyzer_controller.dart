// State for the Storage Analyzer.
//
// The analyzer used to scan once and show a read-only summary. It now keeps the
// whole scanned folder tree ([StorageTree]) so the screen can drill into
// folders, select things, and act on them -- and so a delete can update the
// numbers in place instead of rescanning the vault.
//
// Anything that is plain logic lives in `models/storage_tree.dart`,
// `models/storage_cleanup.dart` and `services/storage_scanner.dart` (all free
// of Flutter and unit-tested). This notifier is the thin layer that wires them
// to the engine and to Riverpod.
//
// The widget still owns the target listenables passed down from the app shell
// since that shared infrastructure is used well beyond this screen. This
// controller reacts through [onTargetsChanged] when mounted vaults or the
// permission-backed Local Storage target changes.
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/storage_cleanup.dart';
import 'package:vaultexplorer/features/tools/models/storage_tree.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/storage_scanner.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

export 'package:vaultexplorer/features/tools/models/storage_cleanup.dart'
    show CleanupKind, CleanupSuggestion;
export 'package:vaultexplorer/features/tools/models/storage_tree.dart'
    show
        StorageCategory,
        StorageNode,
        StorageSelection,
        StorageSort,
        StorageTree;
export 'package:vaultexplorer/features/tools/services/storage_scanner.dart'
    show StorageScanProgress;

part 'storage_analyzer_controller.g.dart';

const Object _unset = Object();

/// How a delete went.
class StorageDeleteResult {
  const StorageDeleteResult({
    required this.deleted,
    required this.failed,
    required this.freedBytes,
    this.readOnly = false,
  });

  static const nothing = StorageDeleteResult(
    deleted: 0,
    failed: 0,
    freedBytes: 0,
  );

  /// Items removed.
  final int deleted;

  /// Items that were not removed (failed, skipped or cancelled).
  final int failed;

  /// Bytes the volume's contents actually shrank by.
  final int freedBytes;

  /// The volume is mounted read-only; nothing was attempted.
  final bool readOnly;

  bool get isTotalSuccess => !readOnly && failed == 0 && deleted > 0;
}

class StorageAnalyzerState {
  final MountedContainer? selected;
  final bool loading;
  final int? totalBytes;
  final int? freeBytes;
  final List<StorageEntry> heaviest;
  final List<StorageCategoryBreakdown> breakdown;
  final bool truncated;
  final int scannedCount;

  /// The scanned volume; null until the first scan finishes. Mutable (deletes
  /// patch it in place) -- watch [treeVersion] to know when it changed.
  final StorageTree? tree;
  final int treeVersion;

  /// The folder being viewed ('' is the volume root).
  final String currentPath;

  /// Paths the person has ticked. Paths, not nodes, so the selection survives
  /// a folder being rescanned.
  final Set<String> selectedPaths;

  /// When set, the by-type view lists this category's files.
  final String? typeFilter;
  final StorageSort sort;

  /// Live tally while [loading].
  final StorageScanProgress? progress;
  final List<CleanupSuggestion> cleanup;

  /// Something else changed the volume since it was scanned.
  final bool stale;

  /// A delete or folder refresh is running; actions are paused.
  final bool busy;

  const StorageAnalyzerState({
    this.selected,
    this.loading = false,
    this.totalBytes,
    this.freeBytes,
    this.heaviest = const [],
    this.breakdown = const [],
    this.truncated = false,
    this.scannedCount = 0,
    this.tree,
    this.treeVersion = 0,
    this.currentPath = '',
    this.selectedPaths = const <String>{},
    this.typeFilter,
    this.sort = StorageSort.size,
    this.progress,
    this.cleanup = const [],
    this.stale = false,
    this.busy = false,
  });

  /// The folder being viewed. Falls back to the root if it no longer exists.
  StorageNode? get currentNode => tree?.find(currentPath) ?? tree?.root;

  /// What the ticked paths amount to (nested picks collapsed).
  StorageSelection get selection =>
      tree?.resolveSelection(selectedPaths) ?? StorageSelection.empty;

  bool get hasSelection => selectedPaths.isNotEmpty;

  /// Some folders could not be read, or were listed only in part.
  bool get hasUnreadable =>
      tree != null && (tree!.unreadableDirs > 0 || tree!.incompleteDirs > 0);

  /// Whether the person may delete from this volume.
  bool get canModify => selected != null && !selected!.readOnly;

  StorageAnalyzerState copyWith({
    bool? loading,
    int? totalBytes,
    int? freeBytes,
    List<StorageEntry>? heaviest,
    List<StorageCategoryBreakdown>? breakdown,
    bool? truncated,
    int? scannedCount,
    StorageTree? tree,
    int? treeVersion,
    String? currentPath,
    Set<String>? selectedPaths,
    Object? typeFilter = _unset,
    StorageSort? sort,
    Object? progress = _unset,
    List<CleanupSuggestion>? cleanup,
    bool? stale,
    bool? busy,
  }) {
    return StorageAnalyzerState(
      selected: selected,
      loading: loading ?? this.loading,
      totalBytes: totalBytes ?? this.totalBytes,
      freeBytes: freeBytes ?? this.freeBytes,
      heaviest: heaviest ?? this.heaviest,
      breakdown: breakdown ?? this.breakdown,
      truncated: truncated ?? this.truncated,
      scannedCount: scannedCount ?? this.scannedCount,
      tree: tree ?? this.tree,
      treeVersion: treeVersion ?? this.treeVersion,
      currentPath: currentPath ?? this.currentPath,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      typeFilter: identical(typeFilter, _unset)
          ? this.typeFilter
          : typeFilter as String?,
      sort: sort ?? this.sort,
      progress: identical(progress, _unset)
          ? this.progress
          : progress as StorageScanProgress?,
      cleanup: cleanup ?? this.cleanup,
      stale: stale ?? this.stale,
      busy: busy ?? this.busy,
    );
  }
}

@riverpod
class StorageAnalyzer extends _$StorageAnalyzer {
  static const _heaviestLimit = 10;
  static const _progressInterval = Duration(milliseconds: 120);

  /// Bumped by every new scan (and on dispose) so a scan or delete that is
  /// still in flight can tell that it has been superseded.
  int _generation = 0;
  DateTime _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Delete operations this notifier started, so their own "volume changed"
  /// announcement is not mistaken for someone else's edit.
  final Set<int> _ownOpIds = <int>{};
  void Function(VolumeContentChange)? _changeListener;

  // Per-tree-version caches for lists the UI asks for on every rebuild.
  int _cacheVersion = -1;
  final Map<String, List<StorageNode>> _listCache = {};

  @override
  StorageAnalyzerState build() {
    ref.onDispose(() => _generation++);
    return const StorageAnalyzerState();
  }

  /// Reacts to the available analyzer targets changing: clears results if
  /// there are none, or re-targets if the selected storage is no longer
  /// available.
  void onMountedListChanged(List<MountedContainer> list) =>
      onTargetsChanged(list);

  /// Same as [onMountedListChanged], with a name that includes Local Storage.
  void onTargetsChanged(List<MountedContainer> list) {
    final selected = state.selected;
    if (list.isEmpty) {
      _generation++;
      state = const StorageAnalyzerState();
    } else if (selected == null ||
        !list.any((c) => c.volId == selected.volId && c.uri == selected.uri)) {
      unawaited(selectTarget(list.first));
    }
  }

  Future<void> selectTarget(MountedContainer container) async {
    state = StorageAnalyzerState(selected: container);
    await load();
  }

  /// Scans the selected volume from scratch. [restorePath] is where to return
  /// to afterwards if it still exists (used by "rescan"). [refresh] bypasses
  /// the engine's directory-listing cache (SAF volumes keep one), so a rescan
  /// sees what is really on disk.
  Future<void> load({String restorePath = '', bool refresh = false}) async {
    final target = state.selected;
    if (target == null) return;
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final gen = ++_generation;

    state = StorageAnalyzerState(selected: target, loading: true);

    var total = target.totalSpace;
    var free = target.freeSpace;
    try {
      final space = await fileIoApi.getSpaceInfo(target);
      if (space != null && space.length > 1) {
        if (space[0] >= 0) total = space[0];
        if (space[1] >= 0) free = space[1];
      }
    } catch (_) {
      // total/free above already default to target.totalSpace/freeSpace;
      // a failure here just means the analyzer falls back to those instead
      // of the (possibly more precise) native-reported figures.
    }
    if (!_isCurrent(gen)) return;

    final tree = await StorageScanner(
      listDirectory: (path) =>
          fileIoApi.listDirectory(target, path, refresh: refresh),
      isCancelled: () => !_isCurrent(gen),
      onProgress: (p) {
        if (!_isCurrent(gen)) return;
        final now = DateTime.now();
        if (now.difference(_lastProgressAt) < _progressInterval) return;
        _lastProgressAt = now;
        state = state.copyWith(progress: p);
      },
    ).scan();

    // A newer scan, a different target or a disposed screen supersedes this
    // walk; drop its results rather than let a stale one clobber a newer one.
    if (!_isCurrent(gen)) return;

    state = state.copyWith(totalBytes: total, freeBytes: free);
    _publish(
      tree,
      currentPath: _nearestExisting(tree, restorePath),
      clearProgress: true,
    );
  }

  /// Scans everything again, returning to the current folder if it survives.
  Future<void> rescan() =>
      load(restorePath: state.currentPath, refresh: true);

  bool _isCurrent(int gen) => ref.mounted && gen == _generation;

  // ── Derived data ─────────────────────────────────────────────────────────

  void _publish(
    StorageTree tree, {
    String? currentPath,
    bool clearProgress = false,
  }) {
    final heaviest = [
      for (final f in tree.largestFiles(_heaviestLimit))
        StorageEntry(path: f.path, name: f.name, sizeBytes: f.sizeBytes),
    ];
    final breakdown = [
      for (final e in tree.categoryTotals().entries)
        StorageCategoryBreakdown(
          category: e.key,
          sizeBytes: e.value.bytes,
          fileCount: e.value.count,
        ),
    ]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final cleanup = CleanupAnalyzer.analyze(
      tree,
      nowSecs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final keepPath = _nearestExisting(tree, currentPath ?? state.currentPath);
    final stillThere = {
      for (final p in state.selectedPaths)
        if (tree.find(p) != null) p,
    };
    final filter = state.typeFilter;

    state = state.copyWith(
      loading: false,
      busy: false,
      tree: tree,
      treeVersion: state.treeVersion + 1,
      heaviest: heaviest,
      breakdown: breakdown,
      truncated: tree.truncated,
      scannedCount: tree.fileCount,
      cleanup: cleanup,
      currentPath: keepPath,
      selectedPaths: stillThere,
      // A category with no files left has nothing to list.
      typeFilter: filter != null && !breakdown.any((b) => b.category == filter)
          ? null
          : filter,
      progress: clearProgress ? null : _unset,
    );
  }

  /// The deepest existing folder along [path] (the root if none).
  static String _nearestExisting(StorageTree tree, String path) {
    var p = path;
    while (p.isNotEmpty) {
      final n = tree.find(p);
      if (n != null && n.isDir) return p;
      final slash = p.lastIndexOf('/');
      p = slash < 0 ? '' : p.substring(0, slash);
    }
    return '';
  }

  void _resetCaches() {
    if (_cacheVersion == state.treeVersion) return;
    _cacheVersion = state.treeVersion;
    _listCache.clear();
  }

  /// The biggest files of one category, largest first.
  List<StorageNode> filesOfType(String category, {int limit = 300}) {
    final tree = state.tree;
    if (tree == null) return const <StorageNode>[];
    _resetCaches();
    return _listCache.putIfAbsent(
      'type:$category:$limit',
      () => tree.largestFiles(limit, where: (f) => f.category == category),
    );
  }

  /// The biggest files on the volume, largest first.
  List<StorageNode> topFiles({int limit = 100}) {
    final tree = state.tree;
    if (tree == null) return const <StorageNode>[];
    _resetCaches();
    return _listCache.putIfAbsent('top:$limit', () => tree.largestFiles(limit));
  }

  // ── Navigation & selection ───────────────────────────────────────────────

  void openFolder(String path) {
    final node = state.tree?.find(path);
    if (node == null || !node.isDir) return;
    state = state.copyWith(currentPath: path);
  }

  void goUp() {
    final up = state.currentNode?.parent;
    if (up == null) return;
    state = state.copyWith(currentPath: up.path);
  }

  void setSort(StorageSort sort) => state = state.copyWith(sort: sort);

  void setTypeFilter(String? category) =>
      state = state.copyWith(typeFilter: category);

  void toggleSelected(String path) {
    if (path.isEmpty) return;
    final next = <String>{...state.selectedPaths};
    if (!next.remove(path)) next.add(path);
    state = state.copyWith(selectedPaths: next);
  }

  /// Ticks [paths] in addition to what is already ticked.
  void addSelected(Iterable<String> paths) {
    state = state.copyWith(
      selectedPaths: {
        ...state.selectedPaths,
        ...paths.where((p) => p.isNotEmpty),
      },
    );
  }

  void setSelected(Iterable<String> paths) {
    state = state.copyWith(
      selectedPaths: {...paths.where((p) => p.isNotEmpty)},
    );
  }

  void clearSelection() {
    if (state.selectedPaths.isEmpty) return;
    state = state.copyWith(selectedPaths: const <String>{});
  }

  // ── Keeping up with the volume ───────────────────────────────────────────

  /// Starts noticing when something other than this screen changes the
  /// selected volume (a delete in the file browser, say), so the numbers can
  /// be flagged as out of date. Safe to call more than once.
  void watchContentChanges() {
    if (_changeListener != null) return;
    final service = ref.read(fileOperationServiceProvider);
    void listener(VolumeContentChange change) {
      if (!ref.mounted) return;
      if (change.volId != state.selected?.volId) return;
      if (_ownOpIds.contains(change.opId)) return;
      if (!state.stale) state = state.copyWith(stale: true);
    }

    _changeListener = listener;
    service.addVolumeContentChangedListener(listener);
    ref.onDispose(() => service.removeVolumeContentChangedListener(listener));
  }

  Future<void> _refreshSpace() async {
    final target = state.selected;
    if (target == null) return;
    final gen = _generation;
    try {
      final space = await ref.read(vaultFileIoApiProvider).getSpaceInfo(target);
      if (!_isCurrent(gen) || space == null || space.length < 2) return;
      state = state.copyWith(
        totalBytes: space[0] >= 0 ? space[0] : null,
        freeBytes: space[1] >= 0 ? space[1] : null,
      );
    } catch (_) {
      // Purely cosmetic: the gauge keeps its previous figures.
    }
  }

  /// Rescans one folder and patches it into the tree, without publishing.
  /// Returns false if the folder is gone or the tree was replaced meanwhile.
  Future<bool> _rescanFolderInto(StorageTree tree, String path, int gen) async {
    final target = state.selected;
    if (target == null) return false;
    final old = tree.find(path);
    if (old == null || !old.isDir) return false;
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final outcome =
        await StorageScanner(
          listDirectory: (p) =>
              fileIoApi.listDirectory(target, p, refresh: true),
          isCancelled: () => !_isCurrent(gen),
        ).scanFolder(
          name: old.name,
          path: old.path,
          modifiedSecs: old.modifiedSecs,
        );
    if (!_isCurrent(gen) || !identical(state.tree, tree)) return false;
    if (!tree.replace(old, outcome.node)) return false;
    // Only ever worsen the verdict: the counters are not tracked per folder, so
    // a clean refresh cannot prove an earlier problem elsewhere is gone.
    tree.truncated = tree.truncated || outcome.truncated;
    tree.unreadableDirs += outcome.unreadableDirs;
    tree.incompleteDirs += outcome.incompleteDirs;
    return true;
  }

  /// Rescans just the folder at [path] and updates every total above it.
  Future<void> refreshFolder(String path) async {
    final tree = state.tree;
    if (tree == null || state.busy || state.loading) return;
    if (path.isEmpty) return rescan();
    final gen = _generation;
    state = state.copyWith(busy: true);
    try {
      await _rescanFolderInto(tree, path, gen);
    } finally {
      if (_isCurrent(gen) && identical(state.tree, tree)) {
        _publish(tree);
        unawaited(_refreshSpace());
      }
    }
  }

  // ── Acting on results ────────────────────────────────────────────────────

  /// Permanently deletes [nodes] from the volume through the same background
  /// operation the file browser uses (so it shows in the activity pill, is
  /// batched natively, and is announced to every other view of the volume).
  ///
  /// Afterwards the tree is brought up to date without a full rescan:
  /// everything that was deleted is removed, and any folder the engine could
  /// only partly delete is rescanned so its numbers are true.
  Future<StorageDeleteResult> deleteNodes(
    List<StorageNode> nodes,
    AppLocalizations l10n,
  ) async {
    final target = state.selected;
    final tree = state.tree;
    if (target == null || tree == null || nodes.isEmpty || state.busy) {
      return StorageDeleteResult.nothing;
    }
    if (target.readOnly) {
      return const StorageDeleteResult(
        deleted: 0,
        failed: 0,
        freedBytes: 0,
        readOnly: true,
      );
    }

    final gen = _generation;
    final bytesBefore = tree.totalBytes;
    final byPath = {for (final n in nodes) n.path: n};
    state = state.copyWith(busy: true);
    try {
      return await _runDelete(
        target: target,
        tree: tree,
        nodes: nodes,
        byPath: byPath,
        bytesBefore: bytesBefore,
        gen: gen,
        l10n: l10n,
      );
    } catch (_) {
      // Never leave the screen locked behind a failed delete; the caller
      // still sees the error.
      if (_isCurrent(gen) && state.busy) state = state.copyWith(busy: false);
      rethrow;
    }
  }

  Future<StorageDeleteResult> _runDelete({
    required MountedContainer target,
    required StorageTree tree,
    required List<StorageNode> nodes,
    required Map<String, StorageNode> byPath,
    required int bytesBefore,
    required int gen,
    required AppLocalizations l10n,
  }) async {
    final op = ref
        .read(fileOperationServiceProvider)
        .enqueueDelete(
          container: target,
          items: [
            for (final n in nodes)
              ClipboardItem(
                path: n.path,
                isDir: n.isDir,
                sizeBytes: n.sizeBytes,
                modifiedSecs: n.modifiedSecs,
              ),
          ],
          locationLabel: '',
          l10n: l10n,
        );
    _ownOpIds.add(op.id);

    final finished = Completer<void>();
    void onOpChanged() {
      final done =
          op.status != FileOperationStatus.pending &&
          op.status != FileOperationStatus.running;
      if (!done) return;
      op.removeListener(onOpChanged);
      if (!finished.isCompleted) finished.complete();
    }

    op.addListener(onOpChanged);
    onOpChanged();
    await finished.future;

    if (!_isCurrent(gen) || !identical(state.tree, tree)) {
      // The screen was closed or the volume rescanned while deleting; the new
      // tree already reflects the outcome.
      return StorageDeleteResult.nothing;
    }

    var deleted = 0;
    var failed = 0;
    final partialFolders = <String>[];
    for (final status in op.itemStatuses) {
      final node = byPath[status.item.path];
      if (status.result == FileItemResult.success) {
        deleted++;
        if (node != null) tree.remove(node);
      } else {
        failed++;
        // A folder that failed may still have lost some of its contents.
        if (node != null && node.isDir) partialFolders.add(node.path);
      }
    }
    for (final path in partialFolders) {
      await _rescanFolderInto(tree, path, gen);
      if (!_isCurrent(gen) || !identical(state.tree, tree)) {
        return StorageDeleteResult.nothing;
      }
    }

    _publish(tree);
    unawaited(_refreshSpace());
    return StorageDeleteResult(
      deleted: deleted,
      failed: failed,
      freedBytes: bytesBefore - tree.totalBytes,
    );
  }
}
