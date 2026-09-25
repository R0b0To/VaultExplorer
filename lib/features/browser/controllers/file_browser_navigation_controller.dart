import 'dart:async';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

part 'file_browser_navigation_controller.g.dart';

class PathSegment {
  final String label;
  final String fatPath;
  final bool isArchiveRoot;

  /// Cached items belonging to this specific directory level.
  List<RawEntry>? items;
  BrowserLayoutMode? layoutMode;
  double scrollOffset;

  /// Parent directory items captured when this directory was entered,
  /// used to render the parent view during an interactive back-gesture.
  List<RawEntry>? previewItems;
  BrowserLayoutMode? previewLayoutMode;

  PathSegment(
    this.label,
    this.fatPath, {
    this.isArchiveRoot = false,
    this.items,
    this.layoutMode,
    this.scrollOffset = 0.0,
    this.previewItems,
    this.previewLayoutMode,
  });
}

class FileBrowserNavigationState {
  final List<PathSegment> pathStack;
  final List<RawEntry> currentItems;
  final bool isLoading;
  final bool isListingTruncated;
  final String? statusMessage;
  final bool statusIsError;
  final int? freeSpace;
  final BrowserLayoutMode layoutMode;
  final String? currentFilter;
  final ArchiveContext? archiveContext;
  final bool isContainerLocked;

  // Back gesture preview state
  final double? backGestureProgress;
  final List<RawEntry>? backGesturePreviewItems;
  final BrowserLayoutMode? backGesturePreviewLayoutMode;
  final String? backGesturePreviewDirPath;
  final bool backGesturePreviewAtRoot;

  const FileBrowserNavigationState({
    this.pathStack = const [],
    this.currentItems = const [],
    this.isLoading = false,
    this.isListingTruncated = false,
    this.statusMessage,
    this.statusIsError = false,
    this.freeSpace,
    this.layoutMode = BrowserLayoutMode.list,
    this.currentFilter,
    this.archiveContext,
    this.isContainerLocked = false,
    this.backGestureProgress,
    this.backGesturePreviewItems,
    this.backGesturePreviewLayoutMode,
    this.backGesturePreviewDirPath,
    this.backGesturePreviewAtRoot = false,
  });

  bool get atRoot => pathStack.length <= 1;

  String get currentDirPath => pathStack.isEmpty ? '' : pathStack.last.fatPath;

  String? get archiveRootPath => archiveContext == null
      ? null
      : (archiveContext!.pathStackEntryIndex < pathStack.length
          ? pathStack[archiveContext!.pathStackEntryIndex].fatPath
          : null);

  FileBrowserNavigationState copyWith({
    List<PathSegment>? pathStack,
    List<RawEntry>? currentItems,
    bool? isLoading,
    bool? isListingTruncated,
    String? statusMessage,
    bool clearStatusMessage = false,
    bool? statusIsError,
    int? freeSpace,
    bool clearFreeSpace = false,
    BrowserLayoutMode? layoutMode,
    String? currentFilter,
    bool clearCurrentFilter = false,
    ArchiveContext? archiveContext,
    bool clearArchiveContext = false,
    bool? isContainerLocked,
    double? backGestureProgress,
    List<RawEntry>? backGesturePreviewItems,
    BrowserLayoutMode? backGesturePreviewLayoutMode,
    String? backGesturePreviewDirPath,
    bool? backGesturePreviewAtRoot,
    bool clearBackGesturePreview = false,
  }) {
    return FileBrowserNavigationState(
      pathStack: pathStack ?? this.pathStack,
      currentItems: currentItems ?? this.currentItems,
      isLoading: isLoading ?? this.isLoading,
      isListingTruncated: isListingTruncated ?? this.isListingTruncated,
      statusMessage:
          clearStatusMessage ? null : (statusMessage ?? this.statusMessage),
      statusIsError: statusIsError ?? this.statusIsError,
      freeSpace: clearFreeSpace ? null : (freeSpace ?? this.freeSpace),
      layoutMode: layoutMode ?? this.layoutMode,
      currentFilter:
          clearCurrentFilter ? null : (currentFilter ?? this.currentFilter),
      archiveContext:
          clearArchiveContext ? null : (archiveContext ?? this.archiveContext),
      isContainerLocked: isContainerLocked ?? this.isContainerLocked,
      backGestureProgress: clearBackGesturePreview
          ? null
          : (backGestureProgress ?? this.backGestureProgress),
      backGesturePreviewItems: clearBackGesturePreview
          ? null
          : (backGesturePreviewItems ?? this.backGesturePreviewItems),
      backGesturePreviewLayoutMode: clearBackGesturePreview
          ? null
          : (backGesturePreviewLayoutMode ?? this.backGesturePreviewLayoutMode),
      backGesturePreviewDirPath: clearBackGesturePreview
          ? null
          : (backGesturePreviewDirPath ?? this.backGesturePreviewDirPath),
      backGesturePreviewAtRoot: clearBackGesturePreview
          ? false
          : (backGesturePreviewAtRoot ?? this.backGesturePreviewAtRoot),
    );
  }
}

