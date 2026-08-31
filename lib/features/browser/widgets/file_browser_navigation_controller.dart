// Navigation Controller extracted from _FileBrowserScreenState.
//
// Owns: the path stack (_pathStack), the current archive context when
// browsing inside an opened archive (_archiveContext), the loaded
// directory's contents, and the loading/truncation/free-space flags that
// travel with them -- because every navigation method in the original
// (_enterDirectory / _navigateUp / _jumpTo / _navigateToPath / _openArchive)
// updated all of these atomically in one setState call. That's the real
// coherent unit here, not the path stack alone.
//
// Family-keyed by the container's volId, same reasoning as
// FileBrowserSelection/FileBrowserSort/FileBrowserSearch/
// FileBrowserPinsBookmarks: one FileBrowserScreen instance covers a whole
// container's directory tree.
//
// What did NOT come along, deliberately:
//  - _layoutMode: looked like navigation state (recomputed at every call
//    site in the original) but is actually a pure function of
//    (dirPath, toolbarConfig, appSettings) -- nothing here needs to store
//    it, the screen can derive it at build time instead of keeping it
//    imperatively in sync. [enterDirectory]'s preview-caching still needs
//    a snapshot of it *at the moment of navigating away* (see
//    [PathSegment.previewLayoutMode]), so the caller passes it in rather
//    than this controller looking it up.
//  - _currentFilter, search-controller state, selection state: unrelated
//    concerns that happen to get reset on navigation in the original.
//    The screen resets them itself right alongside calling into this
//    controller, same as it already does for its search controller's
//    clear().
//  - Localized error messages: this controller has no BuildContext/l10n.
//    Failures land in [FileBrowserNavigationState.loadError] instead; the
//    screen is expected to `ref.listen` for it and turn it into a
//    localized status message (see the migration brief's implementation
//    lessons: "Use ref.listen() for ... side effects that need
//    BuildContext").
//
// Real bug this extraction fixes, not just relocates: the original
// mutated _pathStack in place (List.add/.removeLast/.removeRange/
// .clear()+addAll) five separate times. Under Riverpod's
// reference-equality change detection that class of write can silently
// fail to notify watchers (same failure mode the pins/bookmarks
// controller's header describes). Every write here reconstructs a new
// list instead, per the migration brief's rule #7.
//
// Preserves faithfully, not "fixed": the generation-counter race guard
// (a fast back-and-forth can leave two listDirectory calls in flight;
// only the one matching both the current generation *and* the current
// path should apply) and the fire-and-forget style of the mutation
// methods (none of them await their own load to finish before returning,
// matching the original navigation methods).
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';

part 'file_browser_navigation_controller.g.dart';

class PathSegment {
  final String label;
  final String fatPath;
  final bool isArchiveRoot;
  final List<RawEntry>? previewItems;
  final BrowserLayoutMode? previewLayoutMode;

  const PathSegment(
    this.label,
    this.fatPath, {
    this.isArchiveRoot = false,
    this.previewItems,
    this.previewLayoutMode,
  });
}

enum FileBrowserLoadErrorKind { directoryListing, archiveOpen }

typedef FileBrowserLoadError = ({FileBrowserLoadErrorKind kind, String detail});

typedef FileBrowserNavigationState = ({
  List<PathSegment> pathStack,
  ArchiveContext? archiveContext,
  List<RawEntry> currentItems,
  bool isLoading,
  bool isListingTruncated,
  int? freeSpace,
  FileBrowserLoadError? loadError,
});

@riverpod
class FileBrowserNavigation extends _$FileBrowserNavigation {
  int _loadGeneration = 0;
  bool _initialized = false;

  @override
  FileBrowserNavigationState build(int volId) {
    ref.onDispose(() => state.archiveContext?.dispose());
    return (
      pathStack: const [],
      archiveContext: null,
      currentItems: const [],
      isLoading: false,
      isListingTruncated: false,
      freeSpace: null,
      loadError: null,
    );
  }

  /// Must be called once, with a localized root-folder label, before any
  /// other method on this controller. Mirrors the original's lazy
  /// `_pathStack` initialization in `didChangeDependencies()` -- that
  /// needs a `BuildContext` for `context.l10n.rootFolderLabel`, which
  /// isn't available in [build] above. Safe to call every
  /// `didChangeDependencies()` firing; only the first call has any effect.
  void initializeIfNeeded(String rootLabel) {
    if (_initialized) return;
    _initialized = true;
    state = (
      pathStack: [PathSegment(rootLabel, '')],
      archiveContext: null,
      currentItems: const [],
      isLoading: false,
      isListingTruncated: false,
      freeSpace: null,
      loadError: null,
    );
  }

