import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';

/// Entry points of one Vaults tab, published for the desktop toolbar.
///
/// The Home toolbar is built by the shell, outside the dashboard's widget
/// subtree, so it cannot reach [VaultDashboardState] directly. The live
/// dashboard registers its actions here and the toolbar listens. A null value
/// means this tab's dashboard is not mounted, and the toolbar buttons disable
/// themselves.
class DashboardToolbarActions {
  /// Opens the "Add a vault" options (mount existing, create new, USB).
  final ValueNotifier<VoidCallback?> addVault = ValueNotifier(null);

  /// What the toolbar's search field holds. The dashboard filters its vault
  /// list by it; an empty string means no filter.
  final ValueNotifier<String> searchQuery = ValueNotifier('');
}

/// The toolbar state of every Vaults tab, by tab id.
///
/// Several Vaults tabs can be open at once, and the one toolbar the shell shows
/// belongs to whichever is in front. Each tab therefore has its own handle: a
/// search typed in one tab neither filters nor is shown in another, and the Add
/// button always opens the sheet of the tab it is shown for.
class DashboardToolbarRegistry {
  final Map<TabId, DashboardToolbarActions> _byTab = {};

  // For a dashboard that is not hosted in a tab workspace.
  final DashboardToolbarActions _standalone = DashboardToolbarActions();

  /// The handle of [tabId], created on first use. A null id (a dashboard shown
  /// outside a tab workspace) gets one shared standalone handle.
  DashboardToolbarActions forTab(TabId? tabId) => tabId == null
      ? _standalone
      : _byTab.putIfAbsent(tabId, DashboardToolbarActions.new);

  /// Forgets the handles of tabs that have been closed.
  ///
  /// The registry is shared by every window, so each workspace releases only
  /// the tabs it knows to be gone; it cannot tell which handles belong to
  /// another window's tabs.
  ///
  /// The notifiers are not disposed: a closing tab's dashboard and toolbar may
  /// still touch them while the tree is torn down, and a notifier nobody
  /// listens to any more holds nothing that needs releasing.
  void release(Iterable<TabId> tabIds) {
    for (final id in tabIds) {
      _byTab.remove(id);
    }
  }
}

final dashboardToolbarActionsProvider = Provider<DashboardToolbarRegistry>(
  (ref) => DashboardToolbarRegistry(),
);
