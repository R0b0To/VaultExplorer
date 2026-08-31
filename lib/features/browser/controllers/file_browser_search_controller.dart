// Search Controller extracted from _FileBrowserScreenState. Unlike the
// still-deferred Navigation Controller, search state is read widely
// (~15 sites, mostly filtering/display logic in build()) but written from
// exactly 4 methods (_clearSearch/_onSearchQueryChanged/
// _onDeepSearchToggled/_runDeepSearch, plus the recursive
// _scanDirectoryForQuery helper) that don't touch path-stack, archive, or
// clipboard/toolbar state -- a genuinely self-contained slice, not a forced
// extraction. Family-keyed by the container's volId, same reasoning as
// FileBrowserSelection/FileBrowserSort: one FileBrowserScreen instance
// covers a whole container's directory tree via its own _pathStack.
//
// Directory listing needs archive-awareness (_listDirEntries in the
// original branches on _archiveContext), but the controller doesn't own
// navigation state -- runDeepSearch takes the resolved inputs
// (currentDirPath, showHiddenFiles, and -- only when browsing inside an
// in-memory archive -- the archive itself plus its already-resolved root
// path) as call-time params instead. Keeps the boundary the same place
// FileBrowserSort/FileBrowserSelection already drew it: the controller
// owns the search algorithm, the widget still owns "where am I".
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';

part 'file_browser_search_controller.g.dart';

typedef FileBrowserSearchState = ({
  bool active,
  String query,
  bool isDeepSearch,
  bool isSearchingSubfolders,
  List<RawEntry> deepSearchResults,
});

const _emptySearch = (
  active: false,
  query: '',
  isDeepSearch: false,
  isSearchingSubfolders: false,
  deepSearchResults: <RawEntry>[],
);

const _maxScanDepth = 20;

@riverpod
class FileBrowserSearch extends _$FileBrowserSearch {
  Timer? _debounceTimer;
  int _generation = 0;

  @override
  FileBrowserSearchState build(int volId) {
    ref.onDispose(() => _debounceTimer?.cancel());
    return _emptySearch;
  }

  /// Toggles the search bar itself open/closed -- matches the original's
  /// inline `setState(() { _searchActive = !_searchActive; if
  /// (!_searchActive) _searchQuery = ''; })` at the search icon button.
  void toggleActive() {
    if (state.active) {
      clear();
    } else {
      state = (
        active: true,
        query: state.query,
        isDeepSearch: state.isDeepSearch,
        isSearchingSubfolders: state.isSearchingSubfolders,
        deepSearchResults: state.deepSearchResults,
      );
    }
  }

  void clear() {
    _debounceTimer?.cancel();
    _generation++;
    state = _emptySearch;
  }