  bool get atRoot => state.pathStack.length == 1;
  String get currentDirPath => state.pathStack.last.fatPath;

  /// Path of the archive's own root inside its container, if currently
  /// browsing inside one -- mirrors the original screen's
  /// `_archiveRootPathForSearch` getter (still needed by the search
  /// controller, which stays screen-owned).
  String? get archiveRootPath => state.archiveContext == null
      ? null
      : state.pathStack[state.archiveContext!.pathStackEntryIndex].fatPath;

  Future<void> enterDirectory(
    MountedContainer container,
    String name,
    String newPath, {
    required List<RawEntry> previewItems,
    required BrowserLayoutMode previewLayoutMode,
  }) async {
    state = (
      pathStack: [
        ...state.pathStack,
        PathSegment(
          name,
          newPath,
          previewItems: previewItems,
          previewLayoutMode: previewLayoutMode,
        ),
      ],
      archiveContext: state.archiveContext,
      currentItems: const [],
      isLoading: true,
      isListingTruncated: state.isListingTruncated,
      freeSpace: state.freeSpace,
      loadError: null,
    );
    await _loadDirectoryContents(container, newPath);
  }

  void navigateUp(MountedContainer container) {
    if (atRoot) return;
    var archiveContext = state.archiveContext;
    if (archiveContext != null &&
        state.pathStack.length - 1 <= archiveContext.pathStackEntryIndex) {
      archiveContext.dispose();
      archiveContext = null;
    }
    final newStack = state.pathStack.sublist(0, state.pathStack.length - 1);
    state = (
      pathStack: newStack,
      archiveContext: archiveContext,
      currentItems: const [],
      isLoading: true,
      isListingTruncated: state.isListingTruncated,
      freeSpace: state.freeSpace,
      loadError: null,
    );
    _loadDirectoryContents(container, newStack.last.fatPath);
  }

  void jumpTo(MountedContainer container, int index) {
    if (index == state.pathStack.length - 1) return;
    var archiveContext = state.archiveContext;
    if (archiveContext != null && index < archiveContext.pathStackEntryIndex) {
      archiveContext.dispose();
      archiveContext = null;
    }
    final newStack = state.pathStack.sublist(0, index + 1);
    state = (
      pathStack: newStack,
      archiveContext: archiveContext,
      currentItems: const [],
      isLoading: true,
      isListingTruncated: state.isListingTruncated,
      freeSpace: state.freeSpace,
      loadError: null,
    );
    _loadDirectoryContents(container, newStack.last.fatPath);
  }

  /// Rebuilds the whole stack from an absolute [fullPath]. Covers the
  /// original `_navigateToPath`'s directory branch only -- the file-tap
  /// branch (navigate to a path, then open the file at the end of it)
  /// stays the screen's job, since resolving and opening a file is a UI
  /// concern (viewers, sheets) this controller has no business owning.
  Future<void> navigateToPath(
    MountedContainer container,
    String rootLabel,
    String fullPath,
  ) async {
    final segments = fullPath.isEmpty ? <String>[] : fullPath.split('/');
    final newStack = [PathSegment(rootLabel, '')];
    var current = '';
    for (final seg in segments) {
      current = current.isEmpty ? seg : '$current/$seg';
      newStack.add(PathSegment(seg, current));
    }
    state.archiveContext?.dispose();
    state = (
      pathStack: newStack,
      archiveContext: null,
      currentItems: const [],
      isLoading: true,
      isListingTruncated: state.isListingTruncated,
      freeSpace: state.freeSpace,
      loadError: null,
    );
    await _loadDirectoryContents(container, current);
  }

  Future<void> openArchive(
    MountedContainer container,
    String fullPath,
    String archiveName,
  ) async {
    state = (
      pathStack: state.pathStack,
      archiveContext: state.archiveContext,
      currentItems: const [],
      isLoading: true,
      isListingTruncated: state.isListingTruncated,
      freeSpace: state.freeSpace,
      loadError: null,
    );
    try {
      final ctx = await ArchiveService.open(
        container: container,
        archivePathInContainer: fullPath,
        pathStackEntryIndex: state.pathStack.length,
      );
      if (!ref.mounted) {
        ctx.dispose();
        return;
      }
      state = (
        pathStack: [
          ...state.pathStack,
          PathSegment(archiveName, fullPath, isArchiveRoot: true),
        ],
        archiveContext: ctx,
        currentItems: state.currentItems,
        isLoading: state.isLoading,
        isListingTruncated: state.isListingTruncated,
        freeSpace: state.freeSpace,
        loadError: null,
      );
      _loadArchiveContents(fullPath);
    } catch (e) {
      if (ref.mounted) {
        state = (
          pathStack: state.pathStack,
          archiveContext: state.archiveContext,
          currentItems: state.currentItems,
          isLoading: false,
          isListingTruncated: state.isListingTruncated,
          freeSpace: state.freeSpace,
          loadError: (
            kind: FileBrowserLoadErrorKind.archiveOpen,
            detail: '${e.runtimeType}',
          ),
        );
      }
    }
  }

