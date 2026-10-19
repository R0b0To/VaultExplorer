import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_controller.dart';

MountedContainer _container(int volId, [String? name]) => MountedContainer(
  uri: 'vault://$volId',
  displayName: name ?? 'vault$volId',
  volId: volId,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 0,
  freeSpace: 0,
);

void main() {
  group('BrowserTabsController', () {
    test('starts with one active tab on the initial container', () {
      final c = BrowserTabsController(_container(1));
      expect(c.length, 1);
      expect(c.hasMultiple, isFalse);
      expect(c.activeTab!.volId, 1);
      expect(c.activeKey, c.tabs.first.key);
      expect(c.previousTab, isNull);
      c.dispose();
    });

    test('tab keys never collide with real volIds and are unique', () {
      final a = BrowserTabsController(_container(1));
      final b = BrowserTabsController(_container(1));
      final keys = {a.tabs.first.key, b.tabs.first.key};
      expect(keys.length, 2);
      for (final k in keys) {
        expect(k, greaterThanOrEqualTo(1 << 20));
      }
      a.dispose();
      b.dispose();
    });

    test('two tabs on the same vault get distinct state keys', () {
      final c = BrowserTabsController(_container(7));
      final key = c.openTab(_container(7), initialPath: 'docs');
      expect(key, isNotNull);
      expect(c.tabs.map((t) => t.key).toSet().length, 2);
      expect(c.activeTab!.initialPath, 'docs');
      c.dispose();
    });

    test('openTab activates the new tab and remembers the previous one', () {
      final c = BrowserTabsController(_container(1));
      final first = c.activeKey;
      final second = c.openTab(_container(2))!;
      expect(c.activeKey, second);
      expect(c.previousTab!.key, first);
      c.dispose();
    });

    test('openTab with activate:false keeps the current tab active', () {
      final c = BrowserTabsController(_container(1));
      final first = c.activeKey;
      c.openTab(_container(2), activate: false);
      expect(c.activeKey, first);
      expect(c.length, 2);
      c.dispose();
    });

    test('openTab refuses beyond the cap', () {
      final c = BrowserTabsController(_container(1));
      for (var i = 1; i < kMaxBrowserTabs; i++) {
        expect(c.openTab(_container(i + 1)), isNotNull);
      }
      expect(c.atLimit, isTrue);
      expect(c.openTab(_container(99)), isNull);
      expect(c.length, kMaxBrowserTabs);
      c.dispose();
    });

    test('swapToPrevious flips between two tabs', () {
      final c = BrowserTabsController(_container(1));
      final a = c.activeKey;
      final b = c.openTab(_container(2))!;
      expect(c.swapToPrevious(), isTrue);
      expect(c.activeKey, a);
      expect(c.swapToPrevious(), isTrue);
      expect(c.activeKey, b);
      c.dispose();
    });

    test('swapToPrevious is a no-op with a single tab', () {
      final c = BrowserTabsController(_container(1));
      expect(c.swapToPrevious(), isFalse);
      c.dispose();
    });

    test('closing the active tab returns to the previously used tab', () {
      final c = BrowserTabsController(_container(1));
      final a = c.activeKey;
      final b = c.openTab(_container(2))!;
      c.openTab(_container(3));
      c.activate(b); // history: 1 -> 2 -> 3 -> 2
      c.activate(a); // active a, previous b
      c.closeTab(a);
      expect(c.activeKey, b);
      c.dispose();
    });

    test('closing a background tab keeps the active tab', () {
      final c = BrowserTabsController(_container(1));
      final a = c.activeKey;
      final b = c.openTab(_container(2))!;
      c.closeTab(a);
      expect(c.activeKey, b);
      expect(c.length, 1);
      c.dispose();
    });

    test('closing the last tab empties the controller', () {
      final c = BrowserTabsController(_container(1));
      c.closeTab(c.activeKey);
      expect(c.isEmpty, isTrue);
      expect(c.activeKey, -1);
      expect(c.activeTab, isNull);
      c.dispose();
    });

    test('closeByVolId removes every tab on that volume only', () {
      final c = BrowserTabsController(_container(1));
      c.openTab(_container(2));
      c.openTab(_container(1));
      c.openTab(_container(3));
      expect(c.closeByVolId(1), isTrue);
      expect(c.tabs.map((t) => t.volId), [2, 3]);
      expect(c.closeByVolId(42), isFalse);
      c.dispose();
    });

    test('closeByVolId on the active tab activates a surviving tab', () {
      final c = BrowserTabsController(_container(1));
      c.openTab(_container(2));
      c.closeByVolId(2);
      expect(c.activeTab!.volId, 1);
      c.dispose();
    });

    test('closeOthers keeps only the chosen tab and activates it', () {
      final c = BrowserTabsController(_container(1));
      c.openTab(_container(2));
      final keep = c.openTab(_container(3))!;
      c.closeOthers(keep);
      expect(c.length, 1);
      expect(c.activeKey, keep);
      expect(c.previousTab, isNull);
      c.dispose();
    });

    test('replaceActive swaps in a fresh key so no state can leak', () {
      final c = BrowserTabsController(_container(1));
      final oldKey = c.activeKey;
      c.replaceActive(_container(5), initialPath: 'x');
      expect(c.length, 1);
      expect(c.activeKey, isNot(oldKey));
      expect(c.activeTab!.volId, 5);
      expect(c.activeTab!.initialPath, 'x');
      expect(c.tabForKey(oldKey), isNull);
      c.dispose();
    });

    test('paste request is delivered once, only to the requested tab', () {
      final c = BrowserTabsController(_container(1));
      final a = c.activeKey;
      final b = c.openTab(_container(2))!;
      c.requestPaste(b);
      expect(c.consumePasteRequest(a), isFalse);
      expect(c.consumePasteRequest(b), isTrue);
      expect(c.consumePasteRequest(b), isFalse);
      c.dispose();
    });

    test('paste request is dropped when its tab closes', () {
      final c = BrowserTabsController(_container(1));
      final b = c.openTab(_container(2))!;
      c.requestPaste(b);
      c.closeTab(b);
      expect(c.consumePasteRequest(b), isFalse);
      c.dispose();
    });

    test('listeners are notified on every structural change', () {
      final c = BrowserTabsController(_container(1));
      var n = 0;
      c.addListener(() => n++);
      final b = c.openTab(_container(2))!;
      c.activate(c.tabs.first.key);
      c.swapToPrevious();
      c.closeTab(b);
      expect(n, 4);
      c.dispose();
    });
  });
}
