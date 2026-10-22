import 'package:vaultexplorer/features/browser/models/browser_tab_origin.dart';

/// What system back does for the focused directory viewport.
enum BrowserBackAction {
  /// Leave selection mode.
  exitSelection,

  /// Close the search field and show the folder again.
  clearSearch,

  /// Go to the parent folder.
  navigateUp,

  /// At the root of a tab that was opened from Home: show Home again.
  returnHome,

  /// At the root of a route-hosted browser without tabs: close the route.
  popRoute,

  /// At the root of a tab that was not opened from Home: stay put.
  stay,

  /// Nothing left for the browser to do; let the system leave the app.
  leave,
}

/// Decides what system back means, in order: selection, search, folder depth,
/// then the person's starting point once the root is reached.
///
/// [canPop] and the back handler both come from this one function, so what the
/// system is told ("I will handle this") can never drift from what happens.
BrowserBackAction resolveBrowserBack({
  required bool selectionMode,
  required bool searchActive,
  required bool atRoot,
  required BrowserTabOrigin origin,

  /// The workspace is the app's root surface (decoy mode).
  required bool appRoot,

  /// The workspace has a Home tab, i.e. it is the one embedded in the main
  /// shell rather than a browser route pushed over another screen.
  required bool hostsHome,
  required bool tabsEnabled,
}) {
  if (selectionMode) return BrowserBackAction.exitSelection;
  if (searchActive) return BrowserBackAction.clearSearch;
  if (!atRoot) return BrowserBackAction.navigateUp;
  if (appRoot) return BrowserBackAction.leave;
  if (hostsHome) {
    return origin == BrowserTabOrigin.home
        ? BrowserBackAction.returnHome
        : BrowserBackAction.stay;
  }
  return tabsEnabled ? BrowserBackAction.stay : BrowserBackAction.popRoute;
}
