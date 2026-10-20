import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Hard cap on simultaneously open file-manager tabs. Every file tab keeps its
/// whole `FileBrowserScreen` alive in an `IndexedStack`; the Dashboard root
/// tab is excluded from this limit.
const int kMaxBrowserTabs = 5;

/// Tab state keys start well above any real `volId` (vaults are >= 0, local /
/// external storage is negative) so a tab key can never collide with a
/// volId-keyed provider instance used by a screen that is not inside a tab
/// host (decoy mode). Never reset: a key is never reused within a session.
const int _kTabKeyBase = 1 << 20;
int _nextTabKey = _kTabKeyBase;

/// One open location: a stable [key] that scopes a file browser's per-screen
/// Riverpod state, or a Dashboard location when [container] is null.
@immutable
class BrowserTab {
  final int key;
  final MountedContainer? container;

  /// Directory (FAT path inside [container]) the tab opens at; null/empty =
  /// the container root. Only read when the tab's screen is first created.
  final String? initialPath;

  /// Whether Back at this location's root should return to Dashboard. Set
  /// when this tab was created by opening a vault from a Dashboard tab.
  final bool returnToDashboardOnRoot;

  const BrowserTab({
    required this.key,
    this.container,
    this.initialPath,
    this.returnToDashboardOnRoot = false,
  });

  bool get isDashboard => container == null;
  int? get volId => container?.volId;
}

/// State holder for the file manager's tab strip. Plain [ChangeNotifier]
/// (not a Riverpod notifier) on purpose: its lifetime is exactly one
/// `BrowserTabsHost`, and it is exposed to the screens below through
/// [BrowserTabsScope], so there is no global state to reset and nothing for
/// code outside a tab host to accidentally observe.
class BrowserTabsController extends ChangeNotifier {
  BrowserTabsController(
    MountedContainer? initial, {
    String? initialPath,
    bool includeDashboardTab = false,
  }) : _tabs = [] {
    BrowserTab? dashboard;
    if (includeDashboardTab) {
      dashboard = BrowserTab(key: _nextTabKey++);
      _tabs.add(dashboard);
    }
    if (initial == null && dashboard == null) {
      throw ArgumentError(
        'A browser tab controller needs an initial location or Dashboard tab.',
      );
    }
    if (initial != null) {
      final firstFileTab = BrowserTab(
        key: _nextTabKey++,
        container: initial,
        initialPath: initialPath,
      );
      _tabs.add(firstFileTab);
      _activeKey = firstFileTab.key;
      _previousKey = dashboard?.key;
    } else {
      _activeKey = dashboard!.key;
      _previousKey = null;
    }
  }

  final List<BrowserTab> _tabs;
  final ValueNotifier<double> appBarVisibility = ValueNotifier<double>(1.0);
  double _tabStripScrollOffset = 0.0;
  late int _activeKey;
  int? _previousKey;

  List<BrowserTab> get tabs => List.unmodifiable(_tabs);
  int get length => _tabs.length;
  bool get isEmpty => _tabs.isEmpty;
  bool get hasMultiple => _tabs.length > 1;
  int get fileTabCount => _tabs.where((tab) => !tab.isDashboard).length;
  bool get hasBrowserTabs => fileTabCount > 0;
  bool get atLimit => fileTabCount >= kMaxBrowserTabs;
  double get tabStripScrollOffset => _tabStripScrollOffset;

  void setTabStripScrollOffset(double value) {
    if (!value.isFinite) return;
    _tabStripScrollOffset = value < 0.0 ? 0.0 : value;
  }

  /// Key of the visible tab, or -1 when no tabs are open.
  int get activeKey => _tabs.isEmpty ? -1 : _activeKey;

  int get activeIndex {
    final i = _tabs.indexWhere((t) => t.key == _activeKey);
    return i < 0 ? 0 : i;
  }

  BrowserTab? get activeTab => _tabs.isEmpty ? null : _tabs[activeIndex];

  BrowserTab? get dashboardTab {
    for (final tab in _tabs) {
      if (tab.isDashboard) return tab;
    }
    return null;
  }

  /// The tab the user was on before the current one, if it is still open.
  BrowserTab? get previousTab {
    final k = _previousKey;
    if (k == null || k == _activeKey) return null;
    for (final t in _tabs) {
      if (t.key == k) return t;
    }
    return null;
  }

