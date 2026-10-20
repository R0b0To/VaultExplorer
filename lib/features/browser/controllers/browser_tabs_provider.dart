import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';

part 'browser_tabs_provider.g.dart';

/// Hard cap on all simultaneously open browser tabs, including Dashboard.
const int kMaxBrowserTabs = 5;

sealed class BrowserTabKind {
  const BrowserTabKind();
}

/// The unique workspace Dashboard page. It cannot be closed directly and can
/// occupy the active tab's slot when the user navigates Home.
final class HomeTab extends BrowserTabKind {
  const HomeTab();
}

/// A folder location in a mounted vault or storage container.
@immutable
final class FolderTab extends BrowserTabKind {
  const FolderTab({required this.container, this.initialPath});

  final MountedContainer container;
  final String? initialPath;
}

/// A single location in a browser workspace.
@immutable
class BrowserTabState {
  final TabId tabId;
  final BrowserTabKind kind;

  const BrowserTabState.home({required this.tabId}) : kind = const HomeTab();

  BrowserTabState.folder({
    required this.tabId,
    required MountedContainer container,
    String? initialPath,
  }) : kind = FolderTab(container: container, initialPath: initialPath);

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

  /// Compatibility accessor for older integrations. Production widgets key by
  /// [tabId] directly; keep legacy integer keys in a reserved range.
  @Deprecated('Use tabId.')
  int get key => (1 << 20) + tabId.value;
}

/// Unique per hosted browser route. Keeping the initial route data in this
/// family argument lets each route own an auto-disposed Riverpod engine while
/// retaining a lightweight compatibility controller for existing widgets.
@immutable
class BrowserTabsConfig {
  static int _nextSessionId = 1;

  final int sessionId;
  final MountedContainer? initialContainer;
  final String? initialPath;
  final bool includeDashboardTab;

  const BrowserTabsConfig._({
    required this.sessionId,
    required this.initialContainer,
    this.initialPath,
    this.includeDashboardTab = false,
  });

  factory BrowserTabsConfig.create({
    MountedContainer? initialContainer,
    String? initialPath,
    bool includeDashboardTab = false,
  }) => BrowserTabsConfig._(
    sessionId: _nextSessionId++,
    initialContainer: initialContainer,
    initialPath: initialPath,
    includeDashboardTab: includeDashboardTab,
  );
}

@immutable
class BrowserTabsState {
  final List<BrowserTabState> tabs;
  final TabId? activeTabId;
  final TabId? previousTabId;
  final double tabStripScrollOffset;