  /// Re-runs the load for whatever directory is currently on top of the
  /// stack -- the original's generic "something changed, reload the
  /// current folder" primitive, called from ~20 places throughout the
  /// screen (after delete/paste/rename/crypto/extract, pull-to-refresh,
  /// app-resume) as well as from every navigation method above.
  /// [forceRefresh] threads through to the native listDirectory call's
  /// own `refresh` param (bypasses its cache) -- matches the original's
  /// `refresh: true` call sites (pull-to-refresh, app-resume).
  Future<void> reload(MountedContainer container, {bool forceRefresh = false}) =>
      _loadDirectoryContents(container, currentDirPath, refresh: forceRefresh);

  Future<void> _loadDirectoryContents(
    MountedContainer container,
    String path, {
    bool refresh = false,
  }) async {
    final generation = ++_loadGeneration;
    // Only force the spinner on when there's nothing on screen yet --
    // matches the original exactly: a reload-after-operation or
    // pull-to-refresh with existing content stays silent (no blank
    // flash), only a genuinely empty view shows the spinner. Navigation
    // callers above already set isLoading themselves before calling in
    // here (with currentItems cleared too), so this redundantly re-sets
    // the same value there -- harmless, matches the original's own
    // unconditional re-set in that case.
    if (state.currentItems.isEmpty) {
      state = (
        pathStack: state.pathStack,
        archiveContext: state.archiveContext,
        currentItems: state.currentItems,
        isLoading: true,
        isListingTruncated: state.isListingTruncated,
        freeSpace: state.freeSpace,
        loadError: state.loadError,
      );
    }
    if (state.archiveContext != null) {
      _loadArchiveContents(path);
      return;
    }
    try {
      final items = await ref
          .read(vaultFileIoApiProvider)
          .listDirectory(container, path, refresh: refresh);
      if (!ref.mounted || generation != _loadGeneration || path != currentDirPath) {
        return;
      }
      final isTruncated = items?.any((f) => f == 'System:TRUNCATED') ?? false;
      state = (
        pathStack: state.pathStack,
        archiveContext: state.archiveContext,
        currentItems: items
                ?.where((f) => !f.startsWith('System:'))
                .map(RawEntry.parse)
                .toList() ??
            const [],
        isLoading: false,
        isListingTruncated: isTruncated,
        freeSpace: state.freeSpace,
        loadError: null,
      );
      ref.read(vaultFileIoApiProvider).getSpaceInfo(container).then((space) {
        if (ref.mounted &&
            generation == _loadGeneration &&
            space != null &&
            space.length > 1 &&
            space[0] > 0 &&
            space[1] >= 0) {
          state = (
            pathStack: state.pathStack,
            archiveContext: state.archiveContext,
            currentItems: state.currentItems,
            isLoading: state.isLoading,
            isListingTruncated: state.isListingTruncated,
            freeSpace: space[1],
            loadError: state.loadError,
          );
        }
      }).catchError((_) {});
    } catch (e) {
      if (ref.mounted && generation == _loadGeneration) {
        state = (
          pathStack: state.pathStack,
          archiveContext: state.archiveContext,
          currentItems: state.currentItems,
          isLoading: false,
          isListingTruncated: state.isListingTruncated,
          freeSpace: state.freeSpace,
          loadError: (
            kind: FileBrowserLoadErrorKind.directoryListing,
            detail: '${e.runtimeType}',
          ),
        );
      }
    }
  }

  void _loadArchiveContents(String path) {
    final archiveContext = state.archiveContext;
    if (archiveContext == null) return;
    final archiveRoot = archiveRootPath!;
    var subPath = '';
    if (path.length > archiveRoot.length) {
      subPath = path.substring(archiveRoot.length);
      if (subPath.startsWith('/')) subPath = subPath.substring(1);
    }
    final items = archiveContext.listDirectory(subPath);
    state = (
      pathStack: state.pathStack,
      archiveContext: state.archiveContext,
      currentItems: items.map(RawEntry.parse).toList(),
      isLoading: false,
      isListingTruncated: false,
      freeSpace: state.freeSpace,
      loadError: null,
    );
  }
}
