// Selection Controller from the migration plan's Phase 4 worked example
// ("FileBrowserSelectionController ... Replaces any custom selection
// mixins"). Was SelectionMixin<FileBrowserScreen>, mixed directly into
// _FileBrowserScreenState. Family-keyed by the container's volId: one
// FileBrowserScreen instance handles every directory within a single
// mounted container via its own _pathStack (there's no per-directory
// screen push), so volId is the right scope -- selection persists across
// folders within one browsing session and is isolated between containers.
//
// Deliberately autoDispose (the default, no `keepAlive`): selection is
// screen-session state, not app-wide state that should survive after the
// browser closes.
//
// state is a small immutable record rather than just Set<RawEntry> so the
// async-resolved folder sizes are reactive too (widgets watching this
// provider see hasPendingFolderSizes/selectedTotalBytes update as each
// folder's size comes back), without a second provider to keep in sync.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'file_browser_selection_controller.g.dart';

typedef FileBrowserSelectionState = ({
  Set<RawEntry> items,
  Map<String, int> resolvedFolderSizes,
});

const _emptySelection = (
  items: <RawEntry>{},
  resolvedFolderSizes: <String, int>{},
);

@riverpod
class FileBrowserSelection extends _$FileBrowserSelection {
  bool _fetchingFolderSizes = false;

  @override
  FileBrowserSelectionState build(int volId) => _emptySelection;

  void toggleSelectItem(RawEntry item) {
    final items = {...state.items};
    if (items.contains(item)) {
      items.remove(item);
    } else {
      items.add(item);
    }
    state = (items: items, resolvedFolderSizes: state.resolvedFolderSizes);
  }

  /// Sets the selected items in bulk, commonly called during hold range
  /// selection.
  void setSelectedItems(Set<RawEntry> newSelection) {
    state = (
      items: {...newSelection},
      resolvedFolderSizes: state.resolvedFolderSizes,
    );
  }

  void exitSelectionMode() {
    state = _emptySelection;
  }

  /// Fetches the recursive byte total for every selected directory whose
  /// size has not yet been resolved.
  ///
  /// Call this from the host screen whenever the selection changes and
  /// `state.selectedFolderCount > 0`. Each resolved size updates [state]
  /// (so the label updates progressively as sizes arrive, rather than
  /// waiting for all of them). Re-entrant-safe: concurrent calls are
  /// serialised via [_fetchingFolderSizes]; newly selected folders
  /// discovered after the guard is set are picked up on the next call.
  Future<void> fetchFolderSizes(
    MountedContainer container,
    String currentDirPath,
  ) async {
    if (_fetchingFolderSizes) return;
    _fetchingFolderSizes = true;

    try {
      final pending = state.items
          .where((e) => e.isDir)
          .where((e) => !state.resolvedFolderSizes.containsKey(e.name))
          .toList(growable: false);

      for (final e in pending) {
        if (!ref.mounted) return;

        final fatPath = currentDirPath.isEmpty
            ? e.name
            : '$currentDirPath/${e.name}';

        final size = await vaultExplorerApi.getFolderSize(container, fatPath);

        if (!ref.mounted) return;

        state = (
          items: state.items,
          resolvedFolderSizes: {...state.resolvedFolderSizes, e.name: size},
        );
      }
    } finally {
      _fetchingFolderSizes = false;
    }
  }
}

/// Derived getters, kept as extension methods (rather than Notifier
/// getters) so they recompute whenever a widget watches [state] itself --
/// a getter on the cached Notifier *instance* wouldn't trigger a rebuild
/// on its own.
extension FileBrowserSelectionStateX on FileBrowserSelectionState {
  bool get isSelectionMode => items.isNotEmpty;

  int get selectedFileCount => items.where((e) => !e.isDir).length;
  int get selectedFolderCount => items.where((e) => e.isDir).length;

  /// Byte sum of all selected *files*. Directories are always 0 here; use
  /// [selectedTotalBytes] once folder sizes have been resolved.
  int get selectedFileBytes {
    int sum = 0;
    for (final e in items) {
      if (!e.isDir) sum += e.sizeBytes;
    }
    return sum;
  }

  /// Byte sum of selected files PLUS any folder sizes already resolved.
  int get selectedTotalBytes {
    int sum = selectedFileBytes;
    for (final e in items) {
      if (e.isDir) sum += resolvedFolderSizes[e.name] ?? 0;
    }
    return sum;
  }

  /// True while at least one selected folder has not yet been sized.
  bool get hasPendingFolderSizes {
    for (final e in items) {
      if (e.isDir && !resolvedFolderSizes.containsKey(e.name)) return true;
    }
    return false;
  }

  /// Ready-to-display summary for the selection action-bar, e.g.
  /// "3 files · 42.3 MB" or "2 folders (calculating…)".
  String selectionSummary(AppLocalizations l10n) {
    final fc = selectedFolderCount;
    final fileSize = selectedFileBytes;
    final total = selectedTotalBytes;
    final fileCount = selectedFileCount;
    final filePart = fileCount > 0
        ? '${l10n.statsFileCount(fileCount)}'
              '${fileSize > 0 ? ' · ${formatBytes(fileSize)}' : ''}'
        : '';
    if (fc == 0) return filePart;
    final folderLabel = l10n.statsFolderCount(fc);
    final String folderSizePart;
    if (hasPendingFolderSizes) {
      folderSizePart = '(${l10n.sizeCalculatingLabel})';
    } else {
      final resolvedBytes = total - fileSize;
      folderSizePart = resolvedBytes > 0
          ? '· ${formatBytes(resolvedBytes)}'
          : '';
    }
    final folderPart = '$folderLabel $folderSizePart'.trim();
    if (filePart.isEmpty) return folderPart;
    return l10n.selectionSummaryCombined(filePart, folderPart);
  }
}
