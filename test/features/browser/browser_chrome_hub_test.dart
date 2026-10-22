import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_chrome_hub.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';

MountedContainer _container(int volId) => MountedContainer(
  uri: 'vault://$volId',
  displayName: 'vault$volId',
  volId: volId,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 0,
  freeSpace: 0,
);

// Distinct functions, so identity tells the tests which bar is showing.
PreferredSizeWidget _barA(BuildContext context) =>
    const PreferredSize(preferredSize: Size.zero, child: SizedBox());
PreferredSizeWidget _barB(BuildContext context) =>
    const PreferredSize(preferredSize: Size.zero, child: SizedBox());

const Widget _fabOne = SizedBox(key: ValueKey<String>('fab-1'));
const Widget _bottomOne = SizedBox(key: ValueKey<String>('bottom-1'));

class _Harness {
  _Harness(this.config, this.tabs, this.hub);
  final BrowserTabsConfig config;
  final BrowserTabs tabs;
  final BrowserChromeHub hub;
}

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  /// Both providers are auto-dispose; hold listeners, as the shell does.
  _Harness open({bool dashboard = false}) {
    final config = BrowserTabsConfig.create(
      initialContainer: _container(1),
      includeDashboardTab: dashboard,
    );
    final workspace = container.listen<BrowserTabsState>(
      browserTabsProvider(config),
      (_, _) {},
    );
    final hub = container.listen<BrowserChromeHub>(
      browserChromeProvider(config),
      (_, _) {},
    );
    addTearDown(workspace.close);
    addTearDown(hub.close);
    return _Harness(
      config,
      container.read(browserTabsProvider(config).notifier),
      hub.read(),
    );
  }

  TabId activeId(_Harness h) =>
      container.read(browserTabsProvider(h.config)).activeTabId!;

  group('BrowserChromeHub', () {
    test('shows the active tab app bar once it has published', () {
      final h = open();
      expect(h.hub.appBar.value, isNull);
      h.hub.setAppBar(activeId(h), _barA);
      expect(h.hub.appBar.value, equals(_barA));
    });

    test('holds a background tab\'s chrome until it becomes active', () {
      final h = open();
      final background = h.tabs.openTab(_container(2), activate: false)!;
      h.hub.setAppBar(background, _barB);
      expect(h.hub.appBar.value, isNull);

      h.tabs.activate(background);
      expect(h.hub.appBar.value, equals(_barB));
    });

    test('keeps the previous app bar while a new tab has not published', () {
      final h = open();
      final first = activeId(h);
      h.hub.setAppBar(first, _barA);

      final second = h.tabs.openTab(_container(2))!;
      expect(h.hub.appBar.value, equals(_barA));

      h.hub.setAppBar(second, _barB);
      expect(h.hub.appBar.value, equals(_barB));

      h.tabs.activate(first);
      expect(h.hub.appBar.value, equals(_barA));
    });

    test('keeps the floating action across tabs until one publishes null', () {
      final h = open();
      final first = activeId(h);
      h.hub.setFloatingAction(first, _fabOne);

      final second = h.tabs.openTab(_container(2))!;
      expect(h.hub.floatingAction.value, same(_fabOne));

      h.hub.setFloatingAction(second, null);
      expect(h.hub.floatingAction.value, isNull);

      h.tabs.activate(first);
      expect(h.hub.floatingAction.value, same(_fabOne));
    });

    test('bottom bar belongs to its tab and is not carried over', () {
      final h = open();
      final first = activeId(h);
      h.hub.setBottomBar(first, _bottomOne);
      expect(h.hub.bottomBar.value, same(_bottomOne));

      h.tabs.openTab(_container(2));
      expect(h.hub.bottomBar.value, isNull);

      h.tabs.activate(first);
      expect(h.hub.bottomBar.value, same(_bottomOne));
    });

    test('Home shows the dashboard app bar', () {
      final h = open(dashboard: true);
      h.tabs.openDashboardTab();
      expect(
        container.read(browserTabsProvider(h.config)).activeTab!.isDashboard,
        isTrue,
      );
      expect(h.hub.appBar.value, equals(dashboardBrowserAppBarFactory));
    });

    test('selection app bar follows the active tab and can be cleared', () {
      final h = open();
      final first = activeId(h);
      h.hub.setSelectionAppBar(first, _barA);
      expect(h.hub.selectionAppBar.value, equals(_barA));

      h.hub.setSelectionAppBar(first, null);
      expect(h.hub.selectionAppBar.value, isNull);
    });

    test('tracks tabs on screen besides the active one', () {
      final h = open();
      final first = activeId(h);
      final second = h.tabs.openTab(_container(2), activate: false)!;
      expect(h.hub.visibleTabs.value, isEmpty);

      h.hub.setVisibleTabs({first, second});
      expect(h.hub.visibleTabs.value, {first, second});

      var notifications = 0;
      h.hub.visibleTabs.addListener(() => notifications++);
      h.hub.setVisibleTabs({first, second});
      expect(notifications, 0, reason: 'an identical set is not a change');

      h.tabs.closeByVolId(2);
      expect(h.hub.visibleTabs.value, {first});
      expect(notifications, 1);
    });

    test('ignores contributions after it has been disposed', () {
      final h = open();
      final first = activeId(h);
      final standalone = BrowserChromeHub(
        initial: container.read(browserTabsProvider(h.config)),
        readSelection: () => const AggregatedTabsSelection(
          itemsByTab: {},
          count: 0,
          bytes: 0,
          hasPendingFolderSizes: false,
        ),
      );
      standalone.dispose();
      standalone.setAppBar(first, _barA);
      standalone.setFloatingAction(first, _fabOne);
    });
  });
}
