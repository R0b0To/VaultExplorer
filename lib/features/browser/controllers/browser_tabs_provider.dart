import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
import 'package:vaultexplorer/features/browser/models/browser_tab_origin.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';

part 'browser_tabs_provider.g.dart';

/// Hard cap on all simultaneously open browser tabs, including Dashboard.
///
/// Dual pane splits this budget between two groups, so it is one more than a
/// single strip needs. Each open tab keeps its listing in memory, which is why
/// the cap is raised by one rather than removed.
const int kMaxBrowserTabs = 6;

/// One of the two tab groups of a workspace. In the landscape dual-pane layout
/// each group owns a pane; everywhere else all groups share one strip, with
/// [primary] first. The panes follow the layout direction, so [primary] is the
/// start side (left in left-to-right locales).
enum TabPane {
  primary,
  secondary;

  TabPane get other => this == TabPane.primary ? secondary : primary;
}

sealed class BrowserTabKind {
  const BrowserTabKind();
}

/// The workspace's Dashboard page. The workspace keeps at most one instance
/// because its view state is shared, but the tab can be closed and reopened.
final class HomeTab extends BrowserTabKind {
  const HomeTab();
}

/// A folder location in a mounted vault or storage container.
@immutable
final class FolderTab extends BrowserTabKind {
  const FolderTab({
    required this.container,
    this.initialPath,
    this.origin = BrowserTabOrigin.other,
  });

  final MountedContainer container;
  final String? initialPath;
  final BrowserTabOrigin origin;
}

/// A single location in a browser workspace.
@immutable
class BrowserTabState {
  final TabId tabId;
  final BrowserTabKind kind;

  /// The group this tab belongs to.
  final TabPane pane;

  const BrowserTabState.home({required this.tabId, this.pane = TabPane.primary})
    : kind = const HomeTab();

  BrowserTabState.folder({
    required this.tabId,
    required MountedContainer container,
    String? initialPath,
    BrowserTabOrigin origin = BrowserTabOrigin.other,
    this.pane = TabPane.primary,
  }) : kind = FolderTab(
         container: container,
         initialPath: initialPath,
         origin: origin,
       );

  const BrowserTabState._({
    required this.tabId,
    required this.kind,
    required this.pane,
  });

  /// The same tab (same id, same location) in [pane].
  BrowserTabState inPane(TabPane pane) => this.pane == pane
      ? this
      : BrowserTabState._(tabId: tabId, kind: kind, pane: pane);

  bool get isDashboard => kind is HomeTab;
  MountedContainer? get container => switch (kind) {
    HomeTab() => null,
    FolderTab(:final container) => container,
  };
  String? get initialPath => switch (kind) {
    HomeTab() => null,
    FolderTab(:final initialPath) => initialPath,
  };
  int? get volId => container?.volId;

  /// Where this tab was opened from. Home tabs have no origin of their own.
  BrowserTabOrigin get origin => switch (kind) {
    HomeTab() => BrowserTabOrigin.other,
    FolderTab(:final origin) => origin,
  };
}

/// Identifies one workspace: each hosted browser route (or the decoy root)
/// owns an auto-disposed [BrowserTabs] engine keyed by this value, which also
/// carries that route's initial data and policy. Equality is by [sessionId],
/// so the same workspace always resolves to the same engine.
@immutable
class BrowserTabsConfig {
  static int _nextSessionId = 1;

  final int sessionId;
  final MountedContainer? initialContainer;
  final String? initialPath;
  final bool includeDashboardTab;

  /// True when this workspace is the app's root surface (decoy mode): no route
  /// lies beneath it. Closing the last tab reopens the primary location instead
  /// of leaving, and back at the root of the visible tab leaves the app.
  final bool appRoot;

  const BrowserTabsConfig._({
    required this.sessionId,
    required this.initialContainer,
    this.initialPath,
    this.includeDashboardTab = false,
    this.appRoot = false,
  });

  factory BrowserTabsConfig.create({
    MountedContainer? initialContainer,
    String? initialPath,
    bool includeDashboardTab = false,
    bool appRoot = false,
  }) => BrowserTabsConfig._(
    sessionId: _nextSessionId++,
    initialContainer: initialContainer,
    initialPath: initialPath,
    includeDashboardTab: includeDashboardTab,
    appRoot: appRoot,
  );

  @override
  bool operator ==(Object other) =>
      other is BrowserTabsConfig && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

@immutable
class BrowserTabsState {
  /// Every open tab, ordered primary group first, then secondary group.
  final List<BrowserTabState> tabs;

