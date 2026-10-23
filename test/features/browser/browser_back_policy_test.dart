import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/models/browser_back_policy.dart';

BrowserBackAction _back({
  bool selection = false,
  bool search = false,
  bool atRoot = true,
  bool appRoot = false,
  bool hostsHome = true,
  bool tabsEnabled = true,
}) => resolveBrowserBack(
  selectionMode: selection,
  searchActive: search,
  atRoot: atRoot,
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

    test('folder depth wins: Home is only reached from the root', () {
      expect(_back(atRoot: false), BrowserBackAction.navigateUp);
    });
  });

  group('at the root of a tab in the main shell', () {
    test('storage root: back returns to Home', () {
      for (final tabs in [true, false]) {
        expect(
          _back(tabsEnabled: tabs),
          BrowserBackAction.returnHome,
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
                final action = _back(
                  selection: selection,
                  search: search,
                  atRoot: atRoot,
                  appRoot: appRoot,
                  hostsHome: hostsHome,
                  tabsEnabled: tabs,
                );
                expect(
                  action == BrowserBackAction.leave,
                  appRoot && atRoot && !selection && !search,
                  reason:
                      'sel=$selection search=$search root=$atRoot '
                      'appRoot=$appRoot home=$hostsHome tabs=$tabs '
                      '-> $action',
                );
              }
            }
          }
        }
      }
    }
  });
}
