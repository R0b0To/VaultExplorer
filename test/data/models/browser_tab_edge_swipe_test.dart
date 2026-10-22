import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/browser_tab_edge_swipe.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  group('BrowserTabEdgeSwipe', () {
    test('every mode survives a round trip through json', () {
      for (final mode in BrowserTabEdgeSwipe.values) {
        expect(BrowserTabEdgeSwipe.fromJson(mode.toJson()), mode);
      }
    });

    test('a missing or unknown value falls back to the default', () {
      expect(BrowserTabEdgeSwipe.fromJson(null), BrowserTabEdgeSwipe.drawerAndNewTab);
      expect(BrowserTabEdgeSwipe.fromJson('bogus'), BrowserTabEdgeSwipe.drawerAndNewTab);
    });

    test('only the no-tab-swiping mode stops swipes changing tabs', () {
      expect(
        BrowserTabEdgeSwipe.values.where((mode) => !mode.swipesBetweenTabs),
        [BrowserTabEdgeSwipe.noTabSwiping],
      );
    });

    test('only the first two modes act on the first and last tab', () {
      expect(
        BrowserTabEdgeSwipe.values.where((mode) => mode.hasEdgeActions),
        [BrowserTabEdgeSwipe.drawerAndNewTab, BrowserTabEdgeSwipe.loop],
      );
      expect(
        BrowserTabEdgeSwipe.values.where((mode) => mode.loops),
        [BrowserTabEdgeSwipe.loop],
      );
    });

    test('every mode has its own label and description', () {
      final l10n = AppLocalizationsEn();
      final labels = {
        for (final mode in BrowserTabEdgeSwipe.values)
          mode.getLocalizedLabel(l10n),
      };
      final descriptions = {
        for (final mode in BrowserTabEdgeSwipe.values)
          mode.getLocalizedDescription(l10n),
      };

      expect(labels.length, BrowserTabEdgeSwipe.values.length);
      expect(descriptions.length, BrowserTabEdgeSwipe.values.length);
      expect(labels.every((text) => text.trim().isNotEmpty), isTrue);
    });
  });
}