  /// The tab that has focus: the shown tab of the focused pane. Everything that
  /// works on "the current tab" (app bar, back, clipboard, ...) follows this.
  final TabId? activeTabId;
  final TabId? previousTabId;

  /// The tab shown in the pane that does not have focus. Only meaningful while
  /// both panes hold tabs; read it through [activeTabIdOfPane].
  final TabId? unfocusedPaneTabId;

  /// Whether the layout can currently show two panes side by side (landscape,
  /// wide enough, dual pane enabled). Mirrored here by the shell so the strip
  /// and item actions can react to it; the engine uses it to decide where new
  /// tabs go.
  final bool splitAvailable;

  const BrowserTabsState({
    required this.tabs,
    required this.activeTabId,
    this.previousTabId,
    this.unfocusedPaneTabId,
    this.splitAvailable = false,
  });

  int get activeIndex {
    if (activeTabId == null) return -1;
    final index = tabs.indexWhere((tab) => tab.tabId == activeTabId);
    return index;
  }

  BrowserTabState? get activeTab {
    final index = activeIndex;
    return index < 0 ? null : tabs[index];
  }

  bool get hasMultiple => tabs.length > 1;
  int get fileTabCount => tabs.where((tab) => !tab.isDashboard).length;
  bool get atLimit => tabs.length >= kMaxBrowserTabs;

  /// The pane that has focus (the active tab's pane).
  TabPane? get focusedPane => activeTab?.pane;

  List<BrowserTabState> tabsInPane(TabPane pane) =>
      tabs.where((tab) => tab.pane == pane).toList(growable: false);

  int paneTabCount(TabPane pane) =>
      tabs.where((tab) => tab.pane == pane).length;

  /// Both panes hold at least one tab, so a dual-pane layout has two things to
  /// show.
  bool get hasBothPanes =>
      paneTabCount(TabPane.primary) > 0 && paneTabCount(TabPane.secondary) > 0;

  /// Dual pane is on screen: the layout can split and both panes are in use.
  bool get isSplit => splitAvailable && hasBothPanes;

  /// The tab [pane] currently shows. For the focused pane that is
  /// [activeTabId]; for the other pane it is the last tab shown there, falling
  /// back to its first tab if that one is gone.
  TabId? activeTabIdOfPane(TabPane pane) {
    final active = activeTab;
    if (active == null) return null;
    if (active.pane == pane) return active.tabId;
    final remembered = unfocusedPaneTabId;
    if (remembered != null) {
      for (final tab in tabs) {
        if (tab.tabId == remembered && tab.pane == pane) return remembered;
      }
    }
    for (final tab in tabs) {
      if (tab.pane == pane) return tab.tabId;
    }
    return null;
  }

  BrowserTabsState copyWith({
    List<BrowserTabState>? tabs,
    TabId? activeTabId,
    TabId? previousTabId,
    bool clearPreviousTabId = false,
    TabId? unfocusedPaneTabId,
    bool clearUnfocusedPaneTabId = false,
    bool? splitAvailable,
  }) => BrowserTabsState(
    tabs: tabs ?? this.tabs,
    activeTabId: activeTabId ?? this.activeTabId,
    previousTabId: clearPreviousTabId
        ? null
        : (previousTabId ?? this.previousTabId),
    unfocusedPaneTabId: clearUnfocusedPaneTabId
        ? null
        : (unfocusedPaneTabId ?? this.unfocusedPaneTabId),
    splitAvailable: splitAvailable ?? this.splitAvailable,
  );
}

@riverpod
class BrowserTabs extends _$BrowserTabs {
  @override
  BrowserTabsState build(BrowserTabsConfig config) {
    final tabs = <BrowserTabState>[];
    BrowserTabState? dashboard;
    if (config.includeDashboardTab) {
      dashboard = BrowserTabState.home(tabId: TabId.allocate());
      tabs.add(dashboard);
    }
    if (config.initialContainer == null && dashboard == null) {
      throw ArgumentError(
        'A browser tab engine needs an initial location or Dashboard tab.',
      );
    }
    final initialContainer = config.initialContainer;
    if (initialContainer != null) {
      final firstFileTab = BrowserTabState.folder(
        tabId: TabId.allocate(),
        container: initialContainer,
        initialPath: config.initialPath,
      );
      tabs.add(firstFileTab);
      return BrowserTabsState(
        tabs: List.unmodifiable(tabs),
        activeTabId: firstFileTab.tabId,
        previousTabId: dashboard?.tabId,
      );
    }
    return BrowserTabsState(
      tabs: List.unmodifiable(tabs),
      activeTabId: dashboard!.tabId,
    );
  }

