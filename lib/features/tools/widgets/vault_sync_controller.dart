import 'dart:async';
import 'dart:ui';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/filesystem/file_size.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_pins_bookmarks_controller.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/services/vault_sync_service.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'vault_sync_controller.g.dart';

/// Which differences the results list shows.
enum VaultSyncFilter {
  all,
  onlyLeft,
  onlyRight,

  /// Present on both sides, one copy newer.
  newer,

  /// Needs the person to decide (same time but different size, or a
  /// file-versus-folder mismatch).
  conflicts,

  /// Entries the current plan will delete.
  deletions,
}

/// How the results list is ordered.
enum VaultSyncSort { path, size, modified, status }

/// Completes once [op] has finished, however it ended.
Future<void> waitForFileOperation(FileOperation op) {
  bool isDone() =>
      op.status != FileOperationStatus.pending &&
      op.status != FileOperationStatus.running;
  final completer = Completer<void>();
  if (isDone()) {
    completer.complete();
    return completer.future;
  }
  late final VoidCallback listener;
  listener = () {
    if (!isDone()) return;
    op.removeListener(listener);
    if (!completer.isCompleted) completer.complete();
  };
  op.addListener(listener);
  return completer.future;
}

class VaultSyncState {
  final VaultSyncSide? left;
  final VaultSyncSide? right;
  final bool isComparing;
  final VaultSyncScanProgress progress;
  final List<VaultDiffEntry> entries;
  final int identicalCount;
  final SyncDirection direction;
  final Map<String, EntryAction> overrides;
  final bool isSyncing;
  final VaultSyncFilter filter;
  final VaultSyncSort sort;

  /// Entry ids ticked for a bulk action. Empty = not in selection mode.
  final Set<String> selectedIds;

  /// A delete changed things the comparison can't account for (an in-sync
  /// file or a folder present on both sides), so the counts may be off until
  /// the next compare.
  final bool resultsStale;

  /// Both sides are chosen but point at the same folder, or one sits inside
  /// the other -- syncing them would copy a folder into itself.
  bool get sidesOverlap {
    final l = left;
    final r = right;
    return l != null && r != null && l.overlapsWith(r);
  }

  bool get canCompare => left != null && right != null && !sidesOverlap;

  const VaultSyncState({
    this.left,
    this.right,
    this.isComparing = false,
    this.progress = const VaultSyncScanProgress(stage: VaultSyncScanStage.idle),
    this.entries = const [],
    this.identicalCount = 0,
    this.direction = SyncDirection.twoWay,
    this.overrides = const {},
    this.isSyncing = false,
    this.filter = VaultSyncFilter.all,
    this.sort = VaultSyncSort.path,
    this.selectedIds = const {},
    this.resultsStale = false,
  });

  VaultSyncState _copy({
    VaultSyncSide? left,
    bool clearLeft = false,
    VaultSyncSide? right,
    bool clearRight = false,
    bool? isComparing,
    VaultSyncScanProgress? progress,
    List<VaultDiffEntry>? entries,
    int? identicalCount,
    SyncDirection? direction,
    Map<String, EntryAction>? overrides,
    bool? isSyncing,
    VaultSyncFilter? filter,
    VaultSyncSort? sort,
    Set<String>? selectedIds,
    bool? resultsStale,
  }) => VaultSyncState(
    left: clearLeft ? null : (left ?? this.left),
    right: clearRight ? null : (right ?? this.right),
    isComparing: isComparing ?? this.isComparing,
    progress: progress ?? this.progress,
    entries: entries ?? this.entries,
    identicalCount: identicalCount ?? this.identicalCount,
    direction: direction ?? this.direction,
    overrides: overrides ?? this.overrides,
    isSyncing: isSyncing ?? this.isSyncing,
    filter: filter ?? this.filter,
    sort: sort ?? this.sort,
    selectedIds: selectedIds ?? this.selectedIds,
    resultsStale: resultsStale ?? this.resultsStale,
  );
}

@riverpod
class VaultSync extends _$VaultSync {
  late VaultSyncService _service;
  VaultSyncCancellationToken? _cancelToken;

