import 'dart:async';
import 'package:flutter/services.dart';
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

  List<RawEntry>? previewItems;
  BrowserLayoutMode? previewLayoutMode;

  PathSegment(
    this.label,
    this.fatPath, {
    this.isArchiveRoot = false,
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

  /// Mirrors `state.archiveContext`, kept in sync at its two write sites
  /// below (openArchive/closeArchive). `ref.onDispose`'s callback can't
  /// safely read this Notifier's own `state` -- Riverpod disallows
  /// accessing `state` from inside a lifecycle callback and throws
  /// "Cannot use Ref or modify other providers inside life-cycles/
  /// selectors" (hit as a real runtime crash: this used to read
  /// `state.archiveContext` directly here). Final cleanup on provider
  /// disposal reads this plain field instead.
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
        pathStack: [PathSegment(rootLabel, '')],
        layoutMode: layoutMode,
      );
    }
  }

  void setLayoutMode(BrowserLayoutMode mode) {
    state = state.copyWith(layoutMode: mode);
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

  void removeItemsByName(Set<String> deletedNames) {
    final lowerNames = deletedNames.map((n) => n.toLowerCase()).toSet();
    final updated =
        state.currentItems.where((e) => !lowerNames.contains(e.name.toLowerCase())).toList();
    state = state.copyWith(currentItems: updated);
  }

  /// For loading states that aren't a directory load/navigation of their
  /// own (e.g. extracting a single file from an open archive) but still
  /// drive the same screen-wide loading indicator the original code used
  /// one shared `_isLoading` flag for.
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

      if (!ref.mounted || generation != _loadGeneration || path != state.currentDirPath) {
        return;
      }

      final isTruncated = items?.any((f) => f == 'System:TRUNCATED') ?? false;
      final parsed = items
              ?.where((f) => !f.startsWith('System:'))
              .map(RawEntry.parse)
              .toList() ??
          <RawEntry>[];

      state = state.copyWith(
        currentItems: parsed,
        isListingTruncated: isTruncated,
        isLoading: false,
      );

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
      // No l10n here (Notifiers have no BuildContext) -- rethrow so the
      // screen's own try/catch can turn this into a localized status
      // message via _setStatus, same as the original inline code did.
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
    state = state.copyWith(
      currentItems: items.map(RawEntry.parse).toList(),
      isListingTruncated: false,
      isLoading: false,
      layoutMode: layoutMode ?? state.layoutMode,
    );
  }

  Future<void> openArchive(
    MountedContainer container,
    String fullPath,
    String archiveName, {
    BrowserLayoutMode? layoutMode,
    VoidCallback? onActivity,
  }) async {
    onActivity?.call();
    state = state.copyWith(
      isLoading: true,
      currentItems: const [],
      clearCurrentFilter: true,
    );

    try {
      final ctx = await ArchiveService.open(
        container: container,
        archivePathInContainer: fullPath,
        pathStackEntryIndex: state.pathStack.length,
      );

      final newStack = List<PathSegment>.from(state.pathStack)
        ..add(PathSegment(archiveName, fullPath, isArchiveRoot: true));

      state = state.copyWith(
        archiveContext: ctx,
        pathStack: newStack,
        layoutMode: layoutMode ?? state.layoutMode,
      );
      _liveArchiveContext = ctx;

      _loadArchiveContents(fullPath, layoutMode: layoutMode);
    } catch (e) {
      // No l10n here -- see loadDirectoryContents's catch for why this
      // rethrows instead of setting statusMessage directly.
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
  }) {
    final parentPreviewItems = List<RawEntry>.of(state.currentItems);
    final parentPreviewLayoutMode = state.layoutMode;

    final newSegment = PathSegment(
      entry.name,
      newPath,
      previewItems: parentPreviewItems,
      previewLayoutMode: parentPreviewLayoutMode,
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
    final newPath = newStack.last.fatPath;

    state = state.copyWith(
      pathStack: newStack,
      currentItems: const [],
      clearCurrentFilter: true,
      isLoading: true,
      layoutMode: layoutMode ?? state.layoutMode,
    );

    return newPath;
  }

  String? jumpTo(int index, {BrowserLayoutMode? layoutMode}) {
    if (index >= state.pathStack.length - 1 || index < 0) return null;

    final ctx = state.archiveContext;
    if (ctx != null && index < ctx.pathStackEntryIndex) {
      closeArchive();
    }

    final newStack = state.pathStack.sublist(0, index + 1);
    final newPath = newStack.last.fatPath;

    state = state.copyWith(
      pathStack: newStack,
      currentItems: const [],
      clearCurrentFilter: true,
      isLoading: true,
      layoutMode: layoutMode ?? state.layoutMode,
    );

    return newPath;
  }

  String navigateToPath(
    MountedContainer container,
    String fullPath, {
    required bool isDir,
    required String rootLabel,
    BrowserLayoutMode? layoutMode,
    VoidCallback? onActivity,
  }) {
    onActivity?.call();
    if (state.archiveContext != null) closeArchive();
    final segments = fullPath.isEmpty ? <String>[] : fullPath.split('/');

    if (isDir) {
      final newStack = [PathSegment(rootLabel, '')];
      String current = '';
      for (final seg in segments) {
        current = current.isEmpty ? seg : '$current/$seg';
        newStack.add(PathSegment(seg, current));
      }
      state = state.copyWith(
        pathStack: newStack,
        currentItems: const [],
        clearCurrentFilter: true,
        isLoading: true,
        layoutMode: layoutMode ?? state.layoutMode,
      );
      return current;
    } else {
      final parentPath = segments.length > 1
          ? segments.sublist(0, segments.length - 1).join('/')
          : '';
      final newStack = [PathSegment(rootLabel, '')];
      if (parentPath.isNotEmpty) {
        final parentSegments = parentPath.split('/');
        String current = '';
        for (final seg in parentSegments) {
          current = current.isEmpty ? seg : '$current/$seg';
          newStack.add(PathSegment(seg, current));
        }
      }
      state = state.copyWith(
        pathStack: newStack,
        currentItems: const [],
        clearCurrentFilter: true,
        isLoading: true,
        layoutMode: layoutMode ?? state.layoutMode,
      );
      return parentPath;
    }
  }

  bool startBackGesture(double progress) {
    if (state.atRoot) return false;
    final currentSegment = state.pathStack.last;
    final targetDirPath = state.pathStack[state.pathStack.length - 2].fatPath;
    final atRootAfterBack = state.pathStack.length == 2;

    state = state.copyWith(
      backGestureProgress: progress,
      backGesturePreviewItems: currentSegment.previewItems,
      backGesturePreviewLayoutMode: currentSegment.previewLayoutMode,
      backGesturePreviewDirPath: targetDirPath,
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