  /// Whether the shell can currently lay out two panes. Kept outside [state]
  /// so a change can be applied together with the tab moves it causes; it is
  /// mirrored into [BrowserTabsState.splitAvailable] for readers.
  bool _splitAvailable = false;

  /// Where each tab strip was last scrolled to, so a rebuilt strip can come
  /// back to the same place.
  ///
  /// Deliberately not part of [state]: it changes on every frame the strip
  /// scrolls (including the animation that brings a newly active tab into
  /// view), nothing renders from it, and publishing it through [state] woke
  /// every listener of the workspace - the shell, the chrome hub, each mounted
  /// viewport and the Dashboard - once per frame.
  final Map<TabPane, double> _tabStripScrollOffsets = {};

  double get tabStripScrollOffset => tabStripScrollOffsetOf(TabPane.primary);

  double tabStripScrollOffsetOf(TabPane pane) =>
      _tabStripScrollOffsets[pane] ?? 0;

  void setTabStripScrollOffset(
    double value, {
    TabPane pane = TabPane.primary,
  }) {
    if (!value.isFinite) return;
    _tabStripScrollOffsets[pane] = value < 0 ? 0.0 : value;
  }

  // -- Invariants -----------------------------------------------------------

  /// Every state change goes through here so the pane rules hold no matter
  /// which operation produced it:
  ///
  /// * [BrowserTabsState.tabs] is ordered primary group, then secondary group.
  /// * A pane never exists without its partner: when the primary group empties
  ///   the secondary tabs collapse into it, so "one pane" is always "all tabs
  ///   in primary".
  /// * [BrowserTabsState.unfocusedPaneTabId] points at a tab of the pane that
  ///   does not have focus, or at nothing.
  void _commit(BrowserTabsState next) => state = _normalized(next);

  BrowserTabsState _normalized(BrowserTabsState s) {
    var tabs = s.tabs;
    var unfocused = s.unfocusedPaneTabId;
    if (tabs.isNotEmpty) {
      final primary = <BrowserTabState>[];
      final secondary = <BrowserTabState>[];
      for (final tab in tabs) {
        (tab.pane == TabPane.primary ? primary : secondary).add(tab);
      }
      if (primary.isEmpty) {
        tabs = List.unmodifiable([
          for (final tab in secondary) tab.inPane(TabPane.primary),
        ]);
      } else if (secondary.isNotEmpty) {
        final ordered = [...primary, ...secondary];
        for (var i = 0; i < ordered.length; i++) {
          if (ordered[i].tabId != tabs[i].tabId) {
            tabs = List.unmodifiable(ordered);
            break;
          }
        }
      }
    }
    if (unfocused != null) {
      final active = tabs.where((tab) => tab.tabId == s.activeTabId);
      final pointee = tabs.where((tab) => tab.tabId == unfocused);
      final valid =
          active.isNotEmpty &&
          pointee.isNotEmpty &&
          pointee.first.pane != active.first.pane;
      if (!valid) unfocused = null;
    }
    if (identical(tabs, s.tabs) &&
        unfocused == s.unfocusedPaneTabId &&
        s.splitAvailable == _splitAvailable) {
      return s;
    }
    return BrowserTabsState(
      tabs: tabs,
      activeTabId: s.activeTabId,
      previousTabId: s.previousTabId,
      unfocusedPaneTabId: unfocused,
      splitAvailable: _splitAvailable,
    );
  }

  /// Where a new tab for [pane] goes: right after [after] when that tab is in
  /// the pane, otherwise at the end of the pane's group.
  int _insertionIndex(List<BrowserTabState> tabs, TabPane pane, TabId? after) {
    if (after != null) {
      final index = tabs.indexWhere(
        (tab) => tab.tabId == after && tab.pane == pane,
      );
      if (index >= 0) return index + 1;
    }
    final last = tabs.lastIndexWhere((tab) => tab.pane == pane);
    if (last >= 0) return last + 1;
    return pane == TabPane.primary ? 0 : tabs.length;
  }

  int _groupStart(List<BrowserTabState> tabs, TabPane pane) {
    final first = tabs.indexWhere((tab) => tab.pane == pane);
    if (first >= 0) return first;
    return pane == TabPane.primary ? 0 : tabs.length;
  }

  // -- Split layout ---------------------------------------------------------