  @override
  VaultSyncState build() {
    _service = VaultSyncService(ref.watch(vaultFileIoApiProvider));
    ref.onDispose(() {
      _cancelToken?.cancel();
    });
    return const VaultSyncState();
  }

  void initDefaultSides(List<MountedContainer> containers) {
    if (state.left == null && containers.isNotEmpty) {
      final leftSide = VaultSyncSide(
        container: containers.first,
        relativePath: '',
      );
      final rightSide = containers.length > 1
          ? VaultSyncSide(container: containers[1], relativePath: '')
          : null;
      state = state._copy(left: leftSide, right: rightSide);
    }
  }

  void setSide({required bool isLeft, required VaultSyncSide side}) {
    state = isLeft ? state._copy(left: side) : state._copy(right: side);
    resetResults();
  }

  void swapSides() {
    state = state._copy(left: state.right, right: state.left);
    resetResults();
  }

  void resetResults() {
    _cancelToken?.cancel();
    state = state._copy(
      isComparing: false,
      entries: const [],
      identicalCount: 0,
      overrides: const {},
      selectedIds: const {},
      resultsStale: false,
      progress: const VaultSyncScanProgress(stage: VaultSyncScanStage.idle),
    );
  }

  void setDirection(SyncDirection dir) {
    state = state._copy(direction: dir, overrides: const {});
  }

  void setOverride(String entryId, EntryAction action) {
    final newOverrides = Map<String, EntryAction>.from(state.overrides)
      ..[entryId] = action;
    state = state._copy(overrides: Map.unmodifiable(newOverrides));
  }

  EntryAction actionFor(VaultDiffEntry e) {
    final override = state.overrides[e.id];
    var action = override ?? _service.defaultAction(e, state.direction);
    if (action == EntryAction.copyToRight &&
        (state.right?.container.readOnly ?? false)) {
      action = EntryAction.skip;
    }
    if (action == EntryAction.copyToLeft &&
        (state.left?.container.readOnly ?? false)) {
      action = EntryAction.skip;
    }
    if (action == EntryAction.deleteRight &&
        (state.right?.container.readOnly ?? false)) {
      action = EntryAction.skip;
    }
    if (action == EntryAction.deleteLeft &&
        (state.left?.container.readOnly ?? false)) {
      action = EntryAction.skip;
    }
    return action;
  }

  /// Whether [action] makes sense for [e] right now: the side it would copy
  /// from (or delete on) must actually hold the entry, a file-versus-folder
  /// mismatch can't be copied over, and a read-only side can't be changed.
  /// Menus offer only the actions this allows.
  bool canApply(VaultDiffEntry e, EntryAction action) {
    final leftReadOnly = state.left?.container.readOnly ?? false;
    final rightReadOnly = state.right?.container.readOnly ?? false;
    // Nothing to copy for a file that is already in sync, and a folder
    // present on both sides is synced by comparing what is inside it.
    if (action.isCopy &&
        (e.status == VaultDiffStatus.identical ||
            e.status == VaultDiffStatus.bothFolders)) {
      return false;
    }
    return switch (action) {
      EntryAction.skip => true,
      EntryAction.copyToRight =>
        e.existsOnLeft && !e.typeMismatch && !rightReadOnly,
      EntryAction.copyToLeft =>
        e.existsOnRight && !e.typeMismatch && !leftReadOnly,
      EntryAction.deleteLeft => e.existsOnLeft && !leftReadOnly,
      EntryAction.deleteRight => e.existsOnRight && !rightReadOnly,
    };
  }

  // ── Filter / sort / selection ─────────────────────────────────────────────

  void setFilter(VaultSyncFilter filter) {
    state = state._copy(filter: filter);
  }

  void setSort(VaultSyncSort sort) {
    state = state._copy(sort: sort);
  }