@riverpod
class FileBrowserNavigation extends _$FileBrowserNavigation {
  int _loadGeneration = 0;
  ArchiveContext? _liveArchiveContext;

  @override
  FileBrowserNavigationState build(int volId) {
    ref.onDispose(() {
      _liveArchiveContext?.dispose();
    });
    return const FileBrowserNavigationState();
  }

  void initRoot({
    required String rootLabel,
    BrowserLayoutMode layoutMode = BrowserLayoutMode.list,
  }) {
    if (state.pathStack.isEmpty) {
      state = state.copyWith(
        pathStack: [
          PathSegment(
            rootLabel,
            '',
            layoutMode: layoutMode,
            items: state.currentItems.isNotEmpty
                ? List<RawEntry>.of(state.currentItems)
                : null,
          )
        ],
        layoutMode: layoutMode,
      );
    }
  }

  void setLayoutMode(BrowserLayoutMode mode) {
    state = state.copyWith(layoutMode: mode);
    if (state.pathStack.isNotEmpty) {
      state.pathStack.last.layoutMode = mode;
    }
  }

  void setFilter(String? filter) {
    state = state.copyWith(
      currentFilter: filter,
      clearCurrentFilter: filter == null,
    );
  }

  void setStatus(String? message, {bool error = false}) {
    state = state.copyWith(
      statusMessage: message,
      clearStatusMessage: message == null,
      statusIsError: error,
    );
  }

  void clearStatus() {
    state = state.copyWith(clearStatusMessage: true, statusIsError: false);
  }

  void setContainerLocked(bool locked) {
    state = state.copyWith(isContainerLocked: locked);
  }

  void setFreeSpace(int? freeSpace) {
    state = state.copyWith(
      freeSpace: freeSpace,
      clearFreeSpace: freeSpace == null,
    );
  }

  void _prefetchParentIfMissing(MountedContainer container) {
    if (state.pathStack.length < 2) return;
    final parentSegment = state.pathStack[state.pathStack.length - 2];
    if (parentSegment.items != null && parentSegment.items!.isNotEmpty) return;

    unawaited(() async {
      try {
        final raw = await ref.read(vaultFileIoApiProvider).listDirectory(
              container,
              parentSegment.fatPath,
            );
        if (raw != null) {
          final parsed = raw
              .where((f) => !f.startsWith('System:'))
              .map(RawEntry.parse)
              .toList();
          parentSegment.items = parsed;
        }
      } catch (e) {
        VeLog.w('FileBrowserNavigation', 'Parent prefetch failed at ${VeLog.censorUri(parentSegment.fatPath)}', e);
      }
    }());
  }