  BrowserTab? tabForKey(int key) {
    for (final t in _tabs) {
      if (t.key == key) return t;
    }
    return null;
  }

  void _insertAfterActive(BrowserTab tab) {
    _tabs.insert(_tabs.isEmpty ? 0 : activeIndex + 1, tab);
  }

  /// Opens a new tab for [container] (optionally at [initialPath]) and makes
  /// it the active one. Returns the new tab's key, or null when the cap
  /// ([kMaxBrowserTabs]) is reached.
  int? openTab(
    MountedContainer container, {
    String? initialPath,
    bool activate = true,
  }) {
    if (atLimit) return null;
    final tab = BrowserTab(
      key: _nextTabKey++,
      container: container,
      initialPath: initialPath,
    );
    _insertAfterActive(tab);
    if (activate) {
      _previousKey = _activeKey;
      _activeKey = tab.key;
    }
    notifyListeners();
    return tab.key;
  }

  /// Opens another Dashboard location and makes it active. Dashboard tabs do
  /// not count toward the file-tab limit. The Dashboard is a unique location,
  /// so this activates its existing tab rather than creating a duplicate.
  int openDashboardTab() {
    final existing = dashboardTab;
    if (existing != null) {
      activate(existing.key);
      return existing.key;
    }

    final tab = BrowserTab(key: _nextTabKey++);
    _insertAfterActive(tab);
    _previousKey = _activeKey;
    _activeKey = tab.key;
    notifyListeners();
    return tab.key;
  }

  /// Replaces the *active* tab with a fresh tab on [container]. A fresh key
  /// (rather than mutating the old tab) means no navigation / selection /
  /// search state from the previous location can leak into the new one.
  void replaceActive(
    MountedContainer container, {
    String? initialPath,
    bool returnToDashboardOnRoot = false,
  }) {
    if (_tabs.isEmpty) return;
    final index = activeIndex;
    final replacement = BrowserTab(
      key: _nextTabKey++,
      container: container,
      initialPath: initialPath,
      returnToDashboardOnRoot: returnToDashboardOnRoot,
    );
    final oldKey = _tabs[index].key;
    _tabs[index] = replacement;
    _activeKey = replacement.key;
    if (_previousKey == oldKey) _previousKey = null;
    notifyListeners();
  }

  /// Returns to the Dashboard in this tab if [key] is the active tab and it
  /// was opened from Dashboard. Other locations keep their root as the Back
  /// boundary.
  bool returnToDashboardAtRoot(int key) {
    final tab = tabForKey(key);
    if (tab == null || key != _activeKey || !tab.returnToDashboardOnRoot) {
      return false;
    }
    replaceActiveWithDashboard();
    return true;
  }

  /// Replaces the active file location with the Dashboard location while
  /// keeping the same tab slot. Used when navigating back to Dashboard from
  /// the root of a vault opened in the Dashboard tab.
  void replaceActiveWithDashboard() {
    if (_tabs.isEmpty || activeTab?.isDashboard == true) return;
    final index = activeIndex;
    final oldKey = _tabs[index].key;
    final replacement = BrowserTab(key: _nextTabKey++);
    _tabs[index] = replacement;
    _activeKey = replacement.key;
    if (_previousKey == oldKey) _previousKey = null;
    notifyListeners();
  }

  void activate(int key) {
    if (key == _activeKey || tabForKey(key) == null) return;
    _previousKey = _activeKey;
    _activeKey = key;
    notifyListeners();
  }

  /// Jumps back to the previously active tab ("last used", like Alt-Tab), so
  /// two locations can be flipped between with one tap. Returns false when
  /// there is no other tab to go to.
  bool swapToPrevious() {
    final prev = previousTab;
    if (prev != null) {
      activate(prev.key);
      return true;
    }
    if (_tabs.length < 2) return false;
    // No usable history (previous tab was closed): fall back to the nearest
    // neighbour so the action still does something predictable.
    final i = activeIndex;
    activate(_tabs[i == 0 ? 1 : i - 1].key);
    return true;
  }

  void closeTab(int key) {
    final index = _tabs.indexWhere((t) => t.key == key);
    // Keep one location available at all times. In particular, closing the
    // last Dashboard tab would leave later vault navigation without a tab to
    // return to.
    if (index < 0 || _tabs.length <= 1) return;
    _removeAt(index);
    notifyListeners();
  }

