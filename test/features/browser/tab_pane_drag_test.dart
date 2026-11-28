import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/controllers/tab_pane_drag.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  TabPaneDrag listen(BrowserTabsConfig config) {
    final subscription = container.listen<TabPaneDrag>(
      tabPaneDragProvider(config),
      (_, _) {},
    );
    addTearDown(subscription.close);
    return subscription.read();
  }

  group('tabPaneDragProvider', () {
    test('a workspace has one, shared by everything that listens', () {
      final config = BrowserTabsConfig.create(includeDashboardTab: true);
      expect(listen(config), same(listen(config)));
    });

    test('workspaces do not share it', () {
      final one = BrowserTabsConfig.create(includeDashboardTab: true);
      final two = BrowserTabsConfig.create(includeDashboardTab: true);
      expect(listen(one), isNot(same(listen(two))));
    });

    test('nothing is hovered to begin with', () {
      final drag = listen(BrowserTabsConfig.create(includeDashboardTab: true));
      expect(drag.hover.value, isNull);
      expect(drag.paneBounds, isNull);
    });

    test('what the page publishes is what a strip finds', () {
      final drag = listen(BrowserTabsConfig.create(includeDashboardTab: true));
      drag.paneBounds = (pane) => pane == TabPane.secondary
          ? const Rect.fromLTWH(500, 40, 500, 600)
          : null;
      expect(
        drag.paneBounds!(TabPane.secondary),
        const Rect.fromLTWH(500, 40, 500, 600),
      );
      expect(drag.paneBounds!(TabPane.primary), isNull);
    });

    test('the pane a tab is held over is announced as it changes', () {
      final drag = listen(BrowserTabsConfig.create(includeDashboardTab: true));
      final seen = <TabPane?>[];
      drag.hover.addListener(() => seen.add(drag.hover.value));
      drag.hover.value = TabPane.secondary;
      drag.hover.value = TabPane.secondary; // no change, nothing to announce
      drag.hover.value = null;
      expect(seen, [TabPane.secondary, null]);
    });
  });
}