  /// The result entries after applying the filter and the sort order.
  List<VaultDiffEntry> visibleEntries() {
    bool matches(VaultDiffEntry e) {
      return switch (state.filter) {
        VaultSyncFilter.all => true,
        VaultSyncFilter.onlyLeft => e.status == VaultDiffStatus.onlyLeft,
        VaultSyncFilter.onlyRight => e.status == VaultDiffStatus.onlyRight,
        VaultSyncFilter.newer =>
          e.status == VaultDiffStatus.leftNewer ||
              e.status == VaultDiffStatus.rightNewer,
        VaultSyncFilter.conflicts => e.status == VaultDiffStatus.conflicted,
        VaultSyncFilter.deletions => actionFor(e).isDelete,
      };
    }

    int bigger(int? a, int? b) => (a ?? 0) > (b ?? 0) ? (a ?? 0) : (b ?? 0);
    final list = state.entries.where(matches).toList();
    switch (state.sort) {
      case VaultSyncSort.path:
        break; // scanDiff already returns entries sorted by path.
      case VaultSyncSort.size:
        list.sort(
          (a, b) => bigger(
            b.leftSizeBytes,
            b.rightSizeBytes,
          ).compareTo(bigger(a.leftSizeBytes, a.rightSizeBytes)),
        );
      case VaultSyncSort.modified:
        list.sort(
          (a, b) => bigger(
            b.leftModifiedSecs,
            b.rightModifiedSecs,
          ).compareTo(bigger(a.leftModifiedSecs, a.rightModifiedSecs)),
        );
      case VaultSyncSort.status:
        list.sort((a, b) {
          final byStatus = a.status.index.compareTo(b.status.index);
          return byStatus != 0
              ? byStatus
              : a.relativePath.compareTo(b.relativePath);
        });
    }
    return list;
  }

  void toggleSelected(String id) {
    final next = {...state.selectedIds};
    if (!next.remove(id)) next.add(id);
    state = state._copy(selectedIds: Set.unmodifiable(next));
  }

  void selectIds(Iterable<String> ids) {
    state = state._copy(selectedIds: Set.unmodifiable({...ids}));
  }

  void clearSelection() {
    if (state.selectedIds.isEmpty) return;
    state = state._copy(selectedIds: const {});
  }

  /// Sets [action] on every entry in [ids] it applies to (see [canApply]),
  /// leaving the others as they were. Returns how many were changed.
  int setOverrides(Iterable<String> ids, EntryAction action) {
    final byId = {for (final e in state.entries) e.id: e};
    final next = Map<String, EntryAction>.from(state.overrides);
    var changed = 0;
    for (final id in ids) {
      final entry = byId[id];
      if (entry == null || !canApply(entry, action)) continue;
      next[id] = action;
      changed++;
    }
    if (changed > 0) state = state._copy(overrides: Map.unmodifiable(next));
    return changed;
  }

  /// How many entries the current plan would delete.
  int pendingDeleteCount() =>
      state.entries.where((e) => actionFor(e).isDelete).length;

  /// Display labels of the non-vault sides that would receive files copied
  /// out of an encrypted vault under the current plan. Empty when nothing
  /// leaves a vault for plain storage. Used to warn before syncing.
  List<String> plaintextExportTargets() {
    final left = state.left;
    final right = state.right;
    if (left == null || right == null) return const [];
    return _service
        .plaintextDestinations(
          left: left,
          right: right,
          actions: state.entries.map(actionFor),
        )
        .map((side) => side.displayLabel)
        .toList();
  }

  Future<void> startCompare() async {
    final left = state.left;
    final right = state.right;
    if (left == null || right == null || left.overlapsWith(right)) return;

    _cancelToken?.cancel();
    final token = VaultSyncCancellationToken();
    _cancelToken = token;

    state = state._copy(
      isComparing: true,
      entries: const [],
      identicalCount: 0,
      overrides: const {},
      selectedIds: const {},
      resultsStale: false,
      progress: const VaultSyncScanProgress(
        stage: VaultSyncScanStage.comparing,
      ),
    );

    await for (final update in _service.scanDiff(
      left: left,
      right: right,
      cancelToken: token,
    )) {
      if (!ref.mounted) return;
      final isDone =
          update.progress.stage == VaultSyncScanStage.complete ||
          update.progress.stage == VaultSyncScanStage.cancelled ||
          update.progress.stage == VaultSyncScanStage.failed;

      state = state._copy(
        progress: update.progress,
        entries: update.entries,
        identicalCount: update.identicalCount,
        isComparing: !isDone,
      );
    }
  }

