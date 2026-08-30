import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_sort_controller.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

void main() {
  group('FileBrowserSort Controller Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial sort state is name ascending', () {
      final state = container.read(fileBrowserSortProvider(1));
      expect(state.sortBy, SortBy.name);
      expect(state.sortAscending, isTrue);
    });

    test('Toggling the same sort field flips sortAscending', () {
      final notifier = container.read(fileBrowserSortProvider(1).notifier);

      // Toggling name (currently true -> false)
      notifier.setSort(SortBy.name);
      var state = container.read(fileBrowserSortProvider(1));
      expect(state.sortBy, SortBy.name);
      expect(state.sortAscending, isFalse);

      // Toggling name again (false -> true)
      notifier.setSort(SortBy.name);
      state = container.read(fileBrowserSortProvider(1));
      expect(state.sortBy, SortBy.name);
      expect(state.sortAscending, isTrue);
    });

    test('Switching to a different sort field sets default direction for that field', () {
      final notifier = container.read(fileBrowserSortProvider(1).notifier);

      // Switching to size defaults to descending (false)
      notifier.setSort(SortBy.size);
      var state = container.read(fileBrowserSortProvider(1));
      expect(state.sortBy, SortBy.size);
      expect(state.sortAscending, isFalse);

      // Switching to date defaults to descending (false)
      notifier.setSort(SortBy.date);
      state = container.read(fileBrowserSortProvider(1));
      expect(state.sortBy, SortBy.date);
      expect(state.sortAscending, isFalse);

      // Switching to extension defaults to ascending (true)
      notifier.setSort(SortBy.extension);
      state = container.read(fileBrowserSortProvider(1));
      expect(state.sortBy, SortBy.extension);
      expect(state.sortAscending, isTrue);

      // Switching back to name defaults to ascending (true)
      notifier.setSort(SortBy.name);
      state = container.read(fileBrowserSortProvider(1));
      expect(state.sortBy, SortBy.name);
      expect(state.sortAscending, isTrue);
    });

    test('restore sets both sort and ascending directly', () {
      final notifier = container.read(fileBrowserSortProvider(1).notifier);

      notifier.restore(SortBy.date, true);
      final state = container.read(fileBrowserSortProvider(1));
      expect(state.sortBy, SortBy.date);
      expect(state.sortAscending, isTrue);
    });

    test('FileBrowserSortStateX.compare correctly sorts entries', () {
      const entryA = RawEntry(name: 'a.txt', isDir: false, sizeBytes: 100, modifiedSecs: 1000);
      const entryB = RawEntry(name: 'b.txt', isDir: false, sizeBytes: 500, modifiedSecs: 2000);

      // Sort by Name Ascending: a.txt before b.txt
      var state = container.read(fileBrowserSortProvider(1));
      expect(state.compare(entryA, entryB), lessThan(0));
      expect(state.compare(entryB, entryA), greaterThan(0));

      // Sort by Size Descending
      container.read(fileBrowserSortProvider(1).notifier).setSort(SortBy.size);
      state = container.read(fileBrowserSortProvider(1));
      // Between files: entryB (500) comes before entryA (100)
      expect(state.compare(entryB, entryA), lessThan(0));
    });

    test('Family keyed per volId isolates sort state', () {
      container.read(fileBrowserSortProvider(1).notifier).setSort(SortBy.size);
      container.read(fileBrowserSortProvider(2).notifier).setSort(SortBy.date);

      expect(container.read(fileBrowserSortProvider(1)).sortBy, SortBy.size);
      expect(container.read(fileBrowserSortProvider(2)).sortBy, SortBy.date);
    });
  });
}