  /// Tells the engine whether the layout can show two panes. Becoming
  /// available with every tab in one pane splits the workspace: the tab that
  /// was in use before the current one moves to the second pane.
  void setSplitAvailable(bool available) {
    if (_splitAvailable == available) return;
    _splitAvailable = available;
    var next = state.copyWith(splitAvailable: available);
    if (available) next = _autoSplit(next);
    _commit(next);
  }

  BrowserTabsState _autoSplit(BrowserTabsState s) {
    if (s.tabs.length < 2 || s.hasBothPanes) return s;
    final active = s.activeTab;
    if (active == null) return s;
    final previousId = s.previousTabId;
    BrowserTabState? pick;
    if (previousId != null && previousId != active.tabId) {
      pick = s.tabs.where((tab) => tab.tabId == previousId).firstOrNull;
    }
    if (pick == null) {
      final index = s.activeIndex;
      pick = s.tabs[index + 1 < s.tabs.length ? index + 1 : index - 1];
    }
    final target = active.pane.other;
    final pickedId = pick.tabId;
    return s.copyWith(
      tabs: List.unmodifiable([
        for (final tab in s.tabs)
          tab.tabId == pickedId ? tab.inPane(target) : tab,
      ]),
      unfocusedPaneTabId: pickedId,
    );
  }

  /// Gives focus to [pane], showing whatever it showed last.
  void focusPane(TabPane pane) {
    final id = state.activeTabIdOfPane(pane);
    if (id != null) activate(id);
  }

  /// Moves a tab to [pane]. The tab is shown there and takes focus; the pane
  /// it left keeps its own last shown tab (or the tab next to it).
  void moveToPane(TabId tabId, TabPane pane) {
    final tab = tabForKey(tabId);
    if (tab == null || tab.pane == pane) return;
    final from = tab.pane;
    final oldGroup = state.tabsInPane(from);
    var shownInFrom = state.activeTabIdOfPane(from);
    if (shownInFrom == tabId) {
      final index = oldGroup.indexWhere((entry) => entry.tabId == tabId);
      final rest = oldGroup.where((entry) => entry.tabId != tabId).toList();
      shownInFrom = rest.isEmpty
          ? null
          : rest[index < rest.length ? index : rest.length - 1].tabId;
    }
    _commit(
      BrowserTabsState(
        tabs: List.unmodifiable([
          for (final entry in state.tabs)
            entry.tabId == tabId ? entry.inPane(pane) : entry,
        ]),
        activeTabId: tabId,
        previousTabId: state.activeTabId != tabId
            ? state.activeTabId
            : state.previousTabId,
        unfocusedPaneTabId: shownInFrom,
      ),
    );
  }

  /// Opens [container] as a new tab in the pane that does not have focus and
  /// shows it there. With [focus] the new pane takes focus as well, as a new
  /// tab normally does.
  TabId? openInOtherPane(
    MountedContainer container, {
    String? initialPath,
    BrowserTabOrigin origin = BrowserTabOrigin.other,
    bool focus = true,
  }) {
    if (state.tabs.isEmpty) {
      return openTab(container, initialPath: initialPath, origin: origin);
    }
    if (state.atLimit) return null;
    final target = (state.focusedPane ?? TabPane.primary).other;
    final tab = BrowserTabState.folder(
      tabId: TabId.allocate(),
      container: container,
      initialPath: initialPath,
      origin: origin,
      pane: target,
    );
    final tabs = [...state.tabs];
    tabs.insert(
      _insertionIndex(tabs, target, state.activeTabIdOfPane(target)),
      tab,
    );
    final current = state.activeTabId;
    _commit(
      state.copyWith(
        tabs: List.unmodifiable(tabs),
        activeTabId: focus ? tab.tabId : current,
        previousTabId: focus ? current : state.previousTabId,
        unfocusedPaneTabId: focus ? current : tab.tabId,
      ),
    );
    return tab.tabId;
  }

  // -- Opening --------------------------------------------------------------

  /// New tabs join the focused pane. While the layout can split but everything
  /// is still in one pane, they start the second pane instead.
  TabPane _paneForNewTab() {
    final focused = state.focusedPane ?? TabPane.primary;
    if (state.splitAvailable && state.tabs.isNotEmpty && !state.hasBothPanes) {
      return focused.other;
    }
    return focused;
  }

