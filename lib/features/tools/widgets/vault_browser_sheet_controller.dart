import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

part 'vault_browser_sheet_controller.g.dart';

@immutable
class VaultBrowserParams {
  final List<MountedContainer> mountedContainers;
  final MountedContainer initialContainer;
  final String initialPath;

  const VaultBrowserParams({
    required this.mountedContainers,
    required this.initialContainer,
    this.initialPath = '',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultBrowserParams &&
          listEquals(other.mountedContainers, mountedContainers) &&
          other.initialContainer == initialContainer &&
          other.initialPath == initialPath;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(mountedContainers),
        initialContainer,
        initialPath,
      );
}

class VaultBrowserState {
  final MountedContainer selectedContainer;
  final List<String> pathStack;
  final List<RawEntry> rawEntries;
  final bool loading;

  String get currentPath => pathStack.isEmpty ? '' : pathStack.last;

  const VaultBrowserState({
    required this.selectedContainer,
    this.pathStack = const [''],
    this.rawEntries = const [],
    this.loading = false,
  });

  VaultBrowserState _copy({
    MountedContainer? selectedContainer,
    List<String>? pathStack,
    List<RawEntry>? rawEntries,
    bool? loading,
  }) => VaultBrowserState(
    selectedContainer: selectedContainer ?? this.selectedContainer,
    pathStack: pathStack ?? this.pathStack,
    rawEntries: rawEntries ?? this.rawEntries,
    loading: loading ?? this.loading,
  );
}

@riverpod
class VaultBrowserController extends _$VaultBrowserController {
  @override
  VaultBrowserState build(VaultBrowserParams params) {
    final state = VaultBrowserState(
      selectedContainer: params.initialContainer,
      pathStack: [params.initialPath],
      loading: true,
    );
    Future.microtask(() => loadDirectory(params.initialPath));
    return state;
  }

  Future<void> loadDirectory(String path) async {
    state = state._copy(loading: true);
    try {
      final rawList = await ref
          .read(vaultFileIoApiProvider)
          .listDirectory(state.selectedContainer, path);
      final entries = RawEntry.parseAll(rawList ?? []);
      if (!ref.mounted) return;
      state = state._copy(rawEntries: entries, loading: false);
    } catch (_) {
      if (ref.mounted) state = state._copy(loading: false);
    }
  }

  void switchVault(MountedContainer container) {
    if (container == state.selectedContainer) return;
    state = state._copy(
      selectedContainer: container,
      pathStack: const [''],
      rawEntries: const [],
      loading: true,
    );
    loadDirectory('');
  }

  void navigateToFolder(String folderName) {
    final newPath = state.currentPath.isEmpty
        ? folderName
        : '${state.currentPath}/$folderName';
    final newStack = List<String>.from(state.pathStack)..add(newPath);
    state = state._copy(pathStack: newStack, loading: true);
    loadDirectory(newPath);
  }

  void navigateUp() {
    if (state.pathStack.length > 1) {
      final newStack = List<String>.from(state.pathStack)..removeLast();
      state = state._copy(pathStack: newStack, loading: true);
      loadDirectory(newStack.last);
    }
  }

  void jumpTo(int index) {
    if (index >= state.pathStack.length - 1) return;
    final newStack = state.pathStack.sublist(0, index + 1);
    state = state._copy(pathStack: newStack, loading: true);
    loadDirectory(newStack.last);
  }
}