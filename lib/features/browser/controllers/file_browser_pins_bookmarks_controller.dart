// Pins & Bookmarks Controller extracted from _FileBrowserScreenState.
// Family-keyed by the container's volId, same reasoning as
// FileBrowserSelection/FileBrowserSort/FileBrowserSearch: one
// FileBrowserScreen instance covers a whole container's directory tree,
// and pinned/bookmarked paths are per-container, persisted via
// ContainerRepository (still a bridged legacy singleton -- see the
// migration brief's §3 on ContainerRepository/FileOperationService).
//
// Real bug this extraction fixes, not just relocates: the original mutated
// _pinnedPaths/_bookmarkPaths in place (Set.add/.remove, List.add/.remove)
// in 5 different write sites, one of them (_finishBatchDelete's
// post-delete cleanup) with no setState() wrapper at all -- it relied on a
// later _loadDirectoryContents() call happening to trigger a rebuild.
// Under Riverpod's reference-equality change detection this class of bug
// silently drops updates; every write here reconstructs immutable
// Set/List values instead, per the migration brief's rule #7.
//
// Preserves one faithfully-reproduced original quirk rather than "fixing"
// it: the original loaded pinned/bookmark paths from ContainerRepository
// twice, independently, from _initSettingsAndContents() and
// _loadToolbarConfig() (both fired from initState() concurrently) -- a
// harmless last-write-wins race, not something this extraction should
// silently deduplicate. load() is exposed so both call sites can still
// call it exactly as before.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_marks_service.dart';

part 'file_browser_pins_bookmarks_controller.g.dart';

const _localMarksService = DecoyLocalMarksService();

typedef FileBrowserPinsBookmarksState = ({
  Set<String> pinnedPaths,
  List<String> bookmarkPaths,
});

const _empty = (pinnedPaths: <String>{}, bookmarkPaths: <String>[]);

@riverpod
class FileBrowserPinsBookmarks extends _$FileBrowserPinsBookmarks {
  @override
  FileBrowserPinsBookmarksState build(int volId) => _empty;

  /// Loads from the persisted [ContainerRecord] for [container], if one
  /// exists. Callable from multiple init call sites (matches the original
  /// -- see header comment); each call independently overwrites state with
  /// whatever the record currently has, same as before.
  Future<void> load(MountedContainer container) async {
    if (container.isLocalStorage) {
      final marks = await _localMarksService.load();
      if (!ref.mounted) return;
      state = (
        pinnedPaths: Set<String>.from(marks.pinnedPaths),
        bookmarkPaths: List<String>.from(marks.bookmarkPaths),
      );
      return;
    }
    final records = await ref.read(containerRepositoryProvider).loadAll();
    final record = records[container.uri];
    if (record == null || !ref.mounted) return;
    state = (
      pinnedPaths: Set<String>.from(record.pinnedPaths),
      bookmarkPaths: List<String>.from(record.bookmarkPaths),
    );
  }

  Future<ContainerRecord> _recordOrDefault(MountedContainer container) async {
    final records = await ref.read(containerRepositoryProvider).loadAll();
    return records[container.uri] ??
        ContainerRecord(
          uri: container.uri,
          label: container.displayName,
          containerFormat: container.containerFormat,
        );
  }

  /// Local storage never touches [ContainerRepository] -- see the doc
  /// comment on decoy_local_marks_service.dart for why that separation
  /// matters here specifically.
  Future<void> _persist(MountedContainer container) async {
    if (container.isLocalStorage) {
      await _localMarksService.save(state);
      return;
    }
    final record = await _recordOrDefault(container);
    await ref.read(containerRepositoryProvider).save(
          record.copyWith(
            pinnedPaths: state.pinnedPaths.toList(),
            bookmarkPaths: state.bookmarkPaths,
          ),
        );
  }

  Future<void> toggleBookmarks(
    MountedContainer container,
    List<String> paths, {
    required bool bookmark,
  }) async {
    final updated = [...state.bookmarkPaths];
    if (bookmark) {
      for (final p in paths) {
        if (!updated.contains(p)) updated.add(p);
      }
    } else {
      updated.removeWhere(paths.toSet().contains);
    }
    state = (pinnedPaths: state.pinnedPaths, bookmarkPaths: updated);
    await _persist(container);
  }

  Future<void> removeBookmark(MountedContainer container, String path) async {
    state = (
      pinnedPaths: state.pinnedPaths,
      bookmarkPaths: state.bookmarkPaths.where((p) => p != path).toList(),
    );
    await _persist(container);
  }

  Future<void> togglePins(
    MountedContainer container,
    List<String> paths, {
    required bool pin,
  }) async {
    final updated = {...state.pinnedPaths};
    if (pin) {
      updated.addAll(paths);
    } else {
      updated.removeAll(paths);
    }
    state = (pinnedPaths: updated, bookmarkPaths: state.bookmarkPaths);
    await _persist(container);
  }

  /// Drops any pinned/bookmarked paths that no longer exist after a batch
  /// delete, persisting only if something actually changed -- matches the
  /// original's `changed` guard in `_finishBatchDelete`. Unlike
  /// [toggleBookmarks]/[togglePins]/[removeBookmark], this does **not**
  /// create a default ContainerRecord when none exists yet -- the
  /// original's cleanup path only saved `if (record != null)`, deliberately
  /// skipping persistence rather than materializing a record on a delete.
  Future<void> removeDeletedPaths(MountedContainer container, Set<String> deletedPaths) async {
    var changed = false;
    var pinned = state.pinnedPaths;
    var bookmarks = state.bookmarkPaths;

    if (pinned.any(deletedPaths.contains)) {
      pinned = pinned.where((p) => !deletedPaths.contains(p)).toSet();
      changed = true;
    }
    if (bookmarks.any(deletedPaths.contains)) {
      bookmarks = bookmarks.where((p) => !deletedPaths.contains(p)).toList();
      changed = true;
    }
    if (!changed) return;

    state = (pinnedPaths: pinned, bookmarkPaths: bookmarks);

    if (container.isLocalStorage) {
      await _localMarksService.save(state);
      return;
    }

    final records = await ref.read(containerRepositoryProvider).loadAll();
    final record = records[container.uri];
    if (record == null) return;
    await ref.read(containerRepositoryProvider).save(
          record.copyWith(pinnedPaths: pinned.toList(), bookmarkPaths: bookmarks),
        );
  }
}