  /// Closes every tab except [key] (which also becomes the active tab).
  void closeOthers(int key) {
    final keep = tabForKey(key);
    if (keep == null) return;
    _tabs
      ..clear()
      ..add(keep);
    _activeKey = keep.key;
    _previousKey = null;
    notifyListeners();
  }

  /// Closes tabs before [key] while keeping that location active.
  void closeToLeft(int key) => _closeOnSide(key, closeLeft: true);

  /// Closes tabs after [key] while keeping that location active.
  void closeToRight(int key) => _closeOnSide(key, closeLeft: false);

  void _closeOnSide(int key, {required bool closeLeft}) {
    final index = _tabs.indexWhere((tab) => tab.key == key);
    if (index < 0) return;
    final removedKeys = closeLeft
        ? _tabs.take(index).map((tab) => tab.key).toSet()
        : _tabs.skip(index + 1).map((tab) => tab.key).toSet();
    if (removedKeys.isEmpty) return;

    _tabs.removeWhere((tab) => removedKeys.contains(tab.key));
    if (removedKeys.contains(_activeKey)) _activeKey = key;
    if (_previousKey != null && removedKeys.contains(_previousKey)) {
      _previousKey = null;
    }
    if (_previousKey == _activeKey) _previousKey = null;
    notifyListeners();
  }

  /// Closes all file tabs, keeping the Dashboard root tab when present.
  /// Kept for callers that need bulk cleanup; the tab menu exposes the more
  /// precise close-to-left/right operations instead.
  void closeAll() {
    if (_tabs.length <= 1 || !hasBrowserTabs) return;
    final survivor = activeTab?.isDashboard == true
        ? activeTab
        : dashboardTab ?? activeTab;
    if (survivor == null) return;
    _tabs
      ..clear()
      ..add(survivor);
    _activeKey = survivor.key;
    _previousKey = null;
    notifyListeners();
  }

  /// Moves the tab at [oldIndex] to [newIndex] (drag-to-reorder in the
  /// strip). Both indices are positions in [tabs]; the active tab stays
  /// active because it is tracked by key, not by position.
  void moveTab(int oldIndex, int newIndex) {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= _tabs.length ||
        newIndex < 0 ||
        newIndex >= _tabs.length) {
      return;
    }
    final moved = _tabs.removeAt(oldIndex);
    _tabs.insert(newIndex, moved);
    notifyListeners();
  }

  /// Closes every tab browsing [volId] (vault locked / USB detached / storage
  /// removed). Returns true when at least one tab was closed.
  bool closeByVolId(int volId) {
    var closed = false;
    for (var i = _tabs.length - 1; i >= 0; i--) {
      if (_tabs[i].volId != volId) continue;
      _removeAt(i);
      closed = true;
    }
    if (closed) notifyListeners();
    return closed;
  }

  void _removeAt(int index) {
    final removed = _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _previousKey = null;
      return;
    }
    if (removed.key != _activeKey) {
      if (_previousKey == removed.key) _previousKey = null;
      return;
    }
    // The active tab was removed: prefer the previously used tab, otherwise
    // the neighbour that slid into its slot (or the new last one).
    final prev = _previousKey;
    if (prev != null && tabForKey(prev) != null) {
      _activeKey = prev;
    } else {
      final slot = index >= _tabs.length ? _tabs.length - 1 : index;
      _activeKey = _tabs[slot].key;
    }
    _previousKey = null;
  }

  void setAppBarVisibility(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if ((appBarVisibility.value - clamped).abs() < 0.001) return;
    appBarVisibility.value = clamped;
  }

  @override
  void dispose() {
    appBarVisibility.dispose();
    super.dispose();
  }
}

/// Makes a host's [BrowserTabsController] reachable from the file browser
/// screens (and anything inside them). Absent outside a tab host, which is
/// how a screen knows it is not embedded in tabs.
class BrowserTabsScope extends InheritedNotifier<BrowserTabsController> {
  const BrowserTabsScope({
    super.key,
    required BrowserTabsController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The enclosing controller, or null when not inside a tab host. With
  /// [listen] false (the default for event handlers) the caller is not
  /// rebuilt when the tab list changes.
  static BrowserTabsController? maybeOf(
    BuildContext context, {
    bool listen = false,
  }) {
    if (listen) {
      return context
          .dependOnInheritedWidgetOfExactType<BrowserTabsScope>()
          ?.notifier;
    }
    return context.getInheritedWidgetOfExactType<BrowserTabsScope>()?.notifier;
  }
}
