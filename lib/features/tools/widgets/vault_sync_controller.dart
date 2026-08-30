import 'dart:async';
import 'dart:ui';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/services/vault_sync_service.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'vault_sync_controller.g.dart';

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

  bool get canCompare => left != null && right != null && left != right;

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
  );
}

@riverpod
class VaultSync extends _$VaultSync {
  final _service = VaultSyncService();
  VaultSyncCancellationToken? _cancelToken;

  @override
  VaultSyncState build() {
    ref.onDispose(() {
      _cancelToken?.cancel();
    });
    return const VaultSyncState();
  }

  void initDefaultSides(List<MountedContainer> containers) {
    if (state.left == null && containers.isNotEmpty) {
      final leftSide = VaultSyncSide(container: containers.first, relativePath: '');
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
    state = state._copy(
      left: state.right,
      right: state.left,
    );
    resetResults();
  }

  void resetResults() {
    _cancelToken?.cancel();
    state = state._copy(
      isComparing: false,
      entries: const [],
      identicalCount: 0,
      overrides: const {},
      progress: const VaultSyncScanProgress(stage: VaultSyncScanStage.idle),
    );
  }

  void setDirection(SyncDirection dir) {
    state = state._copy(direction: dir, overrides: const {});
  }

  void setOverride(String entryId, EntryAction action) {
    final newOverrides = Map<String, EntryAction>.from(state.overrides)..[entryId] = action;
    state = state._copy(overrides: Map.unmodifiable(newOverrides));
  }

  EntryAction actionFor(VaultDiffEntry e) {
    final override = state.overrides[e.id];
    var action = override ?? _service.defaultAction(e, state.direction);
    if (action == EntryAction.copyToRight && (state.right?.container.readOnly ?? false)) {
      action = EntryAction.skip;
    }
    if (action == EntryAction.copyToLeft && (state.left?.container.readOnly ?? false)) {
      action = EntryAction.skip;
    }
    return action;
  }

  Future<void> startCompare() async {
    final left = state.left;
    final right = state.right;
    if (left == null || right == null || left == right) return;

    _cancelToken?.cancel();
    final token = VaultSyncCancellationToken();
    _cancelToken = token;

    state = state._copy(
      isComparing: true,
      entries: const [],
      identicalCount: 0,
      overrides: const {},
      progress: const VaultSyncScanProgress(stage: VaultSyncScanStage.comparing),
    );

    await for (final update in _service.scanDiff(
      left: left,
      right: right,
      cancelToken: token,
    )) {
      if (!ref.mounted) return;
      final isDone = update.progress.stage == VaultSyncScanStage.complete ||
          update.progress.stage == VaultSyncScanStage.cancelled;

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
      if (free != null && bytesToRight > (free * 0.95).floor()) {
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
      if (free != null && bytesToLeft > (free * 0.95).floor()) {
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
        final done = op.status != FileOperationStatus.pending &&
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
}