  const BrowserTabsState({
    required this.tabs,
    required this.activeTabId,
    this.previousTabId,
    this.tabStripScrollOffset = 0,
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

  BrowserTabsState copyWith({
    List<BrowserTabState>? tabs,
    TabId? activeTabId,
    TabId? previousTabId,
    bool clearPreviousTabId = false,
    double? tabStripScrollOffset,
  }) => BrowserTabsState(
    tabs: tabs ?? this.tabs,
    activeTabId: activeTabId ?? this.activeTabId,
    previousTabId: clearPreviousTabId
        ? null
        : (previousTabId ?? this.previousTabId),
    tabStripScrollOffset: tabStripScrollOffset ?? this.tabStripScrollOffset,
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

  void setTabStripScrollOffset(double value) {
    if (!value.isFinite) return;
    final offset = value < 0 ? 0.0 : value;
    if (state.tabStripScrollOffset == offset) return;
    state = state.copyWith(tabStripScrollOffset: offset);
  }

  TabId? openTab(
    MountedContainer container, {
    String? initialPath,
    bool activate = true,
  }) {
    if (state.atLimit) return null;
    final tab = BrowserTabState.folder(
      tabId: TabId.allocate(),
      container: container,
      initialPath: initialPath,
    );
    final tabs = [...state.tabs];
    tabs.insert(tabs.isEmpty ? 0 : state.activeIndex + 1, tab);
    state = state.copyWith(
      tabs: List.unmodifiable(tabs),
      previousTabId: activate ? state.activeTabId : state.previousTabId,
      activeTabId: activate ? tab.tabId : state.activeTabId,
    );
    return tab.tabId;
  }

  TabId openDashboardTab() {
    final existing = state.tabs.where((tab) => tab.isDashboard).firstOrNull;
    if (existing != null) {
      activate(existing.tabId);
      return existing.tabId;
    }
    if (state.atLimit) {
      replaceActiveWithDashboard();
      return state.activeTabId ?? state.tabs.first.tabId;
    }
    final tab = BrowserTabState.home(tabId: TabId.allocate());
    final tabs = [...state.tabs];
    tabs.insert(0, tab);
    state = state.copyWith(
      tabs: List.unmodifiable(tabs),
      previousTabId: state.activeTabId,
      activeTabId: tab.tabId,
    );
    return tab.tabId;
  }

  void replaceActive(MountedContainer container, {String? initialPath}) {
    if (state.tabs.isEmpty || state.activeIndex < 0) return;
    final tabs = [...state.tabs];
    final index = state.activeIndex;
    final oldId = tabs[index].tabId;
    final replacement = BrowserTabState.folder(
      tabId: TabId.allocate(),
      container: container,
      initialPath: initialPath,
    );
    tabs[index] = replacement;
    state = state.copyWith(
      tabs: List.unmodifiable(tabs),
      activeTabId: replacement.tabId,
      clearPreviousTabId: state.previousTabId == oldId,
    );
  }

  bool returnToDashboardAtRoot(TabId tabId) {
    if (tabId != state.activeTabId) return false;
    final home = state.tabs.where((tab) => tab.isDashboard).firstOrNull;
    if (home == null) return false;
    activate(home.tabId);
    return true;
  }

  void replaceActiveWithDashboard() {
    final activeTab = state.activeTab;
    if (activeTab == null) {
      if (state.tabs.isEmpty) openDashboardTab();
      return;
    }
    if (activeTab.isDashboard) return;

    final activeTabId = activeTab.tabId;
    final removedDashboardIds = state.tabs
        .where((tab) => tab.isDashboard)
        .map((tab) => tab.tabId)
        .toSet();
    final tabs = state.tabs.where((tab) => !tab.isDashboard).toList();
    final activeIndex = tabs.indexWhere((tab) => tab.tabId == activeTabId);
    if (activeIndex < 0) return;

    final dashboard = BrowserTabState.home(tabId: TabId.allocate());
    tabs[activeIndex] = dashboard;
    state = state.copyWith(
      tabs: List.unmodifiable(tabs),
      activeTabId: dashboard.tabId,
      clearPreviousTabId: removedDashboardIds.contains(state.previousTabId),
    );
  }

  void activate(TabId tabId) {
    if (tabId == state.activeTabId || tabForKey(tabId) == null) return;
    state = state.copyWith(
      activeTabId: tabId,
      previousTabId: state.activeTabId,
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

  void closeTab(TabId tabId) {
    final index = state.tabs.indexWhere((tab) => tab.tabId == tabId);
    if (index < 0) return;
    if (state.tabs[index].isDashboard) return;
    _removeAt(index);
  }

  void closeOthers(TabId tabId) {
    final keep = tabForKey(tabId);
    if (keep == null) return;
    final home = state.tabs.where((tab) => tab.isDashboard).firstOrNull;
    final tabs = home != null && home.tabId != keep.tabId
        ? List<BrowserTabState>.unmodifiable([home, keep])
        : List<BrowserTabState>.unmodifiable([keep]);
    state = BrowserTabsState(tabs: tabs, activeTabId: keep.tabId);
  }

  void closeToLeft(TabId tabId) => _closeOnSide(tabId, closeLeft: true);
  void closeToRight(TabId tabId) => _closeOnSide(tabId, closeLeft: false);

  void _closeOnSide(TabId tabId, {required bool closeLeft}) {
    final index = state.tabs.indexWhere((tab) => tab.tabId == tabId);
    if (index < 0) return;
    final removed =
        (closeLeft
              ? state.tabs.take(index).map((tab) => tab.tabId).toSet()
              : state.tabs.skip(index + 1).map((tab) => tab.tabId).toSet())
          ..removeWhere(
            (id) => state.tabs.any((tab) => tab.tabId == id && tab.isDashboard),
          );
    if (removed.isEmpty) return;
    final tabs = state.tabs
        .where((tab) => !removed.contains(tab.tabId))
        .toList();
    final active = removed.contains(state.activeTabId)
        ? tabId
        : state.activeTabId!;
    state = state.copyWith(
      tabs: List.unmodifiable(tabs),
      activeTabId: active,
      clearPreviousTabId:
          state.previousTabId == null || removed.contains(state.previousTabId),
    );
  }

  void closeAll() {
    final home = state.tabs.where((tab) => tab.isDashboard).firstOrNull;
    if (home != null) {
      state = BrowserTabsState(
        tabs: List.unmodifiable([home]),
        activeTabId: home.tabId,
      );
    } else if (state.tabs.isNotEmpty) {
      state = const BrowserTabsState(tabs: [], activeTabId: null);
    }
  }

  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= state.tabs.length ||
        newIndex < 0 ||
        newIndex >= state.tabs.length) {
      return;
    }
    if (state.tabs[oldIndex].isDashboard) return;
    if (state.tabs.firstOrNull?.isDashboard == true && newIndex == 0) {
      newIndex = 1;
    }
    final tabs = [...state.tabs];
    final moved = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, moved);
    state = state.copyWith(tabs: List.unmodifiable(tabs));
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
      state = const BrowserTabsState(tabs: [], activeTabId: null);
      return true;
    }
    final oldActiveIndex = state.activeIndex;
    final active = removed.contains(state.activeTabId)
        ? tabs[oldActiveIndex.clamp(0, tabs.length - 1)].tabId
        : state.activeTabId!;
    state = state.copyWith(
      tabs: List.unmodifiable(tabs),
      activeTabId: active,
      clearPreviousTabId:
          state.previousTabId == null || removed.contains(state.previousTabId),
    );
    return true;
  }

  void _removeAt(int index) {
    final removed = state.tabs[index];
    final tabs = [...state.tabs]..removeAt(index);
    if (tabs.isEmpty) {
      state = const BrowserTabsState(tabs: [], activeTabId: null);
      return;
    }
    if (removed.tabId != state.activeTabId) {
      state = state.copyWith(
        tabs: List.unmodifiable(tabs),
        clearPreviousTabId: state.previousTabId == removed.tabId,
      );
      return;
    }
    final previousStillOpen =
        state.previousTabId != null &&
        tabs.any((tab) => tab.tabId == state.previousTabId);
    final active = previousStillOpen
        ? state.previousTabId!
        : tabs[index >= tabs.length ? tabs.length - 1 : index].tabId;
    state = state.copyWith(
      tabs: List.unmodifiable(tabs),
      activeTabId: active,
      clearPreviousTabId: true,
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
      var bytes = 0;
      var pending = false;
      for (final tab in tabs) {
        if (tab.isDashboard) continue;
        final selection = ref.watch(fileBrowserSelectionProvider(tab.tabId));
        itemsByTab[tab.tabId] = Set.unmodifiable(selection.items);
        bytes += selection.selectedTotalBytes;
        pending = pending || selection.hasPendingFolderSizes;
      }
      return AggregatedTabsSelection(
        itemsByTab: Map.unmodifiable(itemsByTab),
        count: itemsByTab.values.fold<int>(
          0,
          (sum, items) => sum + items.length,
        ),
        bytes: bytes,
        hasPendingFolderSizes: pending,
      );
    });
