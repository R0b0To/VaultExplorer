import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_explorer_controller.dart';
import 'package:vaultexplorer/features/decoy/local/widgets/local_type_filter_button.dart';

void main() {
  late ProviderContainer container;
  late ProviderSubscription<DecoyLocalExplorerState> subscription;

  setUp(() {
    container = ProviderContainer();
    subscription = container.listen(decoyLocalExplorerProvider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    container.dispose();
  });

  group('DecoyLocalExplorer controller', () {
    test('starts in the access-checking state', () {
      final state = container.read(decoyLocalExplorerProvider);

      expect(state.checkingAccess, isTrue);
      expect(state.hasAccess, isFalse);
      expect(state.entries, isEmpty);
      expect(state.searchActive, isFalse);
    });

    test('owns search, filter, and layout presentation state', () {
      final controller = container.read(decoyLocalExplorerProvider.notifier);

      controller.openSearch();
      controller.setSearchQuery('receipt');
      controller.setTypeFilter(LocalTypeFilter.document);
      controller.setLayoutMode(BrowserLayoutMode.grid);

      var state = container.read(decoyLocalExplorerProvider);
      expect(state.searchActive, isTrue);
      expect(state.searchQuery, 'receipt');
      expect(state.typeFilter, LocalTypeFilter.document);
      expect(state.layoutMode, BrowserLayoutMode.grid);

      controller.closeSearch();
      state = container.read(decoyLocalExplorerProvider);
      expect(state.searchActive, isFalse);
      expect(state.searchQuery, isEmpty);
    });
  });
}
