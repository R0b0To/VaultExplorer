// The one place bookmarks and pins are read and written.
//
// Family-keyed by the container's volId, like FileBrowserSelection/Sort/
// Search. Everything that shows or changes marks -- the browser, its bookmark
// bar, the media viewer, the bookmark manager, the navigation drawer -- goes
// through this provider, so they all see the same state. They used to each
// read the saved record on their own and write it back whole, which meant a
// bookmark added in the media viewer did not appear in the browser, and the
// browser's next change could silently overwrite it with its stale copy.
//
// Where the marks are persisted is VaultMarksStore's business: inside a
// writable vault, on this device for a read-only one, in the app's own file
// for phone storage. Nothing here depends on which.
//
// Rules this class keeps:
//  * Nothing is loaded until [ensureLoaded] (it never writes), and nothing is
//    saved before a load succeeded, so a slow or failed read can't be
//    "repaired" by overwriting the stored marks with an empty list.
//  * State changes immediately; saves run one at a time, each writing the
//    state as it was when that change was made, so the last change wins in
//    order.
//  * The provider is autoDispose: once a vault is locked and nothing watches
//    it any more, its marks are dropped from memory.
//
// The state is immutable ([VaultMarks]); every change builds a new value, so
// Riverpod's equality check always sees it.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/features/browser/services/vault_marks_store.dart';

part 'file_browser_pins_bookmarks_controller.g.dart';

typedef FileBrowserPinsBookmarksState = VaultMarks;

@riverpod
class FileBrowserPinsBookmarks extends _$FileBrowserPinsBookmarks {
  static const String _tag = 'PinsBookmarks';

  bool _loaded = false;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();

  @override
  FileBrowserPinsBookmarksState build(int volId) {
    _loaded = false;
    _loading = null;
    return VaultMarks.empty;
  }

  /// Whether the stored marks have been read into [state].
  bool get isLoaded => _loaded;

  /// Reads the stored marks once. Safe to call from anywhere, any number of
  /// times: later calls share the first one's result.
  Future<void> ensureLoaded(MountedContainer container) {
    if (_loaded) return Future<void>.value();
    return _loading ??= _read(container).whenComplete(() => _loading = null);
  }

  /// Reads the stored marks again, replacing [state]. For a caller that knows
  /// they changed behind this provider's back; ordinary code never needs it.
  Future<void> reload(MountedContainer container) async {
    _loaded = false;
    await ensureLoaded(container);
  }

  Future<void> _read(MountedContainer container) async {
    try {
      final marks = await ref.read(vaultMarksStoreProvider).load(container);
      if (!ref.mounted) return;
      state = marks;
      _loaded = true;
    } catch (e) {
      // Could not reach the storage. Stay unloaded: [_apply] then refuses to
      // save, and a later ensureLoaded() tries again.
      VeLog.w(_tag, 'could not load marks for vol ${container.volId}', e);
    }
  }

  /// Applies [change] to the current marks, then saves them.
  Future<void> _apply(
    MountedContainer container,
    VaultMarks Function(VaultMarks current) change,
  ) async {
    await ensureLoaded(container);
    if (!_loaded || !ref.mounted) return;
    final next = change(state);
    if (next == state) return;
    state = next;
    await _save(container, next);
  }

  Future<void> _save(MountedContainer container, VaultMarks snapshot) {
    final store = ref.read(vaultMarksStoreProvider);
    final done = _writes.then((_) async {
      if (!await store.save(container, snapshot)) {
        VeLog.w(_tag, 'could not save marks for vol ${container.volId}');
      }
    });
    _writes = done.catchError((Object _) {});
    return done;
  }

  /// Adds or removes bookmarks. Removing only looks at each path; the kind is
  /// recorded when a bookmark is added, from the real directory listing.
  Future<void> toggleBookmarks(
    MountedContainer container,
    List<VaultBookmark> bookmarks, {
    required bool bookmark,
  }) {
    return _apply(
      container,
      (marks) => bookmark
          ? marks.withBookmarks(bookmarks)
          : marks.withoutBookmarks(bookmarks.map((b) => b.path)),
    );
  }

  Future<void> removeBookmark(MountedContainer container, String path) =>
      _apply(container, (marks) => marks.withoutBookmarks([path]));

  /// [newIndex] follows `ReorderableListView.onReorderItem`: the position
  /// after the item was taken out.
  Future<void> reorderBookmarks(
    MountedContainer container,
    int oldIndex,
    int newIndex,
  ) => _apply(container, (marks) => marks.reordered(oldIndex, newIndex));

  Future<void> togglePins(
    MountedContainer container,
    List<String> paths, {
    required bool pin,
  }) {
    return _apply(
      container,
      (marks) => pin ? marks.withPinned(paths) : marks.withoutPinned(paths),
    );
  }

  /// Forgets marks on entries that were deleted, and on everything inside a
  /// deleted folder. Saves only if something was actually marked.
  Future<void> removeDeletedPaths(
    MountedContainer container,
    Set<String> deletedPaths,
  ) => _apply(container, (marks) => marks.withoutDeleted(deletedPaths));

  /// Follows renames and moves, so a bookmark on a renamed entry (or inside a
  /// renamed folder) keeps pointing at it. [moves] maps old path to new path.
  Future<void> remapPaths(
    MountedContainer container,
    Map<String, String> moves,
  ) => _apply(container, (marks) => marks.withMoves(moves));
}
