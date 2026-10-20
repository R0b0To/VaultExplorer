import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';

export 'browser_tabs_provider.dart'
    show BrowserTabState, BrowserTabsConfig, kMaxBrowserTabs;

/// Kept as a source-compatible name for the tab strip and screen callbacks.
typedef BrowserTab = BrowserTabState;

/// Legacy compatibility facade. Production browser chrome and viewports read
/// [browserTabsProvider] directly; this adapter remains for older integrations.
@Deprecated('Use browserTabsProvider with a BrowserTabsConfig.')
class BrowserTabsController extends ChangeNotifier {
  BrowserTabsController(
    MountedContainer? initial, {
    String? initialPath,
    bool includeDashboardTab = false,
    ProviderContainer? providerContainer,
  }) : config = BrowserTabsConfig.create(
         initialContainer: initial,
         initialPath: initialPath,
         includeDashboardTab: includeDashboardTab,
       ),
       _providerContainer = providerContainer ?? ProviderContainer(),
       _ownsProviderContainer = providerContainer == null {
    _subscription = _providerContainer.listen<BrowserTabsState>(
      browserTabsProvider(config),
      (previous, next) => notifyListeners(),
    );
  }

  final BrowserTabsConfig config;
  final ProviderContainer _providerContainer;
  final bool _ownsProviderContainer;
  late final ProviderSubscription<BrowserTabsState> _subscription;
  final ValueNotifier<double> appBarVisibility = ValueNotifier<double>(1.0);

  BrowserTabsState get _state =>
      _providerContainer.read(browserTabsProvider(config));
  BrowserTabs get _notifier =>
      _providerContainer.read(browserTabsProvider(config).notifier);

  List<BrowserTab> get tabs => List.unmodifiable(_state.tabs);
  int get length => _state.tabs.length;
  bool get isEmpty => _state.tabs.isEmpty;
  bool get hasMultiple => _state.hasMultiple;
  int get fileTabCount => _state.fileTabCount;
  bool get hasBrowserTabs => fileTabCount > 0;
  bool get atLimit => _state.atLimit;
  double get tabStripScrollOffset => _state.tabStripScrollOffset;
  int get activeKey {
    final activeTabId = _state.activeTabId;
    return activeTabId == null ? -1 : _legacyKey(activeTabId);
  }

  int get activeIndex => _state.activeIndex;
  BrowserTab? get activeTab => _state.activeTab;
  BrowserTab? get previousTab => _notifier.previousTab();

  BrowserTab? get dashboardTab {
    for (final tab in _state.tabs) {
      if (tab.isDashboard) return tab;
    }
    return null;
  }

  BrowserTab? tabForKey(int key) =>
      _notifier.tabForKey(_tabIdFromLegacyKey(key));

  void setTabStripScrollOffset(double value) =>
      _notifier.setTabStripScrollOffset(value);

  int? openTab(
    MountedContainer container, {
    String? initialPath,
    bool activate = true,
  }) {
    final tabId = _notifier.openTab(
      container,
      initialPath: initialPath,
      activate: activate,
    );
    return tabId == null ? null : _legacyKey(tabId);
  }

  int openDashboardTab() => _legacyKey(_notifier.openDashboardTab());

  void replaceActive(MountedContainer container, {String? initialPath}) =>
      _notifier.replaceActive(container, initialPath: initialPath);

  bool returnToDashboardAtRoot(int key) =>
      _notifier.returnToDashboardAtRoot(_tabIdFromLegacyKey(key));

  void replaceActiveWithDashboard() => _notifier.replaceActiveWithDashboard();
  void activate(int key) => _notifier.activate(_tabIdFromLegacyKey(key));
  bool swapToPrevious() => _notifier.swapToPrevious();
  void closeTab(int key) => _notifier.closeTab(_tabIdFromLegacyKey(key));
  void closeOthers(int key) => _notifier.closeOthers(_tabIdFromLegacyKey(key));
  void closeToLeft(int key) => _notifier.closeToLeft(_tabIdFromLegacyKey(key));
  void closeToRight(int key) =>
      _notifier.closeToRight(_tabIdFromLegacyKey(key));
  void closeAll() => _notifier.closeAll();
  void moveTab(int oldIndex, int newIndex) =>
      _notifier.moveTab(oldIndex, newIndex);
  void reorderTabs(int oldIndex, int newIndex) =>
      _notifier.reorderTabs(oldIndex, newIndex);
  void activateIndex(int index) => _notifier.activateIndex(index);
  bool closeByVolId(int volId) => _notifier.closeByVolId(volId);

  static int _legacyKey(TabId tabId) => (1 << 20) + tabId.value;

  static TabId _tabIdFromLegacyKey(int key) => TabId(key - (1 << 20));

  void setAppBarVisibility(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if ((appBarVisibility.value - clamped).abs() < 0.001) return;
    appBarVisibility.value = clamped;
  }

  @override
  void dispose() {
    _subscription.close();
    appBarVisibility.dispose();
    if (_ownsProviderContainer) _providerContainer.dispose();
    super.dispose();
  }
}