  /// [container]/[archiveContext]/[archiveRootPath] are only needed when
  /// [isDeepSearch] ends up triggering a scan; pass archiveContext/
  /// archiveRootPath as null when not currently browsing inside an
  /// in-memory archive (archiveRootPath is meaningless without it).
  void onQueryChanged(
    String query, {
    required MountedContainer container,
    required String currentDirPath,
    required bool showHiddenFiles,
    ArchiveContext? archiveContext,
    String? archiveRootPath,
  }) {
    state = (
      active: state.active,
      query: query,
      isDeepSearch: state.isDeepSearch,
      isSearchingSubfolders: state.isSearchingSubfolders,
      deepSearchResults: state.deepSearchResults,
    );
    _debounceTimer?.cancel();
    if (!state.isDeepSearch || query.trim().isEmpty) {
      state = (
        active: state.active,
        query: state.query,
        isDeepSearch: state.isDeepSearch,
        isSearchingSubfolders: false,
        deepSearchResults: const [],
      );
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (ref.mounted && state.active && state.isDeepSearch) {
        _runDeepSearch(
          query,
          container: container,
          currentDirPath: currentDirPath,
          showHiddenFiles: showHiddenFiles,
          archiveContext: archiveContext,
          archiveRootPath: archiveRootPath,
        );
      }
    });
  }

  void onDeepSearchToggled(
    bool enabled, {
    required MountedContainer container,
    required String currentDirPath,
    required bool showHiddenFiles,
    ArchiveContext? archiveContext,
    String? archiveRootPath,
  }) {
    state = (
      active: state.active,
      query: state.query,
      isDeepSearch: enabled,
      isSearchingSubfolders: state.isSearchingSubfolders,
      deepSearchResults: state.deepSearchResults,
    );
    onQueryChanged(
      state.query,
      container: container,
      currentDirPath: currentDirPath,
      showHiddenFiles: showHiddenFiles,
      archiveContext: archiveContext,
      archiveRootPath: archiveRootPath,
    );
  }

  Future<void> _runDeepSearch(
    String query, {
    required MountedContainer container,
    required String currentDirPath,
    required bool showHiddenFiles,
    required ArchiveContext? archiveContext,
    required String? archiveRootPath,
  }) async {
    final gen = ++_generation;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      if (ref.mounted) {
        state = (
          active: state.active,
          query: state.query,
          isDeepSearch: state.isDeepSearch,
          isSearchingSubfolders: false,
          deepSearchResults: const [],
        );
      }
      return;
    }
    state = (
      active: state.active,
      query: state.query,
      isDeepSearch: state.isDeepSearch,
      isSearchingSubfolders: true,
      deepSearchResults: state.deepSearchResults,
    );
    final results = <RawEntry>[];
    await _scanDirectoryForQuery(
      currentDirPath,
      q,
      gen,
      results,
      container: container,
      showHiddenFiles: showHiddenFiles,
      archiveContext: archiveContext,
      archiveRootPath: archiveRootPath,
      relativePrefix: '',
    );
    if (!ref.mounted || gen != _generation) return;
    state = (
      active: state.active,
      query: state.query,
      isDeepSearch: state.isDeepSearch,
      isSearchingSubfolders: false,
      deepSearchResults: results,
    );
  }

  Future<List<String>?> _listDirEntries(
    String path, {
    required MountedContainer container,
    required ArchiveContext? archiveContext,
    required String? archiveRootPath,
  }) async {
    if (archiveContext != null && archiveRootPath != null) {
      String subPath = '';
      if (path.length > archiveRootPath.length) {
        subPath = path.substring(archiveRootPath.length);
        if (subPath.startsWith('/')) subPath = subPath.substring(1);
      }
      return archiveContext.listDirectory(subPath);
    }
    return ref.read(vaultFileIoApiProvider).listDirectory(container, path);
  }

  Future<void> _scanDirectoryForQuery(
    String dirPath,
    String query,
    int generation,
    List<RawEntry> results, {
    required MountedContainer container,
    required bool showHiddenFiles,
    required ArchiveContext? archiveContext,
    required String? archiveRootPath,
    required String relativePrefix,
    int depth = 0,
  }) async {
    if (generation != _generation || depth > _maxScanDepth) return;
    try {
      final rawList = await _listDirEntries(
        dirPath,
        container: container,
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
      );
      if (rawList == null || generation != _generation) return;
      final entries = RawEntry.parseAll(rawList);
      final subdirs = <RawEntry>[];
      for (final entry in entries) {
        if (generation != _generation) return;
        if (!showHiddenFiles && isHiddenEntryName(entry.name)) {
          continue;
        }
        final relPath = relativePrefix.isEmpty ? entry.name : '$relativePrefix/${entry.name}';
        final nameMatches = entry.name.toLowerCase().contains(query);
        if (nameMatches) {
          results.add(
            RawEntry(
              name: relPath,
              isDir: entry.isDir,
              sizeBytes: entry.sizeBytes,
              modifiedSecs: entry.modifiedSecs,
            ),
          );
        }
        if (entry.isDir) {
          subdirs.add(entry);
        }
      }
      for (final sub in subdirs) {
        if (generation != _generation) return;
        final subRelPrefix = relativePrefix.isEmpty ? sub.name : '$relativePrefix/${sub.name}';
        final subFullPath = dirPath.isEmpty ? sub.name : '$dirPath/${sub.name}';
        await _scanDirectoryForQuery(
          subFullPath,
          query,
          generation,
          results,
          container: container,
          showHiddenFiles: showHiddenFiles,
          archiveContext: archiveContext,
          archiveRootPath: archiveRootPath,
          relativePrefix: subRelPrefix,
          depth: depth + 1,
        );
      }
    } catch (e) {
      VeLog.e('FileBrowserSearch', 'Deep search failed at ${VeLog.censorUri(dirPath)}', e);
    }
  }
}
