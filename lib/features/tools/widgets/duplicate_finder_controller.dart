import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/duplicate_finder_models.dart';
import 'package:vaultexplorer/features/tools/services/duplicate_finder_service.dart';

part 'duplicate_finder_controller.g.dart';

class DuplicateFinderState {
  final int selectedTargetVolId;
  final bool isScanning;
  final DuplicateScanProgress progress;
  final List<DuplicateGroup> groups;
  final Map<String, bool> selectedForDeletion;

  int get selectedCount =>
      selectedForDeletion.values.where((v) => v).length;

  int get selectedBytesTotal {
    var total = 0;
    for (final group in groups) {
      for (final item in group.files) {
        if (selectedForDeletion[item.id] ?? false) {
          total += item.sizeBytes;
        }
      }
    }
    return total;
  }

  const DuplicateFinderState({
    this.selectedTargetVolId = -1,
    this.isScanning = false,
    this.progress = const DuplicateScanProgress(stage: DuplicateScanStage.idle),
    this.groups = const [],
    this.selectedForDeletion = const {},
  });

  DuplicateFinderState _copy({
    int? selectedTargetVolId,
    bool? isScanning,
    DuplicateScanProgress? progress,
    List<DuplicateGroup>? groups,
    Map<String, bool>? selectedForDeletion,
  }) => DuplicateFinderState(
    selectedTargetVolId: selectedTargetVolId ?? this.selectedTargetVolId,
    isScanning: isScanning ?? this.isScanning,
    progress: progress ?? this.progress,
    groups: groups ?? this.groups,
    selectedForDeletion: selectedForDeletion ?? this.selectedForDeletion,
  );
}

@riverpod
class DuplicateFinder extends _$DuplicateFinder {
  late final DuplicateFinderService _service;
  DuplicateFinderCancellationToken? _cancelToken;

  @override
  DuplicateFinderState build() {
    _service = DuplicateFinderService(
      fileIoApi: ref.read(vaultFileIoApiProvider),
      hashApi: ref.read(vaultHashApiProvider),
    );
    ref.onDispose(() {
      _cancelToken?.cancel();
    });
    return const DuplicateFinderState();
  }

  void setSelectedTargetVolId(int volId) {
    state = state._copy(
      selectedTargetVolId: volId,
      progress: const DuplicateScanProgress(stage: DuplicateScanStage.idle),
      groups: const [],
      selectedForDeletion: const {},
    );
  }

  Future<void> startScan(List<MountedContainer> targets) async {
    if (targets.isEmpty) return;

    _cancelToken?.cancel();
    final token = DuplicateFinderCancellationToken();
    _cancelToken = token;

    state = state._copy(
      isScanning: true,
      groups: const [],
      selectedForDeletion: const {},
      progress: const DuplicateScanProgress(stage: DuplicateScanStage.indexing),
    );

    try {
      await for (final result in _service.scanVaults(
        containers: targets,
        cancelToken: token,
      )) {
        if (!ref.mounted) break;
        state = state._copy(
          progress: result.progress,
          groups: result.groups,
        );
      }
    } finally {
      if (ref.mounted) {
        state = state._copy(isScanning: false);
        autoSelectRedundantCopies();
      }
    }
  }

  void cancelScan() {
    _cancelToken?.cancel();
    state = state._copy(
      isScanning: false,
      progress: const DuplicateScanProgress(stage: DuplicateScanStage.cancelled),
    );
  }

  void autoSelectRedundantCopies() {
    final newSelected = <String, bool>{};
    for (final group in state.groups) {
      for (int i = 0; i < group.files.length; i++) {
        final item = group.files[i];
        newSelected[item.id] = (i > 0);
      }
    }
    state = state._copy(selectedForDeletion: Map.unmodifiable(newSelected));
  }

  void selectAllFiles() {
    final newSelected = <String, bool>{};
    for (final group in state.groups) {
      for (final item in group.files) {
        newSelected[item.id] = true;
      }
    }
    state = state._copy(selectedForDeletion: Map.unmodifiable(newSelected));
  }

  void deselectAllFiles() {
    final newSelected = <String, bool>{};
    for (final group in state.groups) {
      for (final item in group.files) {
        newSelected[item.id] = false;
      }
    }
    state = state._copy(selectedForDeletion: Map.unmodifiable(newSelected));
  }

  void toggleFileSelection(String itemId, bool selected) {
    final newSelected = Map<String, bool>.from(state.selectedForDeletion)..[itemId] = selected;
    state = state._copy(selectedForDeletion: Map.unmodifiable(newSelected));
  }

  Future<int> deleteSelected() async {
    final itemsToDelete = <VaultFileItem>[];
    for (final group in state.groups) {
      for (final item in group.files) {
        if (state.selectedForDeletion[item.id] ?? false) {
          itemsToDelete.add(item);
        }
      }
    }

    if (itemsToDelete.isEmpty) return 0;

    state = state._copy(isScanning: true);
    try {
      final deletedCount = await _service.deleteFiles(itemsToDelete);
      final deletedIds = itemsToDelete.map((e) => e.id).toSet();

      final updatedGroups = <DuplicateGroup>[];
      for (final group in state.groups) {
        final remaining = group.files.where((f) => !deletedIds.contains(f.id)).toList();
        if (remaining.length >= 2) {
          updatedGroups.add(group.copyWithFiles(remaining));
        }
      }

      if (ref.mounted) {
        state = state._copy(
          groups: List.unmodifiable(updatedGroups),
          isScanning: false,
        );
        autoSelectRedundantCopies();
      }
      return deletedCount;
    } finally {
      if (ref.mounted) {
        state = state._copy(isScanning: false);
      }
    }
  }
}
