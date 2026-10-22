import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/models/browser_tab_origin.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';

MountedContainer _container(int volId, [String? name]) => MountedContainer(
  uri: 'vault://$volId',
  displayName: name ?? 'vault$volId',
  volId: volId,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 0,
  freeSpace: 0,
);

/// One workspace under test. The notifier is auto-dispose, so a listener is
/// held for the length of the test, the way the shell holds one.
class _Workspace {
  _Workspace(
    this._container,
    MountedContainer initial, {
    bool appRoot = false,
    bool includeDashboardTab = false,
  }) : config = BrowserTabsConfig.create(
         initialContainer: initial,
         appRoot: appRoot,
         includeDashboardTab: includeDashboardTab,
       ) {
    final sub = _container.listen<BrowserTabsState>(
      browserTabsProvider(config),
      (_, _) => notifications++,
    );
    addTearDown(sub.close);
  }

  final ProviderContainer _container;
  final BrowserTabsConfig config;

  /// State changes seen by a listener, i.e. what the UI would be told about.
  int notifications = 0;

  BrowserTabs get tabs =>
      _container.read(browserTabsProvider(config).notifier);
  BrowserTabsState get state => _container.read(browserTabsProvider(config));
  TabId get active => state.activeTabId!;
  List<TabId> get ids => state.tabs.map((tab) => tab.tabId).toList();
}

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  _Workspace workspace(
    int volId, {
    bool appRoot = false,
    bool includeDashboardTab = false,
  }) => _Workspace(
    container,
    _container(volId),
    appRoot: appRoot,
    includeDashboardTab: includeDashboardTab,
  );

  group('BrowserTabs', () {
    test('starts with one active tab on the initial container', () {
      final w = workspace(1);
      expect(w.state.tabs, hasLength(1));
      expect(w.state.hasMultiple, isFalse);
      expect(w.state.activeTab!.volId, 1);
      expect(w.active, w.state.tabs.first.tabId);
      expect(w.tabs.previousTab(), isNull);
    });

    test('tab ids are unique across workspaces', () {
      final a = workspace(1);
      final b = workspace(1);
      expect(a.active, isNot(b.active));
    });

    test('a closed tab\'s id is never handed out again', () {
      final w = workspace(1);
      final first = w.active;
      w.tabs.openTab(_container(2));
      w.tabs.closeTab(first);
      final reopened = w.tabs.openTab(_container(1))!;
      expect(reopened, isNot(first));
      expect(w.tabs.tabForKey(first), isNull);
    });

    test('two tabs on the same vault get distinct ids', () {
      final w = workspace(7);
      final id = w.tabs.openTab(_container(7), initialPath: 'docs');
      expect(id, isNotNull);
      expect(w.ids.toSet(), hasLength(2));
      expect(w.state.activeTab!.initialPath, 'docs');
    });

    test('openTab activates the new tab and remembers the previous one', () {
      final w = workspace(1);
      final first = w.active;
      final second = w.tabs.openTab(_container(2))!;
      expect(w.active, second);
      expect(w.tabs.previousTab()!.tabId, first);
    });

    test('openTab with activate:false keeps the current tab active', () {
      final w = workspace(1);
      final first = w.active;
      w.tabs.openTab(_container(2), activate: false);
      expect(w.active, first);
      expect(w.state.tabs, hasLength(2));
    });

    test('openTab refuses beyond the cap', () {
      final w = workspace(1);
      for (var i = 1; i < kMaxBrowserTabs; i++) {
        expect(w.tabs.openTab(_container(i + 1)), isNotNull);
      }
      expect(w.state.atLimit, isTrue);
      expect(w.tabs.openTab(_container(99)), isNull);
      expect(w.state.tabs, hasLength(kMaxBrowserTabs));
    });

    test('swapToPrevious flips between two tabs', () {
      final w = workspace(1);
      final a = w.active;
      final b = w.tabs.openTab(_container(2))!;
      expect(w.tabs.swapToPrevious(), isTrue);
      expect(w.active, a);
      expect(w.tabs.swapToPrevious(), isTrue);
      expect(w.active, b);
    });

    test('swapToPrevious is a no-op with a single tab', () {
      final w = workspace(1);
      expect(w.tabs.swapToPrevious(), isFalse);
    });

    test('closing the active tab returns to the previously used tab', () {
      final w = workspace(1);
      final a = w.active;
      final b = w.tabs.openTab(_container(2))!;
      w.tabs.openTab(_container(3));
      w.tabs.activate(b); // history: 1 -> 2 -> 3 -> 2
      w.tabs.activate(a); // active a, previous b
      w.tabs.closeTab(a);
      expect(w.active, b);
    });

    test('closing a background tab keeps the active tab', () {
      final w = workspace(1);
      final a = w.active;
      final b = w.tabs.openTab(_container(2))!;
      w.tabs.closeTab(a);
      expect(w.active, b);
      expect(w.state.tabs, hasLength(1));
    });

    test('closing the last tab empties the workspace', () {
      final w = workspace(1);
      w.tabs.closeTab(w.active);
      expect(w.state.tabs, isEmpty);
      expect(w.state.activeTabId, isNull);
      expect(w.state.activeTab, isNull);
    });

    test('closeByVolId removes every tab on that volume only', () {
      final w = workspace(1);
      w.tabs.openTab(_container(2));
      w.tabs.openTab(_container(1));
      w.tabs.openTab(_container(3));
      expect(w.tabs.closeByVolId(1), isTrue);
      expect(w.state.tabs.map((tab) => tab.volId), [2, 3]);
      expect(w.tabs.closeByVolId(42), isFalse);
    });

    test('closeByVolId on the active tab activates a surviving tab', () {
      final w = workspace(1);
      w.tabs.openTab(_container(2));
      w.tabs.closeByVolId(2);
      expect(w.state.activeTab!.volId, 1);
    });

    test('closeOthers keeps only the chosen tab and activates it', () {
      final w = workspace(1);
      w.tabs.openTab(_container(2));
      final keep = w.tabs.openTab(_container(3))!;
      w.tabs.closeOthers(keep);
      expect(w.state.tabs, hasLength(1));
      expect(w.active, keep);
      expect(w.tabs.previousTab(), isNull);
    });

    test('replaceActive swaps in a fresh id so no state can leak', () {
      final w = workspace(1);
      final oldId = w.active;
      w.tabs.replaceActive(_container(5), initialPath: 'x');
      expect(w.state.tabs, hasLength(1));
      expect(w.active, isNot(oldId));
      expect(w.state.activeTab!.volId, 5);
      expect(w.state.activeTab!.initialPath, 'x');
      expect(w.tabs.tabForKey(oldId), isNull);
    });

    test('moveTab reorders tabs and keeps the active tab active', () {
      final w = workspace(1);
      final a = w.active;
      final b = w.tabs.openTab(_container(2))!;
      final d = w.tabs.openTab(_container(3))!;
      w.tabs.activate(b);
      w.tabs.moveTab(0, 2); // a goes to the end
      expect(w.ids, [b, d, a]);
      expect(w.active, b);
      expect(w.state.activeIndex, 0);
    });

    test('moveTab ignores no-op and out-of-range moves', () {
      final w = workspace(1);
      w.tabs.openTab(_container(2));
      final before = w.ids;
      final seen = w.notifications;
      w.tabs.moveTab(0, 0);
      w.tabs.moveTab(-1, 1);
      w.tabs.moveTab(0, 5);
      w.tabs.moveTab(7, 0);
      expect(w.ids, before);
      expect(w.notifications, seen);
    });

    test('closeAll empties the workspace', () {
      final w = workspace(1);
      w.tabs.openTab(_container(2));
      w.tabs.closeAll();
      expect(w.state.tabs, isEmpty);
      expect(w.state.activeTabId, isNull);
    });

    test('listeners are notified on every structural change', () {
      final w = workspace(1);
      final seen = w.notifications;
      final b = w.tabs.openTab(_container(2))!;
      w.tabs.activate(w.state.tabs.first.tabId);
      w.tabs.swapToPrevious();
      w.tabs.closeTab(b);
      expect(w.notifications - seen, 4);
    });
  });

  group('tab origin', () {
    test('tabs are not opened from Home unless they say so', () {
      final w = workspace(1);
      expect(w.state.activeTab!.origin, BrowserTabOrigin.other);
      w.tabs.openTab(_container(2));
      expect(w.state.activeTab!.origin, BrowserTabOrigin.other);
    });

    test('openTab and replaceActive record where the tab came from', () {
      final w = workspace(1);
      w.tabs.openTab(_container(2), origin: BrowserTabOrigin.home);
      expect(w.state.activeTab!.origin, BrowserTabOrigin.home);

      w.tabs.replaceActive(_container(3), origin: BrowserTabOrigin.home);
      expect(w.state.activeTab!.origin, BrowserTabOrigin.home);

      w.tabs.replaceActive(_container(4));
      expect(w.state.activeTab!.origin, BrowserTabOrigin.other);
    });

    test('setOrigin updates a reused tab and keeps its id and path', () {
      final w = workspace(1);
      w.tabs.replaceActive(_container(2), initialPath: 'docs');
      final id = w.active;

      w.tabs.setOrigin(id, BrowserTabOrigin.home);
      expect(w.active, id);
      expect(w.state.activeTab!.origin, BrowserTabOrigin.home);
      expect(w.state.activeTab!.initialPath, 'docs');
      expect(w.state.activeTab!.volId, 2);

      w.tabs.setOrigin(id, BrowserTabOrigin.other);
      expect(w.state.activeTab!.origin, BrowserTabOrigin.other);
    });

    test('setOrigin to the same value is not a change', () {
      final w = workspace(1);
      final seen = w.notifications;
      w.tabs.setOrigin(w.active, BrowserTabOrigin.other);
      expect(w.notifications, seen);
    });

    test('setOrigin ignores unknown tabs and Home', () {
      final w = workspace(1, includeDashboardTab: true);
      final homeId = w.tabs.openDashboardTab();
      final seen = w.notifications;
      w.tabs.setOrigin(homeId, BrowserTabOrigin.home);
      w.tabs.setOrigin(TabId.allocate(), BrowserTabOrigin.home);
      expect(w.notifications, seen);
      expect(w.state.activeTab!.isDashboard, isTrue);
    });
  });

  group('returning Home', () {
    test('activates the open Home tab and closes the tab it left', () {
      final w = workspace(1, includeDashboardTab: true);
      final home = w.state.tabs.first.tabId;
      final folder = w.active;

      expect(w.tabs.returnToDashboardAtRoot(folder), isTrue);

      expect(w.ids, [home]);
      expect(w.active, home);
      expect(w.tabs.tabForKey(folder), isNull);
    });

    test('leaves every other tab where it was', () {
      final w = workspace(1, includeDashboardTab: true);
      final home = w.state.tabs.first.tabId;
      final first = w.active;
      final second = w.tabs.openTab(_container(2))!;
      expect(w.ids, [home, first, second]);

      expect(w.tabs.returnToDashboardAtRoot(second), isTrue);

      expect(w.ids, [home, first]);
      expect(w.active, home);
    });

    test('works when Home sits to the right of the tab', () {
      final w = workspace(1, includeDashboardTab: true);
      final home = w.state.tabs.first.tabId;
      final folder = w.active;
      w.tabs.moveTab(0, 1);
      expect(w.ids, [folder, home]);

      expect(w.tabs.returnToDashboardAtRoot(folder), isTrue);

      expect(w.ids, [home]);
      expect(w.active, home);
    });

    test('does not keep the closed tab as the previous one', () {
      final w = workspace(1, includeDashboardTab: true);
      final folder = w.active;
      expect(w.tabs.previousTab(), isNotNull);

      w.tabs.returnToDashboardAtRoot(folder);

      expect(w.tabs.previousTab(), isNull);
    });

    test('is one change for the UI, not a close followed by a switch', () {
      final w = workspace(1, includeDashboardTab: true);
      final seen = w.notifications;

      w.tabs.returnToDashboardAtRoot(w.active);

      expect(w.notifications - seen, 1);
    });

    test('ignores a tab that is not the active one', () {
      final w = workspace(1, includeDashboardTab: true);
      final home = w.state.tabs.first.tabId;
      final folder = w.active;
      final seen = w.notifications;

      expect(w.tabs.returnToDashboardAtRoot(home), isFalse);

      expect(w.ids, [home, folder]);
      expect(w.active, folder);
      expect(w.notifications, seen);
    });

    test('leaves Home alone when it is already the active tab', () {
      final w = workspace(1, includeDashboardTab: true);
      final home = w.state.tabs.first.tabId;
      w.tabs.activate(home);
      final seen = w.notifications;

      expect(w.tabs.returnToDashboardAtRoot(home), isTrue);

      expect(w.state.tabs, hasLength(2));
      expect(w.active, home);
      expect(w.notifications, seen);
    });

    test('reports false, changing nothing, when there is no Home tab', () {
      final w = workspace(1);
      final seen = w.notifications;

      expect(w.tabs.returnToDashboardAtRoot(w.active), isFalse);

      expect(w.state.tabs, hasLength(1));
      expect(w.notifications, seen);
    });
  });

  group('BrowserTabsConfig', () {
    test('is equal to itself and to nothing else', () {
      final a = BrowserTabsConfig.create(initialContainer: _container(1));
      final b = BrowserTabsConfig.create(initialContainer: _container(1));
      expect(a, equals(a));
      expect(a.hashCode, a.hashCode);
      expect(a, isNot(equals(b)));
    });

    test('is not an app root unless asked to be', () {
      expect(BrowserTabsConfig.create().appRoot, isFalse);
      expect(
        BrowserTabsConfig.create(
          initialContainer: _container(1),
          appRoot: true,
        ).appRoot,
        isTrue,
      );
    });
  });

  group('app-root workspace (decoy mode)', () {
    test('supports multiple tabs like any other workspace', () {
      final w = workspace(1, appRoot: true);
      expect(w.tabs.openTab(_container(2)), isNotNull);
      expect(w.state.tabs, hasLength(2));
      expect(w.state.tabs.every((tab) => !tab.isDashboard), isTrue);
    });

    test('can be emptied and reopened, which the shell relies on', () {
      final w = workspace(1, appRoot: true);
      expect(w.tabs.closeByVolId(1), isTrue);
      expect(w.state.tabs, isEmpty);

      final reopened = w.tabs.openTab(_container(2));
      expect(reopened, isNotNull);
      expect(w.state.tabs, hasLength(1));
      expect(w.state.activeTabId, reopened);
    });
  });
}