  void cancelCompare() {
    _cancelToken?.cancel();
    state = state._copy(isComparing: false);
  }

  Future<List<String>> checkAvailableSpace({
    required int bytesToLeft,
    required int bytesToRight,
    required AppLocalizations l10n,
  }) async {
    final problems = <String>[];
    final left = state.left;
    final right = state.right;
    if (left == null || right == null) return problems;

    if (bytesToRight > 0) {
      final free = await _service.freeSpaceBytes(right.container);
      if (free != null && !fitsWithinSpaceSafetyMargin(bytesToRight, free)) {
        problems.add(
          l10n.vaultSyncNotEnoughSpaceMessage(
            right.displayLabel,
            formatBytes(bytesToRight),
            formatBytes(free),
          ),
        );
      }
    }
    if (bytesToLeft > 0) {
      final free = await _service.freeSpaceBytes(left.container);
      if (free != null && !fitsWithinSpaceSafetyMargin(bytesToLeft, free)) {
        problems.add(
          l10n.vaultSyncNotEnoughSpaceMessage(
            left.displayLabel,
            formatBytes(bytesToLeft),
            formatBytes(free),
          ),
        );
      }
    }
    return problems;
  }

  void executeSync(AppLocalizations l10n) {
    final left = state.left;
    final right = state.right;
    if (left == null || right == null) return;

    state = state._copy(isSyncing: true);

    final plan = <String, EntryAction>{
      for (final e in state.entries) e.id: actionFor(e),
    };

    final ops = _service.executeSync(
      left: left,
      right: right,
      entries: state.entries,
      plan: plan,
      l10n: l10n,
      fileOperationService: ref.read(fileOperationServiceProvider),
    );

    if (ops.isEmpty) {
      state = state._copy(isSyncing: false);
      return;
    }

    var remaining = ops.length;
    for (final op in ops) {
      late final VoidCallback listener;
      listener = () {
        final done =
            op.status != FileOperationStatus.pending &&
            op.status != FileOperationStatus.running;
        if (!done) return;
        op.removeListener(listener);
        remaining--;
        if (remaining <= 0 && ref.mounted) {
          state = state._copy(isSyncing: false);
          startCompare();
        }
      };
      op.addListener(listener);
    }
  }

  // ── Copying right now ─────────────────────────────────────────────────────

  /// Copies [entries] to the other side right now (not as part of a sync) and
  /// waits for the copies to finish. Returns how many of the copy operations
  /// ended with a failure; 0 means everything was copied.
  Future<int> copyNow({
    required bool toRight,
    required List<VaultDiffEntry> entries,
    required AppLocalizations l10n,
  }) async {
    final left = state.left;
    final right = state.right;
    if (left == null || right == null || entries.isEmpty) return 0;
    final action = toRight ? EntryAction.copyToRight : EntryAction.copyToLeft;
    final copyable = entries.where((e) => canApply(e, action)).toList();
    if (copyable.isEmpty) return 0;

    final ops = _service.executeSync(
      left: left,
      right: right,
      entries: copyable,
      plan: {for (final e in copyable) e.id: action},
      l10n: l10n,
      fileOperationService: ref.read(fileOperationServiceProvider),
    );
    await Future.wait(ops.map(waitForFileOperation));
    if (!ref.mounted) return 0;
    return ops
        .where(
          (op) =>
              op.failCount > 0 || op.status == FileOperationStatus.failed,
        )
        .length;
  }

  // ── Deleting ──────────────────────────────────────────────────────────────

