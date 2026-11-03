import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_sort_controller.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';

/// Keeps the tabs of the revealed vault shell alive while Mask Mode's decoy
/// is the visible identity, so revealing the vault again resumes where the
/// person left off instead of starting from an empty Home.
///
/// Why this is needed: the revealed `MainShell` sits on a route above the
/// decoy and is torn down whenever the app goes back to the decoy (backing
/// out, the app being backgrounded, the app lock). Everything about its tabs
/// lives in auto-disposed providers -- the tab list in [browserTabsProvider],
/// and each tab's folder location and sort in the `fileBrowserNavigation` and
/// `fileBrowserSort` families -- so tearing the shell down used to dispose all
/// of it.
///
/// While the revealed shell is up it hands its workspace to [hold]. The store
/// then keeps a listener on the workspace and on each folder tab's location
/// and sort, which stops them from being disposed with the shell. The next
/// revealed shell asks [resumable] for that workspace and passes it to
/// `BrowserTabsShell.restoredWorkspace`.
///
/// Search and selection are deliberately not kept: they are transient, tied to
/// widgets that are rebuilt on the next reveal, and a deep search may still be
/// running, so they start empty again exactly as they would after switching
/// tabs away and back.
///
/// The store never keeps anything for a vault that is no longer open: when a
/// vault locks (or a USB drive is detached) its tabs are closed right here,
/// which also lets their listings and archive sessions go. A panic purge
/// drops the whole session.
///
/// Only the revealed shell uses this. A normal (non-Mask-Mode) launch, and
/// the decoy's own file manager, are unchanged.
class BrowserSessionStore {
  BrowserTabsConfig? _workspace;
  ProviderContainer? _container;
  VaultEngineEvents? _events;
  ProviderSubscription<BrowserTabsState>? _workspaceSubscription;
  final Map<TabId, List<ProviderSubscription<Object?>>> _tabSubscriptions = {};

  /// Whether a workspace is currently being kept.
  bool get isHolding => _workspace != null;

  /// Starts keeping [workspace] alive. Calling it again for the workspace it
  /// already holds does nothing; a different workspace replaces the old one.
  void hold(ProviderContainer container, BrowserTabsConfig workspace) {
    if (_workspace == workspace && identical(_container, container)) return;
    release();

    _container = container;
    _workspace = workspace;

    final events = container.read(vaultEngineEventsProvider);
    _events = events;
    events.addContainerLockedListener(_onVolumeGone);
    events.addUsbContainerDetachedListener(_onVolumeGone);
    events.addPanicSessionPurgedListener(_onPanic);
    events.addPanicCredentialsPurgedListener(_onPanic);

    _workspaceSubscription = container.listen<BrowserTabsState>(
      browserTabsProvider(workspace),
      (_, next) => _syncTabSubscriptions(next),
      fireImmediately: true,
    );
  }

  /// The workspace to resume, or null when there is nothing worth resuming
  /// (nothing held, or every tab has gone with its vault). In the latter case
  /// whatever is left is released, so the next shell starts clean.
  BrowserTabsConfig? resumable() {
    final container = _container;
    final workspace = _workspace;
    if (container == null || workspace == null) return null;
    final state = container.read(browserTabsProvider(workspace));
    if (state.tabs.isEmpty) {
      release();
      return null;
    }
    return workspace;
  }

  /// Lets go of the held workspace and every tab's providers, so they are
  /// disposed as soon as nothing else is using them.
  void release() {
    final events = _events;
    if (events != null) {
      events.removeContainerLockedListener(_onVolumeGone);
      events.removeUsbContainerDetachedListener(_onVolumeGone);
      events.removePanicSessionPurgedListener(_onPanic);
      events.removePanicCredentialsPurgedListener(_onPanic);
    }
    _events = null;

    _workspaceSubscription?.close();
    _workspaceSubscription = null;

    for (final subscriptions in _tabSubscriptions.values) {
      for (final subscription in subscriptions) {
        subscription.close();
      }
    }
    _tabSubscriptions.clear();

    _workspace = null;
    _container = null;
  }

  void _onPanic() => scheduleMicrotask(release);

  void _onVolumeGone(int volId) {
    final container = _container;
    final workspace = _workspace;
    if (container == null || workspace == null) return;
    // Idempotent: when the shell is on screen its own listener has usually
    // closed these tabs already.
    container.read(browserTabsProvider(workspace).notifier).closeByVolId(volId);
  }

  /// Mirrors the workspace's folder tabs: every open one has its location and
  /// sort held, every closed one has them released.
  void _syncTabSubscriptions(BrowserTabsState next) {
    final container = _container;
    if (container == null) return;

    final live = <TabId>{
      for (final tab in next.tabs)
        if (!tab.isDashboard) tab.tabId,
    };

    for (final id in _tabSubscriptions.keys
        .where((id) => !live.contains(id))
        .toList()) {
      final subscriptions = _tabSubscriptions.remove(id);
      if (subscriptions == null) continue;
      for (final subscription in subscriptions) {
        subscription.close();
      }
    }

    for (final id in live) {
      _tabSubscriptions.putIfAbsent(
        id,
        () => <ProviderSubscription<Object?>>[
          container.listen(fileBrowserNavigationProvider(id), (_, _) {}),
          container.listen(fileBrowserSortProvider(id), (_, _) {}),
        ],
      );
    }
  }
}

/// The single store for the app. Lives as long as the app does, so it
/// outlives every revealed shell.
final browserSessionStoreProvider = Provider<BrowserSessionStore>((ref) {
  final store = BrowserSessionStore();
  ref.onDispose(store.release);
  return store;
});
