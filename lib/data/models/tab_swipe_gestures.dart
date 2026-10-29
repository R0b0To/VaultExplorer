import 'package:flutter/foundation.dart';

/// What a left swipe does once there is no further tab to the right: on the
/// last tab, or anywhere on screen when swiping between tabs is switched off.
enum TabLeftSwipeAction {
  /// Offers a new tab.
  newTab,

  /// Wraps around to the first tab. Only possible while tabs can be swiped.
  loopToFirst,

  /// Does nothing. New tabs still come from the tab strip (default).
  nothing;

  String toJson() => name;

  static TabLeftSwipeAction fromJson(Object? value) => switch (value) {
    'newTab' => TabLeftSwipeAction.newTab,
    'loopToFirst' => TabLeftSwipeAction.loopToFirst,
    _ => TabLeftSwipeAction.nothing,
  };
}

/// What a right swipe does once there is no further tab to the left: on the
/// first tab, or anywhere on screen when swiping between tabs is switched off.
enum TabRightSwipeAction {
  /// Pulls out the side drawer from anywhere on the screen (default).
  openDrawer,

  /// Wraps around to the last tab. Only possible while tabs can be swiped.
  loopToLast,

  /// Does nothing. The drawer still opens from the left screen edge and from
  /// the menu button.
  nothing;

  String toJson() => name;

  static TabRightSwipeAction fromJson(Object? value) => switch (value) {
    'loopToLast' => TabRightSwipeAction.loopToLast,
    'nothing' => TabRightSwipeAction.nothing,
    _ => TabRightSwipeAction.openDrawer,
  };
}

/// How sideways swipes behave in the file manager's tabs, as three
/// independent choices:
///
///  * whether a swipe moves between tabs at all ([swipeBetweenTabs]);
///  * what a left swipe does where there is no next tab ([leftSwipe]);
///  * what a right swipe does where there is no previous tab ([rightSwipe]).
///
/// "Where there is no next/previous tab" is the last/first tab while swiping
/// between tabs is on. With it off, every tab acts like both the first and
/// the last one, so the two gestures work anywhere on the screen.
///
/// Looping needs tab swiping, so with swiping off it is not offered and is
/// stored as [TabLeftSwipeAction.nothing] / [TabRightSwipeAction.nothing]
/// (see [TabSwipeGestures.normalized]).
@immutable
class TabSwipeGestures {
  const TabSwipeGestures({
    this.swipeBetweenTabs = true,
    this.leftSwipe = TabLeftSwipeAction.nothing,
    this.rightSwipe = TabRightSwipeAction.openDrawer,
  });

  /// Builds a value that is always consistent: with tab swiping off, looping
  /// is not possible and becomes "do nothing".
  factory TabSwipeGestures.normalized({
    required bool swipeBetweenTabs,
    required TabLeftSwipeAction leftSwipe,
    required TabRightSwipeAction rightSwipe,
  }) {
    if (swipeBetweenTabs) {
      return TabSwipeGestures(
        swipeBetweenTabs: true,
        leftSwipe: leftSwipe,
        rightSwipe: rightSwipe,
      );
    }
    return TabSwipeGestures(
      swipeBetweenTabs: false,
      leftSwipe: leftSwipe == TabLeftSwipeAction.loopToFirst
          ? TabLeftSwipeAction.nothing
          : leftSwipe,
      rightSwipe: rightSwipe == TabRightSwipeAction.loopToLast
          ? TabRightSwipeAction.nothing
          : rightSwipe,
    );
  }

  /// Whether a horizontal swipe moves to the neighbouring tab.
  final bool swipeBetweenTabs;

  /// What a left swipe does where there is no next tab.
  final TabLeftSwipeAction leftSwipe;

  /// What a right swipe does where there is no previous tab.
  final TabRightSwipeAction rightSwipe;

  /// Swiping left past the last tab wraps around to the first.
  bool get loopsForward =>
      swipeBetweenTabs && leftSwipe == TabLeftSwipeAction.loopToFirst;