  /// Permanently deletes [entries] from one side right now (not as part of a
  /// sync) and waits for the delete to finish.
  ///
  /// Entries that were deleted are taken out of the results in place -- a
  /// file that existed on both sides becomes "only on the other side" -- so
  /// the plan and per-entry choices the person already made are kept. Bookmarks
  /// and pins on the deleted paths are forgotten, as in the file browser.
  ///
  /// Returns how many items were deleted and how many failed. Does nothing
  /// (0 / 0) if the side is missing or read-only; the UI checks that first.
  Future<({int deleted, int failed})> deleteNow({
    required bool fromLeft,
    required List<VaultDiffEntry> entries,
    required AppLocalizations l10n,
  }) async {
    final side = fromLeft ? state.left : state.right;
    if (side == null || side.container.readOnly || entries.isEmpty) {
      return (deleted: 0, failed: 0);
    }
    final op = _service.deleteEntries(
      side: side,
      sideIsLeft: fromLeft,
      entries: entries,
      l10n: l10n,
      fileOperationService: ref.read(fileOperationServiceProvider),
    );
    if (op == null) return (deleted: 0, failed: 0);

    await waitForFileOperation(op);
    if (!ref.mounted) return (deleted: 0, failed: 0);

    final deletedRel = <String>{
      for (final status in op.itemStatuses)
        if (status.result == FileItemResult.success)
          _relativeTo(side, status.item.path),
    };
    final failed = op.itemStatuses
        .where((s) => s.result == FileItemResult.failed)
        .length;

    if (deletedRel.isNotEmpty) {
      final survivors = <VaultDiffEntry>[];
      for (final e in state.entries) {
        final gone = deletedRel.any(
          (d) => e.relativePath == d || e.relativePath.startsWith('$d/'),
        );
        if (!gone) {
          survivors.add(e);
          continue;
        }
        final remaining = _withoutSide(e, left: fromLeft);
        if (remaining != null) survivors.add(remaining);
      }
      final survivingIds = {for (final e in survivors) e.id};
      final stale = entries.any(
        (e) =>
            e.status == VaultDiffStatus.identical ||
            e.status == VaultDiffStatus.bothFolders,
      );
      state = state._copy(
        entries: List.unmodifiable(survivors),
        overrides: Map.unmodifiable({
          for (final o in state.overrides.entries)
            if (survivingIds.contains(o.key)) o.key: o.value,
        }),
        selectedIds: Set.unmodifiable(
          state.selectedIds.where(survivingIds.contains),
        ),
        resultsStale: state.resultsStale || stale,
      );

      // Marks inside a vault are stored by absolute path in that container.
      final container = side.container;
      final absolute = {
        for (final status in op.itemStatuses)
          if (status.result == FileItemResult.success) status.item.path,
      };
      try {
        await ref
            .read(fileBrowserPinsBookmarksProvider(container.volId).notifier)
            .removeDeletedPaths(container, absolute);
      } catch (_) {
        // Marks are a convenience; a failure here must not undo the delete.
      }
    }
    return (deleted: deletedRel.length, failed: failed);
  }

  /// [e] as it looks once its copy on one side is gone, or null when it
  /// existed only there.
  VaultDiffEntry? _withoutSide(VaultDiffEntry e, {required bool left}) {
    if (left) {
      if (!e.existsOnLeft) return e;
      if (!e.existsOnRight) return null;
      return VaultDiffEntry(
        relativePath: e.relativePath,
        name: e.name,
        // For a file-versus-folder mismatch, isDir described the left side.
        isDir: e.typeMismatch ? !e.isDir : e.isDir,
        status: VaultDiffStatus.onlyRight,
        rightSizeBytes: e.rightSizeBytes,
        rightModifiedSecs: e.rightModifiedSecs,
      );
    }
    if (!e.existsOnRight) return e;
    if (!e.existsOnLeft) return null;
    return VaultDiffEntry(
      relativePath: e.relativePath,
      name: e.name,
      isDir: e.isDir,
      status: VaultDiffStatus.onlyLeft,
      leftSizeBytes: e.leftSizeBytes,
      leftModifiedSecs: e.leftModifiedSecs,
    );
  }

  /// [absolute] (a container path under [side]'s root) relative to that root.
  String _relativeTo(VaultSyncSide side, String absolute) {
    final root = side.relativePath;
    if (root.isEmpty || !absolute.startsWith('$root/')) return absolute;
    return absolute.substring(root.length + 1);
  }
}
