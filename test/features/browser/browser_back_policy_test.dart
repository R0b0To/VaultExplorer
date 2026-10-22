import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/models/browser_back_policy.dart';
import 'package:vaultexplorer/features/browser/models/browser_tab_origin.dart';

BrowserBackAction _back({
  bool selection = false,
  bool search = false,
  bool atRoot = true,
  BrowserTabOrigin origin = BrowserTabOrigin.other,
  bool appRoot = false,
  bool hostsHome = true,
  bool tabsEnabled = true,
}) => resolveBrowserBack(
  selectionMode: selection,
  searchActive: search,
  atRoot: atRoot,
  origin: origin,
  appRoot: appRoot,
  hostsHome: hostsHome,
  tabsEnabled: tabsEnabled,
);

void main() {
  group('inside a folder', () {
    test('selection is left first, then search, then the folder goes up', () {
      expect(
        _back(selection: true, search: true, atRoot: false),
        BrowserBackAction.exitSelection,
      );
      expect(_back(search: true, atRoot: false), BrowserBackAction.clearSearch);
      expect(_back(atRoot: false), BrowserBackAction.navigateUp);
    });

    test('selection and search come before the starting point, too', () {
      expect(
        _back(selection: true, origin: BrowserTabOrigin.home),
        BrowserBackAction.exitSelection,
      );
      expect(
        _back(search: true, origin: BrowserTabOrigin.home),
        BrowserBackAction.clearSearch,
      );
    });

    test('depth wins over origin: Home is only reached from the root', () {
      expect(
        _back(atRoot: false, origin: BrowserTabOrigin.home),
        BrowserBackAction.navigateUp,
      );
    });
  });

  group('at the root of a tab in the main shell', () {
    test('opened from Home: back returns to Home', () {
      for (final tabs in [true, false]) {
        expect(
          _back(origin: BrowserTabOrigin.home, tabsEnabled: tabs),
          BrowserBackAction.returnHome,
          reason: 'tabsEnabled=$tabs',
        );
      }
    });

    test('opened from the drawer, a folder action or a menu: back stops', () {
      for (final tabs in [true, false]) {
        expect(
          _back(origin: BrowserTabOrigin.other, tabsEnabled: tabs),
          BrowserBackAction.stay,
          reason: 'tabsEnabled=$tabs',
        );
      }
    });
  });

  group('at the root elsewhere', () {
    test('the decoy root lets the system leave', () {
      expect(_back(appRoot: true, hostsHome: false), BrowserBackAction.leave);
    });

    test('a pushed browser route closes without tabs and stays with them', () {
      expect(
        _back(hostsHome: false, tabsEnabled: false),
        BrowserBackAction.popRoute,
      );
      expect(
        _back(hostsHome: false, tabsEnabled: true),
        BrowserBackAction.stay,
      );
    });
  });

  test('the system is only let through when nothing is left to do', () {
    const bools = [false, true];
    for (final selection in bools) {
      for (final search in bools) {
        for (final atRoot in bools) {
          for (final appRoot in bools) {
            for (final hostsHome in bools) {
              for (final tabs in bools) {
                for (final origin in BrowserTabOrigin.values) {
                  final action = _back(
                    selection: selection,
                    search: search,
                    atRoot: atRoot,
                    appRoot: appRoot,
                    hostsHome: hostsHome,
                    tabsEnabled: tabs,
                    origin: origin,
                  );
                  expect(
                    action == BrowserBackAction.leave,
                    appRoot && atRoot && !selection && !search,
                    reason:
                        'sel=$selection search=$search root=$atRoot '
                        'appRoot=$appRoot home=$hostsHome tabs=$tabs '
                        'origin=$origin -> $action',
                  );
                }
              }
            }
          }
        }
      }
    }
  });
}
