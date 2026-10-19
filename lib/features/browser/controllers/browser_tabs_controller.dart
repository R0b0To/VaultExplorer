import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Hard cap on simultaneously open file-manager tabs. Every open tab keeps its
/// whole `FileBrowserScreen` (scroll positions, path stack, selection, archive
/// context) alive in an `IndexedStack`, so this bounds the memory cost.
const int kMaxBrowserTabs = 5;

/// Tab state keys start well above any real `volId` (vaults are >= 0, local /
/// external storage is negative) so a tab key can never collide with a
/// volId-keyed provider instance used by a screen that is not inside a tab
/// host (decoy mode). Never reset: a key is never reused within a session.
const int _kTabKeyBase = 1 << 20;
int _nextTabKey = _kTabKeyBase;

/// One open tab: a stable [key] that scopes all of the file browser's
/// per-screen Riverpod state (navigation, selection, search, sort), plus the
/// container it browses and, optionally, the directory it should open at.
@immutable
class BrowserTab {
  final int key;
  final MountedContainer container;

  /// Directory (FAT path inside [container]) the tab opens at; null/empty =
  /// the container root. Only read when the tab's screen is first created.
  final String? initialPath;

  const BrowserTab({
    required this.key,
    required this.container,
    this.initialPath,
  });

  int get volId => container.volId;
}

/// State holder for the file manager's tab strip. Plain [ChangeNotifier]
/// (not a Riverpod notifier) on purpose: its lifetime is exactly one
/// `BrowserTabsHost`, and it is exposed to the screens below through
/// [BrowserTabsScope], so there is no global state to reset and nothing for
/// code outside a tab host to accidentally observe.
class BrowserTabsController extends ChangeNotifier {
  BrowserTabsController(MountedContainer initial, {String? initialPath})
    : _tabs = [
        BrowserTab(
          key: _nextTabKey++,
          container: initial,
          initialPath: initialPath,
        ),
      ] {
    _activeKey = _tabs.first.key;
  }

  final List<BrowserTab> _tabs;
  late int _activeKey;
  int? _previousKey;
  int? _pasteRequestKey;

  List<BrowserTab> get tabs => List.unmodifiable(_tabs);
  int get length => _tabs.length;
  bool get isEmpty => _tabs.isEmpty;
  bool get hasMultiple => _tabs.length > 1;
  bool get atLimit => _tabs.length >= kMaxBrowserTabs;

  /// Key of the visible tab, or -1 when no tabs are open.
  int get activeKey => _tabs.isEmpty ? -1 : _activeKey;

  int get activeIndex {
    final i = _tabs.indexWhere((t) => t.key == _activeKey);
    return i < 0 ? 0 : i;
  }

  BrowserTab? get activeTab => _tabs.isEmpty ? null : _tabs[activeIndex];

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
    _tabs.add(tab);
    if (activate) {
      _previousKey = _activeKey;
      _activeKey = tab.key;
    }
    notifyListeners();
    return tab.key;
  }

  /// Replaces the *active* tab with a fresh tab on [container]. A fresh key
  /// (rather than mutating the old tab) means no navigation / selection /
  /// search state from the previous location can leak into the new one.
  void replaceActive(MountedContainer container, {String? initialPath}) {
    if (_tabs.isEmpty) return;
    final index = activeIndex;
    final replacement = BrowserTab(
      key: _nextTabKey++,
      container: container,
      initialPath: initialPath,
    );
    final oldKey = _tabs[index].key;
    _tabs[index] = replacement;
    _activeKey = replacement.key;
    if (_previousKey == oldKey) _previousKey = null;
    if (_pasteRequestKey == oldKey) _pasteRequestKey = null;
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
    if (index < 0) return;
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
    _pasteRequestKey = null;
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

  /// Asks the tab with [key] to run its paste action the next time it
  /// observes the controller (used by "copy/move to other tab" after the
  /// clipboard has been staged and the tab activated).
  void requestPaste(int key) {
    if (tabForKey(key) == null) return;
    _pasteRequestKey = key;
    notifyListeners();
  }

  /// Returns true exactly once per [requestPaste] for [key].
  bool consumePasteRequest(int key) {
    if (_pasteRequestKey != key) return false;
    _pasteRequestKey = null;
    return true;
  }

  void _removeAt(int index) {
    final removed = _tabs.removeAt(index);
    if (_pasteRequestKey == removed.key) _pasteRequestKey = null;
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
