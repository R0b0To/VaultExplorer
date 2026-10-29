import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/tab_swipe_gestures.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

void main() {
  group('TabSwipeGestures defaults', () {
    test('swipe between tabs, nothing on the left, the drawer on the right', () {
      const g = TabSwipeGestures();
      expect(g.swipeBetweenTabs, isTrue);
      expect(g.leftSwipe, TabLeftSwipeAction.nothing);
      expect(g.rightSwipe, TabRightSwipeAction.openDrawer);
    });

    test('a missing or unknown stored value falls back to the defaults', () {
      expect(TabSwipeGestures.fromJson(null), const TabSwipeGestures());
      expect(TabSwipeGestures.fromJson('bogus'), const TabSwipeGestures());
      expect(
        TabSwipeGestures.fromJson({'leftSwipe': 'bogus', 'rightSwipe': 7}),
        const TabSwipeGestures(),
      );
    });
  });

  group('TabSwipeGestures json', () {
    test('every combination survives a round trip', () {
      for (final swipe in [true, false]) {
        for (final left in TabLeftSwipeAction.values) {
          for (final right in TabRightSwipeAction.values) {
            final g = TabSwipeGestures.normalized(
              swipeBetweenTabs: swipe,
              leftSwipe: left,
              rightSwipe: right,
            );
            final restored = TabSwipeGestures.fromJson(
              jsonDecode(jsonEncode(g.toJson())),
            );
            expect(restored, g, reason: '$swipe $left $right');
          }
        }
      }
    });
  });

  group('TabSwipeGestures normalization', () {
    test('looping is not possible without tab swiping', () {
      final g = TabSwipeGestures.normalized(
        swipeBetweenTabs: false,
        leftSwipe: TabLeftSwipeAction.loopToFirst,
        rightSwipe: TabRightSwipeAction.loopToLast,
      );
      expect(g.leftSwipe, TabLeftSwipeAction.nothing);
      expect(g.rightSwipe, TabRightSwipeAction.nothing);
    });

    test('turning tab swiping off keeps a new tab / the drawer', () {
      final g = const TabSwipeGestures(
        leftSwipe: TabLeftSwipeAction.newTab,
      ).copyWith(swipeBetweenTabs: false);
      expect(g.leftSwipe, TabLeftSwipeAction.newTab);
      expect(g.rightSwipe, TabRightSwipeAction.openDrawer);
    });

    test('only the choices that can work are offered', () {
      const on = TabSwipeGestures();
      final off = on.copyWith(swipeBetweenTabs: false);
      expect(on.leftSwipeChoices, TabLeftSwipeAction.values);
      expect(on.rightSwipeChoices, TabRightSwipeAction.values);
      expect(off.leftSwipeChoices, [
        TabLeftSwipeAction.newTab,
        TabLeftSwipeAction.nothing,
      ]);
      expect(off.rightSwipeChoices, [
        TabRightSwipeAction.openDrawer,
        TabRightSwipeAction.nothing,
      ]);
    });

    test('a stored map is normalized when it is read', () {
      final g = TabSwipeGestures.fromJson({
        'swipeBetweenTabs': false,
        'leftSwipe': 'loopToFirst',
        'rightSwipe': 'loopToLast',
      });
      expect(g.leftSwipe, TabLeftSwipeAction.nothing);
      expect(g.rightSwipe, TabRightSwipeAction.nothing);
    });
  });

  group('TabSwipeGestures behaviour flags', () {
    test('each direction loops on its own', () {
      final forwardOnly = const TabSwipeGestures().copyWith(
        leftSwipe: TabLeftSwipeAction.loopToFirst,
      );
      expect(forwardOnly.loopsForward, isTrue);
      expect(forwardOnly.loopsBackward, isFalse);

      final backwardOnly = const TabSwipeGestures().copyWith(
        rightSwipe: TabRightSwipeAction.loopToLast,
      );
      expect(backwardOnly.loopsForward, isFalse);
      expect(backwardOnly.loopsBackward, isTrue);
    });

    test('the host only watches the ends when something there needs it', () {
      const defaults = TabSwipeGestures();
      // The drawer handles its own swipe, so the defaults need no watching.
      expect(defaults.actsPastTheEnds, isFalse);
      expect(
        defaults.copyWith(leftSwipe: TabLeftSwipeAction.newTab).actsPastTheEnds,
        isTrue,
      );
      expect(
        defaults
            .copyWith(
              leftSwipe: TabLeftSwipeAction.nothing,
              rightSwipe: TabRightSwipeAction.loopToLast,
            )
            .actsPastTheEnds,
        isTrue,
      );
      expect(
        defaults.copyWith(swipeBetweenTabs: false).actsPastTheEnds,
        isFalse,
      );
    });

    test('a left swipe anywhere offers a new tab only with tab swiping off', () {
      const on = TabSwipeGestures(leftSwipe: TabLeftSwipeAction.newTab);
      final off = on.copyWith(swipeBetweenTabs: false);
      expect(on.leftSwipeAnywhereOpensNewTab, isFalse);
      expect(off.leftSwipeAnywhereOpensNewTab, isTrue);
      expect(
        off.copyWith(leftSwipe: TabLeftSwipeAction.nothing)
            .leftSwipeAnywhereOpensNewTab,
        isFalse,
      );
    });
  });

  group('TabSwipeGestures migration from the old single setting', () {
    TabSwipeGestures fromLegacy(String? mode) =>
        TabSwipeGestures.fromJson(null, legacyMode: mode);

    test('"drawerAndNewTab" keeps the new-tab swipe it always had', () {
      expect(
        fromLegacy('drawerAndNewTab'),
        const TabSwipeGestures(leftSwipe: TabLeftSwipeAction.newTab),
      );
    });

    test('a missing value (a fresh install) gets the new defaults', () {
      expect(fromLegacy(null), const TabSwipeGestures());
    });

    test('"loop" loops in both directions', () {
      expect(
        fromLegacy('loop'),
        const TabSwipeGestures(
          leftSwipe: TabLeftSwipeAction.loopToFirst,
          rightSwipe: TabRightSwipeAction.loopToLast,
        ),
      );
    });

    test('"noEdgeActions" does nothing at either end', () {
      expect(
        fromLegacy('noEdgeActions'),
        const TabSwipeGestures(
          leftSwipe: TabLeftSwipeAction.nothing,
          rightSwipe: TabRightSwipeAction.nothing,
        ),
      );
    });

    test('"noTabSwiping" stops tab swiping but keeps both gestures anywhere', () {
      expect(
        fromLegacy('noTabSwiping'),
        const TabSwipeGestures(
          swipeBetweenTabs: false,
          leftSwipe: TabLeftSwipeAction.newTab,
        ),
      );
    });

    test('a stored map wins over the legacy value', () {
      final g = TabSwipeGestures.fromJson({
        'swipeBetweenTabs': true,
        'leftSwipe': 'nothing',
        'rightSwipe': 'openDrawer',
      }, legacyMode: 'loop');
      expect(g.leftSwipe, TabLeftSwipeAction.nothing);
      expect(g.rightSwipe, TabRightSwipeAction.openDrawer);
    });
  });

  group('AppSettings', () {
    test('an old settings file with only tabEdgeSwipe still loads', () {
      final s = AppSettings.fromJson({'tabEdgeSwipe': 'noTabSwiping'});
      expect(
        s.tabSwipeGestures,
        const TabSwipeGestures(
          swipeBetweenTabs: false,
          leftSwipe: TabLeftSwipeAction.newTab,
        ),
      );
    });

    test('the gestures survive toJson -> fromJson', () {
      final s = AppSettings(
        tabSwipeGestures: const TabSwipeGestures(
          leftSwipe: TabLeftSwipeAction.nothing,
          rightSwipe: TabRightSwipeAction.loopToLast,
        ),
      );
      expect(AppSettings.fromJson(s.toJson()).tabSwipeGestures, s.tabSwipeGestures);
    });

    test('a fresh install has the default gestures', () {
      expect(AppSettings().tabSwipeGestures, const TabSwipeGestures());
    });
  });
}
