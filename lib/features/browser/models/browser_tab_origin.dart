/// Where a folder tab was opened from. It decides where system back goes once
/// the tab is at its root: back returns the person to where they started.
enum BrowserTabOrigin {
  /// Opened from a Home tile or card. Back at the root returns to Home.
  home,

  /// Opened from the drawer, a folder action, a menu or the new-tab sheet.
  /// Back stops at the root of the storage.
  other,
}