  void removeItemsByName(Set<String> deletedNames) {
    final lowerNames = deletedNames.map((n) => n.toLowerCase()).toSet();
    final updated = state.currentItems
        .where((e) => !lowerNames.contains(e.name.toLowerCase()))
        .toList();
    state = state.copyWith(currentItems: updated);
    if (state.pathStack.isNotEmpty) {
      state.pathStack.last.items = List<RawEntry>.of(updated);
    }
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  Future<void> loadDirectoryContents(
    MountedContainer container,
    String path, {
    bool refresh = false,
    BrowserLayoutMode? layoutMode,
    VoidCallback? onActivity,
  }) async {
    final generation = ++_loadGeneration;
    onActivity?.call();

    state = state.copyWith(
      isLoading: state.currentItems.isEmpty ? true : state.isLoading,
      layoutMode: layoutMode ?? state.layoutMode,
    );

    if (state.archiveContext != null) {
      _loadArchiveContents(path, layoutMode: layoutMode);
      return;
    }

    try {
      final items = await ref.read(vaultFileIoApiProvider).listDirectory(
            container,
            path,
            refresh: refresh,
          );

      if (!ref.mounted ||
          generation != _loadGeneration ||
          path != state.currentDirPath) {
        return;
      }

      final isTruncated = items?.any((f) => f == 'System:TRUNCATED') ?? false;
      final parsed = items
              ?.where((f) => !f.startsWith('System:'))
              .map(RawEntry.parse)
              .toList() ??
          <RawEntry>[];

      // Save the freshly loaded items on the active path segment
      if (state.pathStack.isNotEmpty && state.pathStack.last.fatPath == path) {
        state.pathStack.last.items = List<RawEntry>.of(parsed);
        state.pathStack.last.layoutMode = layoutMode ?? state.layoutMode;
      }

      state = state.copyWith(
        currentItems: parsed,
        isListingTruncated: isTruncated,
        isLoading: false,
      );

      // Ensure the level directly above has items cached for the back gesture
      _prefetchParentIfMissing(container);

      // Async update for free space info
      unawaited(
        ref.read(vaultFileIoApiProvider).getSpaceInfo(container).then((space) {
          if (ref.mounted &&
              generation == _loadGeneration &&
              space != null &&
              space.length > 1 &&
              space[0] > 0 &&
              space[1] >= 0) {
            state = state.copyWith(freeSpace: space[1]);
          }
        }).catchError((_) {}),
      );
    } catch (e) {
      if (!ref.mounted || generation != _loadGeneration) return;
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  void _loadArchiveContents(String path, {BrowserLayoutMode? layoutMode}) {
    final ctx = state.archiveContext;
    if (ctx == null) return;
    final archiveRootPath = state.pathStack[ctx.pathStackEntryIndex].fatPath;
    String subPath = '';
    if (path.length > archiveRootPath.length) {
      subPath = path.substring(archiveRootPath.length);
      if (subPath.startsWith('/')) subPath = subPath.substring(1);
    }
    final items = ctx.listDirectory(subPath);
    final parsed = items.map(RawEntry.parse).toList();

    if (state.pathStack.isNotEmpty && state.pathStack.last.fatPath == path) {
      state.pathStack.last.items = List<RawEntry>.of(parsed);
      state.pathStack.last.layoutMode = layoutMode ?? state.layoutMode;
    }

    state = state.copyWith(
      currentItems: parsed,
      isListingTruncated: false,
      isLoading: false,
      layoutMode: layoutMode ?? state.layoutMode,
    );
  }

  Future<ArchiveContext> openArchive(
    MountedContainer container,
    String fullPath,
    String archiveName, {
    String? passphrase,
    BrowserLayoutMode? layoutMode,
    VoidCallback? onActivity,
  }) async {
    onActivity?.call();

    // Cache current directory items before entering archive
    if (state.pathStack.isNotEmpty) {
      state.pathStack.last.items = List<RawEntry>.of(state.currentItems);
      state.pathStack.last.layoutMode = state.layoutMode;
    }

    final parentPreviewItems = state.currentItems.isNotEmpty
        ? List<RawEntry>.of(state.currentItems)
        : (state.pathStack.isNotEmpty && state.pathStack.last.items != null
            ? List<RawEntry>.of(state.pathStack.last.items!)
            : null);

    state = state.copyWith(
      isLoading: true,
      currentItems: const [],
      clearCurrentFilter: true,
    );

    try {
      final ctx = container.isLocalStorage
          ? await ArchiveService.openLocal(
              pathOrUri: p.join(container.uri, fullPath),
              archiveName: archiveName,
              pathStackEntryIndex: state.pathStack.length,
              passphrase: passphrase,
            )
          : await ArchiveService.open(
              container: container,
              archivePathInContainer: fullPath,
              pathStackEntryIndex: state.pathStack.length,
              passphrase: passphrase,
            );

      if (ctx.status == ArchiveOpenStatus.passphraseRequired ||
          ctx.status == ArchiveOpenStatus.wrongPassphrase) {
        state = state.copyWith(isLoading: false);
        return ctx;
      }

      final newStack = List<PathSegment>.from(state.pathStack)
        ..add(PathSegment(
          archiveName,
          fullPath,
          isArchiveRoot: true,
          layoutMode: layoutMode ?? state.layoutMode,
          previewItems: parentPreviewItems,
          previewLayoutMode: state.layoutMode,
        ));

      state = state.copyWith(
        archiveContext: ctx,
        pathStack: newStack,
        layoutMode: layoutMode ?? state.layoutMode,
      );
      _liveArchiveContext = ctx;

      _loadArchiveContents(fullPath, layoutMode: layoutMode);
      return ctx;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  void closeArchive() {
    state.archiveContext?.dispose();
    state = state.copyWith(clearArchiveContext: true);
    _liveArchiveContext = null;
  }

  void enterDirectory(
    RawEntry entry, {
    required String newPath,
    BrowserLayoutMode? layoutMode,
    double currentScrollOffset = 0.0,
  }) {
    // 1. Save current folder's state and items onto its own segment
    if (state.pathStack.isNotEmpty) {
      state.pathStack.last.scrollOffset = currentScrollOffset;
      state.pathStack.last.items = List<RawEntry>.of(state.currentItems);
      state.pathStack.last.layoutMode = state.layoutMode;
    }

    // Capture parent listing as a back-gesture preview for the child segment
    final parentPreviewItems = state.currentItems.isNotEmpty
        ? List<RawEntry>.of(state.currentItems)
        : (state.pathStack.isNotEmpty && state.pathStack.last.items != null
            ? List<RawEntry>.of(state.pathStack.last.items!)
            : null);

    // 2. Create child segment
    final newSegment = PathSegment(
      entry.name,
      newPath,
      layoutMode: layoutMode ?? state.layoutMode,
      previewItems: parentPreviewItems,
      previewLayoutMode: state.layoutMode,
    );

    final newStack = List<PathSegment>.from(state.pathStack)..add(newSegment);

    state = state.copyWith(
      pathStack: newStack,
      currentItems: const [],
      clearCurrentFilter: true,
      isLoading: true,
      layoutMode: layoutMode ?? state.layoutMode,
    );
  }

  String? navigateUp({BrowserLayoutMode? layoutMode}) {
    if (state.atRoot) return null;

    final ctx = state.archiveContext;
    if (ctx != null && state.pathStack.length - 1 <= ctx.pathStackEntryIndex) {
      closeArchive();
    }

    final newStack = List<PathSegment>.from(state.pathStack)..removeLast();
    final targetSegment = newStack.last;
    final newPath = targetSegment.fatPath;

    // Immediately restore cached items from the parent segment
    final restoredItems = targetSegment.items ?? const <RawEntry>[];

    state = state.copyWith(
      pathStack: newStack,
      currentItems: List<RawEntry>.of(restoredItems),
      clearCurrentFilter: true,
      isLoading: restoredItems.isEmpty,
      layoutMode: layoutMode ?? targetSegment.layoutMode ?? state.layoutMode,
    );

    return newPath;
  }

  String? jumpTo(int index, {BrowserLayoutMode? layoutMode}) {
    if (index >= state.pathStack.length - 1 || index < 0) return null;

    final ctx = state.archiveContext;
    if (ctx != null && index < ctx.pathStackEntryIndex) {
      closeArchive();
    }

    final targetSegment = state.pathStack[index];
    final newStack = state.pathStack.sublist(0, index + 1);
    final newPath = targetSegment.fatPath;
    final restoredItems = targetSegment.items ?? const <RawEntry>[];

    state = state.copyWith(
      pathStack: newStack,
      currentItems: List<RawEntry>.of(restoredItems),
      clearCurrentFilter: true,
      isLoading: restoredItems.isEmpty,
      layoutMode: layoutMode ?? targetSegment.layoutMode ?? state.layoutMode,
    );

    return newPath;
  }

  String navigateToPath(
    MountedContainer container,
    String fullPath, {
    required bool isDir,
    required String rootLabel,
    BrowserLayoutMode? layoutMode,
    BrowserLayoutMode Function(String path)? resolveLayoutMode,
    VoidCallback? onActivity,
  }) {
    onActivity?.call();
    if (state.archiveContext != null) closeArchive();

    // Preserve any segments that were already visited so their cached items stay intact
    final existingByPath = {
      for (final seg in state.pathStack) seg.fatPath: seg,
    };

    PathSegment makeOrReuse(String label, String fatPath) {
      final effectiveMode = resolveLayoutMode?.call(fatPath) ?? layoutMode;
      if (existingByPath.containsKey(fatPath)) {
        final existing = existingByPath[fatPath]!;
        if (effectiveMode != null) existing.layoutMode = effectiveMode;
        return existing;
      }
      return PathSegment(label, fatPath, layoutMode: effectiveMode);
    }

    final segments = fullPath.isEmpty ? <String>[] : fullPath.split('/');

    if (isDir) {
      final newStack = [makeOrReuse(rootLabel, '')];
      String current = '';
      for (final seg in segments) {
        current = current.isEmpty ? seg : '$current/$seg';
        newStack.add(makeOrReuse(seg, current));
      }
      state = state.copyWith(
        pathStack: newStack,
        currentItems: const [],
        clearCurrentFilter: true,
        isLoading: true,
        layoutMode: layoutMode ?? state.layoutMode,
      );

      // Preload parent in background so swiping back displays the parent layout immediately
      _prefetchParentIfMissing(container);
      return current;
    } else {
      final parentPath = segments.length > 1
          ? segments.sublist(0, segments.length - 1).join('/')
          : '';
      final newStack = [makeOrReuse(rootLabel, '')];
      if (parentPath.isNotEmpty) {
        final parentSegments = parentPath.split('/');
        String current = '';
        for (final seg in parentSegments) {
          current = current.isEmpty ? seg : '$current/$seg';
          newStack.add(makeOrReuse(seg, current));
        }
      }
      state = state.copyWith(
        pathStack: newStack,
        currentItems: const [],
        clearCurrentFilter: true,
        isLoading: true,
        layoutMode: layoutMode ?? state.layoutMode,
      );

      _prefetchParentIfMissing(container);
      return parentPath;
    }
  }

  bool startBackGesture(double progress, {BrowserLayoutMode? layoutMode}) {
    if (state.atRoot) return false;

    // Read the parent segment we are swiping back to (length - 2)
    final targetSegment = state.pathStack[state.pathStack.length - 2];
    final currentSegment = state.pathStack.last;
    final atRootAfterBack = state.pathStack.length == 2;
    final effectiveLayoutMode =
        layoutMode ?? currentSegment.previewLayoutMode ?? targetSegment.layoutMode ?? state.layoutMode;

    final previewItems = currentSegment.previewItems ?? targetSegment.items;

    state = state.copyWith(
      backGestureProgress: progress,
      backGesturePreviewItems: previewItems != null
          ? List<RawEntry>.of(previewItems)
          : null,
      backGesturePreviewLayoutMode: effectiveLayoutMode,
      backGesturePreviewDirPath: targetSegment.fatPath,
      backGesturePreviewAtRoot: atRootAfterBack,
    );
    return true;
  }

  void updateBackGestureProgress(double progress) {
    state = state.copyWith(backGestureProgress: progress);
  }

  void cancelBackGesture() {
    state = state.copyWith(clearBackGesturePreview: true);
  }

  void commitBackGesture() {
    state = state.copyWith(backGestureProgress: 1.0);
  }

  void clearBackGesturePreview() {
    state = state.copyWith(clearBackGesturePreview: true);
  }
}