  TabId? openTab(
    MountedContainer container, {
    String? initialPath,
    bool activate = true,
    BrowserTabOrigin origin = BrowserTabOrigin.other,
    TabPane? pane,
  }) {
    if (state.atLimit) return null;
    final target = pane ?? _paneForNewTab();
    final tab = BrowserTabState.folder(
      tabId: TabId.allocate(),
      container: container,
      initialPath: initialPath,
      origin: origin,
      pane: target,
    );
    final tabs = [...state.tabs];
    tabs.insert(
      tabs.isEmpty
          ? 0
          : _insertionIndex(tabs, target, state.activeTabIdOfPane(target)),
      tab,
    );
    final current = state.activeTab;
    // The pane being left keeps showing the tab that was active in it.
    final leftBehind = activate && current != null && current.pane != target
        ? current.tabId
        : null;
    _commit(
      state.copyWith(
        tabs: List.unmodifiable(tabs),
        previousTabId: activate ? state.activeTabId : state.previousTabId,
        activeTabId: activate ? tab.tabId : state.activeTabId,
        unfocusedPaneTabId: leftBehind,
      ),
    );
    return tab.tabId;
  }

  TabId openDashboardTab() {
    final existing = state.tabs.where((tab) => tab.isDashboard).firstOrNull;
    if (existing != null) {
      _activateSingleDashboard(existing);
      return existing.tabId;
    }
    if (state.atLimit) {
      replaceActiveWithDashboard();
      return state.activeTabId ?? state.tabs.first.tabId;
    }
    final pane = state.focusedPane ?? TabPane.primary;
    final tab = BrowserTabState.home(tabId: TabId.allocate(), pane: pane);
    final tabs = [...state.tabs];
    tabs.insert(_groupStart(tabs, pane), tab);
    _commit(
      state.copyWith(
        tabs: List.unmodifiable(tabs),
        previousTabId: state.activeTabId,
        activeTabId: tab.tabId,
      ),
    );
    return tab.tabId;
  }

  /// Creates a Dashboard tab if none exists, otherwise activates the existing
  /// one. Keeping Dashboard singular avoids mounting its shared view state in
  /// multiple PageView children at once.
  TabId? openNewDashboardTab() {
    final existing = state.tabs.where((tab) => tab.isDashboard).firstOrNull;
    if (existing != null) {
      _activateSingleDashboard(existing);
      return existing.tabId;
    }
    if (state.atLimit) return null;
    final tab = BrowserTabState.home(
      tabId: TabId.allocate(),
      pane: state.focusedPane ?? TabPane.primary,
    );
    final tabs = [...state.tabs];
    tabs.insert(tabs.isEmpty ? 0 : state.activeIndex + 1, tab);
    _commit(
      state.copyWith(
        tabs: List.unmodifiable(tabs),
        previousTabId: state.activeTabId,
        activeTabId: tab.tabId,
      ),
    );
    return tab.tabId;
  }

  void _activateSingleDashboard(BrowserTabState dashboard) {
    final duplicateIds = state.tabs
        .where((tab) => tab.isDashboard && tab.tabId != dashboard.tabId)
        .map((tab) => tab.tabId)
        .toSet();
    if (duplicateIds.isEmpty) {
      activate(dashboard.tabId);
      return;
    }

    final previousCandidate = state.activeTabId == dashboard.tabId
        ? state.previousTabId
        : state.activeTabId;
    final previousTabId =
        previousCandidate != null &&
            previousCandidate != dashboard.tabId &&
            !duplicateIds.contains(previousCandidate)
        ? previousCandidate
        : null;
    final current = state.activeTab;
    final leftBehind =
        current != null &&
            current.pane != dashboard.pane &&
            !duplicateIds.contains(current.tabId)
        ? current.tabId
        : null;
    _commit(
      BrowserTabsState(
        tabs: List.unmodifiable(
          state.tabs.where((tab) => !duplicateIds.contains(tab.tabId)),
        ),
        activeTabId: dashboard.tabId,
        previousTabId: previousTabId,
        unfocusedPaneTabId: leftBehind ?? state.unfocusedPaneTabId,
      ),
    );
  }

  void replaceActive(
    MountedContainer container, {
    String? initialPath,
    BrowserTabOrigin origin = BrowserTabOrigin.other,
  }) {
    if (state.tabs.isEmpty || state.activeIndex < 0) return;
    final tabs = [...state.tabs];
    final index = state.activeIndex;
    final oldId = tabs[index].tabId;
    final replacement = BrowserTabState.folder(
      tabId: TabId.allocate(),
      container: container,
      initialPath: initialPath,
      origin: origin,
      pane: tabs[index].pane,
    );
    tabs[index] = replacement;
    _commit(
      state.copyWith(
        tabs: List.unmodifiable(tabs),
        activeTabId: replacement.tabId,
        clearPreviousTabId: state.previousTabId == oldId,
      ),
    );
  }