  /// Swiping right past the first tab wraps around to the last.
  bool get loopsBackward =>
      swipeBetweenTabs && rightSwipe == TabRightSwipeAction.loopToLast;

  /// With tab swiping off, a quick left swipe anywhere offers a new tab.
  bool get leftSwipeAnywhereOpensNewTab =>
      !swipeBetweenTabs && leftSwipe == TabLeftSwipeAction.newTab;

  /// Whether pulling the pager past its first or last tab can do anything
  /// that the tab host itself has to watch for (a new tab, or looping). The
  /// drawer is not one of them: the drawer handles its own swipe.
  bool get actsPastTheEnds =>
      swipeBetweenTabs &&
      (leftSwipe != TabLeftSwipeAction.nothing ||
          rightSwipe == TabRightSwipeAction.loopToLast);

  /// The left-swipe choices to offer: looping needs tab swiping.
  List<TabLeftSwipeAction> get leftSwipeChoices => swipeBetweenTabs
      ? TabLeftSwipeAction.values
      : const [TabLeftSwipeAction.newTab, TabLeftSwipeAction.nothing];

  /// The right-swipe choices to offer: looping needs tab swiping.
  List<TabRightSwipeAction> get rightSwipeChoices => swipeBetweenTabs
      ? TabRightSwipeAction.values
      : const [TabRightSwipeAction.openDrawer, TabRightSwipeAction.nothing];

  TabSwipeGestures copyWith({
    bool? swipeBetweenTabs,
    TabLeftSwipeAction? leftSwipe,
    TabRightSwipeAction? rightSwipe,
  }) => TabSwipeGestures.normalized(
    swipeBetweenTabs: swipeBetweenTabs ?? this.swipeBetweenTabs,
    leftSwipe: leftSwipe ?? this.leftSwipe,
    rightSwipe: rightSwipe ?? this.rightSwipe,
  );

  Map<String, Object> toJson() => {
    'swipeBetweenTabs': swipeBetweenTabs,
    'leftSwipe': leftSwipe.toJson(),
    'rightSwipe': rightSwipe.toJson(),
  };

  /// Reads the stored value. [legacyMode] is the name of the single
  /// `tabEdgeSwipe` mode older versions saved; it is only used when no
  /// [json] map is stored yet, so existing choices carry over unchanged.
  factory TabSwipeGestures.fromJson(Object? json, {String? legacyMode}) {
    if (json is Map) {
      return TabSwipeGestures.normalized(
        swipeBetweenTabs: json['swipeBetweenTabs'] as bool? ?? true,
        leftSwipe: TabLeftSwipeAction.fromJson(json['leftSwipe']),
        rightSwipe: TabRightSwipeAction.fromJson(json['rightSwipe']),
      );
    }
    return switch (legacyMode) {
      // Anyone who had the old default keeps the new-tab swipe they had; only
      // a fresh install gets the new default (no left swipe action).
      'drawerAndNewTab' => const TabSwipeGestures(
        leftSwipe: TabLeftSwipeAction.newTab,
      ),
      'loop' => const TabSwipeGestures(
        leftSwipe: TabLeftSwipeAction.loopToFirst,
        rightSwipe: TabRightSwipeAction.loopToLast,
      ),
      'noEdgeActions' => const TabSwipeGestures(
        leftSwipe: TabLeftSwipeAction.nothing,
        rightSwipe: TabRightSwipeAction.nothing,
      ),
      // Every tab acted like the first one: both gestures worked anywhere.
      'noTabSwiping' => const TabSwipeGestures(
        swipeBetweenTabs: false,
        leftSwipe: TabLeftSwipeAction.newTab,
      ),
      _ => const TabSwipeGestures(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is TabSwipeGestures &&
      other.swipeBetweenTabs == swipeBetweenTabs &&
      other.leftSwipe == leftSwipe &&
      other.rightSwipe == rightSwipe;

  @override
  int get hashCode => Object.hash(swipeBetweenTabs, leftSwipe, rightSwipe);
}
