import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
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
    MountedContainer? initial, {
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

    test('remembering the tab strip offset does not notify listeners', () {
      final w = workspace(1);
      w.tabs.openTab(_container(2));
      final before = w.notifications;

      w.tabs.setTabStripScrollOffset(120);
      w.tabs.setTabStripScrollOffset(240.5);

      expect(w.notifications, before);
      expect(w.tabs.tabStripScrollOffset, 240.5);
    });

    test('tab strip offset clamps negatives and ignores non-finite values', () {
      final w = workspace(1);

      w.tabs.setTabStripScrollOffset(80);
      w.tabs.setTabStripScrollOffset(double.nan);
      w.tabs.setTabStripScrollOffset(double.infinity);
      expect(w.tabs.tabStripScrollOffset, 80);

      w.tabs.setTabStripScrollOffset(-30);
      expect(w.tabs.tabStripScrollOffset, 0);
    });

    test('tab strip offset survives tab changes', () {
      final w = workspace(1);
      final second = w.tabs.openTab(_container(2))!;
      w.tabs.setTabStripScrollOffset(96);

      w.tabs.activate(w.ids.first);
      w.tabs.reorderTabs(0, 1);
      w.tabs.closeTab(second);

      expect(w.tabs.tabStripScrollOffset, 96);
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

  // Characterization of how Home behaves today, written before the Home logic
  // is touched. Every expectation was traced by hand through the commands.
  group('Home tab', () {
    List<bool> homes(_Workspace w) =>
        w.state.tabs.map((tab) => tab.isDashboard).toList();

    test('comes first, with the first folder tab focused and Home remembered', () {
      final w = workspace(1, includeDashboardTab: true);
      expect(homes(w), [true, false]);
      expect(w.state.activeTab!.volId, 1);
      expect(w.tabs.previousTab()!.isDashboard, isTrue);
    });

    test('a Home-only workspace needs no container', () {
      final w = _Workspace(container, null, includeDashboardTab: true);
      expect(homes(w), [true]);
      expect(w.state.activeTab!.isDashboard, isTrue);
    });

    test('openDashboardTab focuses the existing Home and never adds a second', () {
      final w = workspace(1, includeDashboardTab: true);
      final folder = w.active;

      final home = w.tabs.openDashboardTab();

      expect(w.active, home);
      expect(homes(w), [true, false]);
      expect(w.tabs.previousTab()!.tabId, folder);
    });

    test('openDashboardTab with room puts Home first and remembers where it was', () {
      final w = workspace(1);
      final folder = w.active;

      final home = w.tabs.openDashboardTab();

      expect(homes(w), [true, false]);
      expect(w.active, home);
      expect(w.tabs.previousTab()!.tabId, folder);
    });

    test('openDashboardTab at the cap replaces the active tab instead of adding', () {
      final w = workspace(1);
      for (var vol = 2; vol <= kMaxBrowserTabs; vol++) {
        w.tabs.openTab(_container(vol));
      }
      expect(w.state.atLimit, isTrue);

      final home = w.tabs.openDashboardTab();

      expect(w.state.tabs, hasLength(kMaxBrowserTabs));
      expect(w.state.tabs.where((tab) => tab.isDashboard), hasLength(1));
      expect(w.state.tabs.last.isDashboard, isTrue);
      expect(w.active, home);
    });

    test('openNewDashboardTab inserts Home after the active tab', () {
      final w = workspace(1);
      final first = w.active;
      w.tabs.openTab(_container(2));
      w.tabs.activate(first);

      final home = w.tabs.openNewDashboardTab();

      expect(home, isNotNull);
      expect(homes(w), [false, true, false]);
      expect(w.active, home);
    });

    test('openNewDashboardTab focuses an existing Home', () {
      final w = workspace(1, includeDashboardTab: true);
      final existing = w.state.tabs.first.tabId;

      expect(w.tabs.openNewDashboardTab(), existing);
      expect(w.active, existing);
      expect(homes(w), [true, false]);
    });

    test('openNewDashboardTab at the cap does nothing', () {
      final w = workspace(1);
      for (var vol = 2; vol <= kMaxBrowserTabs; vol++) {
        w.tabs.openTab(_container(vol));
      }
      final seen = w.notifications;

      expect(w.tabs.openNewDashboardTab(), isNull);
      expect(w.notifications, seen);
      expect(w.state.tabs.where((tab) => tab.isDashboard), isEmpty);
    });

    test('replaceActiveWithDashboard swaps the active tab for a fresh Home', () {
      final w = workspace(1);
      final first = w.active;
      w.tabs.openTab(_container(2));

      w.tabs.replaceActiveWithDashboard();

      expect(homes(w), [false, true]);
      expect(w.state.activeTab!.isDashboard, isTrue);
      expect(w.tabs.previousTab()!.tabId, first);
    });

    test('replaceActiveWithDashboard leaves only the new Home when one existed', () {
      final w = workspace(1, includeDashboardTab: true);
      final oldHome = w.state.tabs.first.tabId;

      w.tabs.replaceActiveWithDashboard();

      expect(homes(w), [true]);
      expect(w.active, isNot(oldHome));
      expect(w.tabs.previousTab(), isNull);
    });

    test('replaceActiveWithDashboard is a no-op while Home is already active', () {
      final w = workspace(1, includeDashboardTab: true);
      w.tabs.openDashboardTab();
      final seen = w.notifications;

      w.tabs.replaceActiveWithDashboard();

      expect(w.notifications, seen);
      expect(homes(w), [true, false]);
    });

    test('replaceActiveWithDashboard in an empty workspace opens Home', () {
      final w = workspace(1);
      w.tabs.closeAll();

      w.tabs.replaceActiveWithDashboard();

      expect(homes(w), [true]);
      expect(w.state.activeTab!.isDashboard, isTrue);
    });

    test('returnToDashboardAtRoot closes the tab and shows the existing Home', () {
      final w = workspace(1, includeDashboardTab: true);
      final home = w.state.tabs.first.tabId;
      final folder = w.active;

      expect(w.tabs.returnToDashboardAtRoot(folder), isTrue);

      expect(homes(w), [true]);
      expect(w.active, home);
      expect(w.tabs.previousTab(), isNull);
    });

    test('returnToDashboardAtRoot only acts for the active tab', () {
      final w = workspace(1, includeDashboardTab: true);
      final home = w.state.tabs.first.tabId;
      final seen = w.notifications;

      expect(w.tabs.returnToDashboardAtRoot(home), isFalse);
      expect(w.notifications, seen);
    });

    test('returnToDashboardAtRoot has nothing to return to without a Home', () {
      final w = workspace(1);
      final seen = w.notifications;

      expect(w.tabs.returnToDashboardAtRoot(w.active), isFalse);
      expect(w.notifications, seen);
    });

    test('returnToDashboardAtRoot on Home itself changes nothing', () {
      final w = workspace(1, includeDashboardTab: true);
      w.tabs.openDashboardTab();
      final seen = w.notifications;

      expect(w.tabs.returnToDashboardAtRoot(w.active), isTrue);
      expect(w.notifications, seen);
    });

    test('opening from Home and going back puts Home back in the same slot', () {
      // Home -> open a vault from a Home tile -> back at its root.
      final w = workspace(1, includeDashboardTab: true);
      final other = w.state.tabs.last.tabId;
      w.tabs.openDashboardTab();

      w.tabs.replaceActive(_container(2), origin: BrowserTabOrigin.home);
      expect(homes(w), [false, false], reason: 'Home gives way to the vault');
      expect(w.state.activeTab!.origin, BrowserTabOrigin.home);

      // Nothing to return to as a separate tab, so Home takes the slot back.
      expect(w.tabs.returnToDashboardAtRoot(w.active), isFalse);
      w.tabs.replaceActiveWithDashboard();

      expect(homes(w), [true, false]);
      expect(w.state.activeTab!.isDashboard, isTrue);
      expect(w.state.tabs.last.tabId, other, reason: 'other tab is untouched');
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

  group('aggregatedTabsSelectionProvider', () {
    const report = RawEntry(
      name: 'report.txt',
      isDir: false,
      sizeBytes: 100,
      modifiedSecs: 1,
    );
    const photo = RawEntry(
      name: 'photo.jpg',
      isDir: false,
      sizeBytes: 50,
      modifiedSecs: 1,
    );
    const folder = RawEntry(
      name: 'photos',
      isDir: true,
      sizeBytes: 0,
      modifiedSecs: 1,
    );

    AggregatedTabsSelection aggregate(BrowserTabsConfig config) =>
        container.read(aggregatedTabsSelectionProvider(config));

    test('sums every file tab and flags folders that are not sized yet', () {
      final w = workspace(1);
      final first = w.active;
      final second = w.tabs.openTab(_container(2))!;
      container
          .read(fileBrowserSelectionProvider(first).notifier)
          .setSelectedItems({report, folder});
      container
          .read(fileBrowserSelectionProvider(second).notifier)
          .setSelectedItems({photo});

      final selection = aggregate(w.config);

      expect(selection.hasSelection, isTrue);
      expect(selection.count, 3);
      expect(selection.bytes, 150);
      expect(selection.hasPendingFolderSizes, isTrue);
      expect(selection.itemsByTab[first], {report, folder});
      expect(selection.itemsByTab[second], {photo});
    });

    test('follows selection changes and clears with the selection', () {
      final w = workspace(1);
      final notifier = container.read(
        fileBrowserSelectionProvider(w.active).notifier,
      );

      notifier.toggleSelectItem(report);
      expect(aggregate(w.config).count, 1);
      expect(aggregate(w.config).bytes, 100);

      notifier.exitSelectionMode();
      final cleared = aggregate(w.config);
      expect(cleared.hasSelection, isFalse);
      expect(cleared.bytes, 0);
      expect(cleared.hasPendingFolderSizes, isFalse);
    });

    test('hands out read-only sets', () {
      final w = workspace(1);
      container
          .read(fileBrowserSelectionProvider(w.active).notifier)
          .setSelectedItems({report});

      final items = aggregate(w.config).itemsByTab[w.active]!;

      expect(() => items.add(photo), throwsUnsupportedError);
      expect(() => items.remove(report), throwsUnsupportedError);
    });

    test('leaves the Dashboard tab out', () {
      final w = workspace(1, includeDashboardTab: true);

      final selection = aggregate(w.config);

      expect(selection.itemsByTab.keys, [w.active]);
      expect(selection.hasSelection, isFalse);
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