  /// Records where a folder tab was (re)opened from, for tabs that are reused
  /// rather than recreated. The latest open wins.
  void setOrigin(TabId tabId, BrowserTabOrigin origin) {
    final index = state.tabs.indexWhere((tab) => tab.tabId == tabId);
    if (index < 0) return;
    final tab = state.tabs[index];
    final container = tab.container;
    if (container == null || tab.origin == origin) return;
    final tabs = [...state.tabs];
    tabs[index] = BrowserTabState.folder(
      tabId: tab.tabId,
      container: container,
      initialPath: tab.initialPath,
      origin: origin,
      pane: tab.pane,
    );
    state = state.copyWith(tabs: List.unmodifiable(tabs));
  }

  /// Back from the root of [tabId] to the Home tab that is already open.
  ///
  /// The tab being left is closed, so going Home never leaves the location the
  /// person just backed out of open behind it. Returns false, changing
  /// nothing, when [tabId] is not the active tab or there is no Home tab to
  /// return to; callers then use [replaceActiveWithDashboard], which turns the
  /// active tab into Home in place and so closes it the same way.
  ///
  /// When Home sits in the other pane, focus stays in the pane being left: the
  /// tab closes like any other and its pane shows the next tab (or collapses
  /// into the Home pane if it was the last one).
  bool returnToDashboardAtRoot(TabId tabId) {
    if (tabId != state.activeTabId) return false;
    final home = state.tabs.where((tab) => tab.isDashboard).firstOrNull;
    if (home == null) return false;
    // Already on Home: nothing to leave behind.
    if (home.tabId == tabId) return true;
    if (home.pane != state.activeTab?.pane) {
      closeTab(tabId);
      return true;
    }
    final tabs = state.tabs.where((tab) => tab.tabId != tabId).toList();
    _commit(
      state.copyWith(
        tabs: List.unmodifiable(tabs),
        activeTabId: home.tabId,
        // The tab that was focused before is the one just closed.
        clearPreviousTabId: true,
      ),
    );
    return true;
  }

  void replaceActiveWithDashboard() {
    final activeTab = state.activeTab;
    if (activeTab == null) {
      if (state.tabs.isEmpty) openDashboardTab();
      return;
    }
    if (activeTab.isDashboard) {
      _activateSingleDashboard(activeTab);
      return;
    }

    final removedDashboardIds = state.tabs
        .where((tab) => tab.isDashboard)
        .map((tab) => tab.tabId)
        .toSet();
    final tabs = state.tabs.where((tab) => !tab.isDashboard).toList();
    final activeIndex = tabs.indexWhere((tab) => tab.tabId == activeTab.tabId);
    if (activeIndex < 0) return;
    final dashboard = BrowserTabState.home(
      tabId: TabId.allocate(),
      pane: activeTab.pane,
    );
    tabs[activeIndex] = dashboard;
    _commit(
      state.copyWith(
        tabs: List.unmodifiable(tabs),
        activeTabId: dashboard.tabId,
        clearPreviousTabId:
            state.previousTabId == activeTab.tabId ||
            removedDashboardIds.contains(state.previousTabId),
      ),
    );
  }

  // -- Switching ------------------------------------------------------------

  /// Shows [tabId] in its own pane and gives that pane focus. The other pane
  /// keeps showing what it showed.
  void activate(TabId tabId) {
    if (tabId == state.activeTabId) return;
    final target = tabForKey(tabId);
    if (target == null) return;
    final current = state.activeTab;
    _commit(
      state.copyWith(
        activeTabId: tabId,
        previousTabId: state.activeTabId,
        // Leaving a pane leaves its tab on show there.
        unfocusedPaneTabId: current != null && current.pane != target.pane
            ? current.tabId
            : null,
      ),
    );
  }

  bool swapToPrevious() {
    final previous = previousTab();
    if (previous != null) {
      activate(previous.tabId);
      return true;
    }
    if (state.tabs.length < 2 || state.activeIndex < 0) return false;
    final index = state.activeIndex;
    activate(state.tabs[index == 0 ? 1 : index - 1].tabId);
    return true;
  }

  // -- Closing --------------------------------------------------------------

  void closeTab(TabId tabId) {
    final index = state.tabs.indexWhere((tab) => tab.tabId == tabId);
    if (index < 0) return;
    _removeAt(index);
  }

