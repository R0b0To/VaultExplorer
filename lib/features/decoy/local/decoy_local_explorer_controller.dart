import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart'
    show PathSegment;
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository_provider.dart';
import 'package:vaultexplorer/features/decoy/local/widgets/local_type_filter_button.dart';

part 'decoy_local_explorer_controller.g.dart';

/// Shared, non-widget state for one instance of the decoy local explorer.
/// Selection, dialogs, and transient touch feedback deliberately remain in
/// the screen; this controller owns the directory session that must survive
/// ordinary widget rebuilds and asynchronous directory loads.
class DecoyLocalExplorerState {
  const DecoyLocalExplorerState({
    this.checkingAccess = true,
    this.hasAccess = false,
    this.loading = false,
    this.rootPath,
    this.pathStack = const [],
    this.entries = const [],
    this.layoutMode = BrowserLayoutMode.list,
    this.typeFilter = LocalTypeFilter.all,
    this.searchActive = false,
    this.searchQuery = '',
  });

  final bool checkingAccess;
  final bool hasAccess;
  final bool loading;
  final String? rootPath;
  final List<PathSegment> pathStack;
  final List<RawEntry> entries;
  final BrowserLayoutMode layoutMode;
  final LocalTypeFilter typeFilter;
  final bool searchActive;
  final String searchQuery;

  String get currentPath =>
      pathStack.isEmpty ? (rootPath ?? '') : pathStack.last.fatPath;

  DecoyLocalExplorerState copyWith({
    bool? checkingAccess,
    bool? hasAccess,
    bool? loading,
    String? rootPath,
    bool setRootPath = false,
    List<PathSegment>? pathStack,
    List<RawEntry>? entries,
    BrowserLayoutMode? layoutMode,
    LocalTypeFilter? typeFilter,
    bool? searchActive,
    String? searchQuery,
  }) => DecoyLocalExplorerState(
    checkingAccess: checkingAccess ?? this.checkingAccess,
    hasAccess: hasAccess ?? this.hasAccess,
    loading: loading ?? this.loading,
    rootPath: setRootPath ? rootPath : this.rootPath,
    pathStack: pathStack ?? this.pathStack,
    entries: entries ?? this.entries,
    layoutMode: layoutMode ?? this.layoutMode,
    typeFilter: typeFilter ?? this.typeFilter,
    searchActive: searchActive ?? this.searchActive,
    searchQuery: searchQuery ?? this.searchQuery,
  );
}

@riverpod
class DecoyLocalExplorer extends _$DecoyLocalExplorer {
  int _loadGeneration = 0;

  DecoyLocalRepository get _repository =>
      ref.read(decoyLocalRepositoryProvider);
  VaultLifecycleApi get _lifecycle => ref.read(vaultLifecycleApiProvider);

  @override
  DecoyLocalExplorerState build() => const DecoyLocalExplorerState();

  Future<void> initialize(String rootLabel) async {
    state = state.copyWith(checkingAccess: true);
    final hasAccess = await _lifecycle.hasAllFilesAccess();
    if (!ref.mounted) return;
    if (!hasAccess) {
      state = state.copyWith(hasAccess: false, checkingAccess: false);
      return;
    }

    final root = await _repository.primaryRoot();
    if (!ref.mounted) return;
    state = state.copyWith(
      rootPath: root.path,
      setRootPath: true,
      pathStack: [PathSegment(rootLabel, root.path)],
      hasAccess: true,
      checkingAccess: false,
    );
    await load(root.path);
  }

  Future<void> requestAccess(String rootLabel) async {
    await _lifecycle.requestAllFilesAccess(openSettings: true);
    if (!ref.mounted) return;
    await initialize(rootLabel);
  }

  Future<void> load(String path) async {
    final generation = ++_loadGeneration;
    state = state.copyWith(loading: true);
    final entries = await _repository.listDirectory(path);
    if (!ref.mounted || generation != _loadGeneration) return;
    state = state.copyWith(entries: List.unmodifiable(entries), loading: false);
  }

  Future<void> refresh() => load(state.currentPath);

  void enterDirectory(RawEntry entry) {
    final nextPath = p.join(state.currentPath, entry.name);
    state = state.copyWith(
      pathStack: [...state.pathStack, PathSegment(entry.name, nextPath)],
      searchActive: false,
      searchQuery: '',
    );
    unawaited(load(nextPath));
  }

  void jumpTo(int index) {
    if (index == state.pathStack.length - 1) return;
    state = state.copyWith(
      pathStack: state.pathStack.sublist(0, index + 1),
      searchActive: false,
      searchQuery: '',
    );
    unawaited(refresh());
  }

  void setLayoutMode(BrowserLayoutMode value) =>
      state = state.copyWith(layoutMode: value);

  void setTypeFilter(LocalTypeFilter value) =>
      state = state.copyWith(typeFilter: value);

  void openSearch() => state = state.copyWith(searchActive: true);

  void closeSearch() =>
      state = state.copyWith(searchActive: false, searchQuery: '');

  void setSearchQuery(String value) =>
      state = state.copyWith(searchQuery: value);
}
