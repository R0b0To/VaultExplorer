// Sort & Filter Controller from the migration plan's Phase 4 worked
// example ("FileBrowserSortController ... Replaces any custom sort
// mixins"). Was SortMixin<FileBrowserScreen>, mixed directly into
// _FileBrowserScreenState. Family-keyed by the container's volId for the
// same reason as FileBrowserSelection (see file_browser_selection_controller.dart):
// one screen instance covers a whole container's directory tree.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

part 'file_browser_sort_controller.g.dart';

typedef FileBrowserSortState = ({SortBy sortBy, bool sortAscending});

const _defaultSortState = (sortBy: SortBy.name, sortAscending: true);

@riverpod
class FileBrowserSort extends _$FileBrowserSort {
  @override
  FileBrowserSortState build(int volId) => _defaultSortState;

  void setSort(SortBy by) {
    if (state.sortBy == by) {
      state = (sortBy: by, sortAscending: !state.sortAscending);
    } else {
      final ascending = switch (by) {
        SortBy.name => true,
        SortBy.extension => true,
        SortBy.size => false,
        SortBy.date => false,
      };
      state = (sortBy: by, sortAscending: ascending);
    }
  }

  /// Sets both fields directly (no toggle-on-same-field logic) -- used
  /// when restoring the user's saved default sort from AppSettings on
  /// screen init, as opposed to a toolbar tap via [setSort].
  void restore(SortBy by, bool ascending) {
    state = (sortBy: by, sortAscending: ascending);
  }
}

extension FileBrowserSortStateX on FileBrowserSortState {
  int compare(RawEntry ea, RawEntry eb) => compareEntriesBySort(
    ea,
    eb,
    sortBy: sortBy,
    sortAscending: sortAscending,
  );
}