  /// Closes every other tab of [tabId]'s pane; the other pane is untouched.
  void closeOthers(TabId tabId) {
    final keep = tabForKey(tabId);
    if (keep == null) return;
    final removed = state.tabs
        .where((tab) => tab.pane == keep.pane && tab.tabId != tabId)
        .map((tab) => tab.tabId)
        .toSet();
    if (removed.isEmpty) return;
    _closeSet(removed, anchor: tabId);
  }

  void closeToLeft(TabId tabId) => _closeOnSide(tabId, closeLeft: true);
  void closeToRight(TabId tabId) => _closeOnSide(tabId, closeLeft: false);

  /// Sides are within [tabId]'s pane: that is the strip the person is looking
  /// at when they ask.
  void _closeOnSide(TabId tabId, {required bool closeLeft}) {
    final anchor = tabForKey(tabId);
    if (anchor == null) return;
    final group = state.tabsInPane(anchor.pane);
    final index = group.indexWhere((tab) => tab.tabId == tabId);
    if (index < 0) return;
    final removed = (closeLeft ? group.take(index) : group.skip(index + 1))
        .map((tab) => tab.tabId)
        .toSet();
    if (removed.isEmpty) return;
    _closeSet(removed, anchor: tabId);
  }

  /// Removes [removed] (all in one pane, never that pane's last tab). If the
  /// active tab is among them, [anchor] takes over.
  void _closeSet(Set<TabId> removed, {required TabId anchor}) {
    final tabs = state.tabs.where((tab) => !removed.contains(tab.tabId));
    final active = removed.contains(state.activeTabId)
        ? anchor
        : state.activeTabId!;
    _commit(
      state.copyWith(
        tabs: List.unmodifiable(tabs),
        activeTabId: active,
        clearPreviousTabId:
            state.previousTabId == null || removed.contains(state.previousTabId),
      ),
    );
  }

  void closeAll() {
    if (state.tabs.isEmpty) return;
    _commit(const BrowserTabsState(tabs: [], activeTabId: null));
  }

  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= state.tabs.length ||
        newIndex < 0 ||
        newIndex >= state.tabs.length) {
      return;
    }
    final tabs = [...state.tabs];
    final moved = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, moved);
    // Groups keep their order: a drag cannot carry a tab into the other pane.
    _commit(state.copyWith(tabs: List.unmodifiable(tabs)));
  }

  /// [reorderTabs] with indexes counted inside one pane's strip.
  void reorderTabsInPane(TabPane pane, int oldIndex, int newIndex) {
    final size = state.paneTabCount(pane);
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= size ||
        newIndex < 0 ||
        newIndex >= size) {
      return;
    }
    final start = _groupStart(state.tabs, pane);
    reorderTabs(start + oldIndex, start + newIndex);
  }

  void moveTab(int oldIndex, int newIndex) => reorderTabs(oldIndex, newIndex);

  bool closeByVolId(int volId) {
    final removed = state.tabs
        .where((tab) => tab.volId == volId)
        .map((tab) => tab.tabId)
        .toSet();
    if (removed.isEmpty) return false;
    final tabs = state.tabs
        .where((tab) => !removed.contains(tab.tabId))
        .toList();
    if (tabs.isEmpty) {
      _commit(const BrowserTabsState(tabs: [], activeTabId: null));
      return true;
    }
    final active = removed.contains(state.activeTabId)
        ? _survivorForActive(removed)
        : state.activeTabId!;
    _commit(
      state.copyWith(
        tabs: List.unmodifiable(tabs),
        activeTabId: active,
        clearPreviousTabId:
            state.previousTabId == null || removed.contains(state.previousTabId),
      ),
    );
    return true;
  }

  /// The tab that takes focus when the active tab goes away together with
  /// [removed]: the nearest survivor in its own pane, and only when that pane
  /// is gone altogether, the other pane's shown tab.
  TabId _survivorForActive(Set<TabId> removed) {
    final active = state.activeTab!;
    final group = state.tabsInPane(active.pane);
    final at = group.indexWhere((tab) => tab.tabId == active.tabId);
    final after = group
        .skip(at)
        .where((tab) => !removed.contains(tab.tabId))
        .firstOrNull;
    final before = group
        .take(at)
        .where((tab) => !removed.contains(tab.tabId))
        .lastOrNull;
    final inPane = after ?? before;
    if (inPane != null) return inPane.tabId;
    final other = state.activeTabIdOfPane(active.pane.other);
    if (other != null && !removed.contains(other)) return other;
    return state.tabs.firstWhere((tab) => !removed.contains(tab.tabId)).tabId;
  }

  void _removeAt(int index) {
    final removed = state.tabs[index];
    final tabs = [...state.tabs]..removeAt(index);
    if (tabs.isEmpty) {
      _commit(const BrowserTabsState(tabs: [], activeTabId: null));
      return;
    }
    final group = state.tabsInPane(removed.pane);
    final indexInPane = group.indexWhere((tab) => tab.tabId == removed.tabId);
    final survivors = group.where((tab) => tab.tabId != removed.tabId).toList();
    final neighbour = survivors.isEmpty
        ? null
        : survivors[indexInPane < survivors.length
              ? indexInPane
              : survivors.length - 1];

    if (removed.tabId != state.activeTabId) {
      // A background tab, or a tab of the pane that does not have focus. If it
      // was the one shown there, that pane moves on to its neighbour.
      final wasShownInOtherPane =
          state.activeTabIdOfPane(removed.pane) == removed.tabId;
      _commit(
        state.copyWith(
          tabs: List.unmodifiable(tabs),
          clearPreviousTabId: state.previousTabId == removed.tabId,
          unfocusedPaneTabId: wasShownInOtherPane ? neighbour?.tabId : null,
          clearUnfocusedPaneTabId: wasShownInOtherPane && neighbour == null,
        ),
      );
      return;
    }

    final TabId active;
    if (neighbour == null) {
      // The focused pane's last tab: the other pane takes over and the layout
      // collapses to it.
      active =
          state.activeTabIdOfPane(removed.pane.other) ?? tabs.first.tabId;
    } else {
      final previous = state.previousTabId;
      final previousSurvivor =
          previous != null && survivors.any((tab) => tab.tabId == previous)
          ? previous
          : null;
      active = previousSurvivor ?? neighbour.tabId;
    }
    _commit(
      state.copyWith(
        tabs: List.unmodifiable(tabs),
        activeTabId: active,
        clearPreviousTabId: true,
      ),
    );
  }

  BrowserTabState? tabForKey(TabId tabId) {
    for (final tab in state.tabs) {
      if (tab.tabId == tabId) return tab;
    }
    return null;
  }

  BrowserTabState? previousTab() {
    final id = state.previousTabId;
    if (id == null || id == state.activeTabId) return null;
    return tabForKey(id);
  }

  void activateIndex(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    activate(state.tabs[index].tabId);
  }
}

final browserTabsListProvider =
    Provider.family<List<BrowserTabState>, BrowserTabsConfig>(
      (ref, config) =>
          ref.watch(browserTabsProvider(config).select((state) => state.tabs)),
    );

final activeBrowserTabProvider =
    Provider.family<BrowserTabState?, BrowserTabsConfig>(
      (ref, config) => ref.watch(
        browserTabsProvider(config).select((state) => state.activeTab),
      ),
    );

final hasActiveBrowserTabsProvider = Provider.family<bool, BrowserTabsConfig>(
  (ref, config) => ref.watch(
    browserTabsProvider(config).select((state) => state.hasMultiple),
  ),
);

@immutable
class AggregatedTabsSelection {
  final Map<TabId, Set<RawEntry>> itemsByTab;
  final int count;
  final int bytes;
  final bool hasPendingFolderSizes;

  const AggregatedTabsSelection({
    required this.itemsByTab,
    required this.count,
    required this.bytes,
    required this.hasPendingFolderSizes,
  });

  bool get hasSelection => count > 0;
}

final aggregatedTabsSelectionProvider =
    Provider.family<AggregatedTabsSelection, BrowserTabsConfig>((ref, config) {
      final tabs = ref.watch(browserTabsListProvider(config));
      final itemsByTab = <TabId, Set<RawEntry>>{};
      var count = 0;
      var bytes = 0;
      var pending = false;
      for (final tab in tabs) {
        if (tab.isDashboard) continue;
        final selection = ref.watch(fileBrowserSelectionProvider(tab.tabId));
        final items = selection.items;
        count += items.length;
        if (items.isEmpty) {
          // The common case for every tab but the one being worked in: nothing
          // to copy or add up.
          itemsByTab[tab.tabId] = const <RawEntry>{};
          continue;
        }
        // Copied, not shared, so a consumer can never alter a tab's own
        // selection through the aggregate.
        itemsByTab[tab.tabId] = Set.unmodifiable(items);
        final totals = selection.totals;
        bytes += totals.totalBytes;
        pending = pending || totals.hasPendingFolderSizes;
      }
      return AggregatedTabsSelection(
        itemsByTab: Map.unmodifiable(itemsByTab),
        count: count,
        bytes: bytes,
        hasPendingFolderSizes: pending,
      );
    });
