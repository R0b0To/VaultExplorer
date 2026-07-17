import 'package:flutter/material.dart';

/// One button/action that can appear in the file browser's action bar —
/// the bottom navigation bar in portrait, the sidebar rail in landscape.
///
/// Kept as a small, stable enum (rather than baking behaviour into a
/// widget) so ordering/visibility can be persisted as plain strings via
/// [FileManagerToolbarConfig] without depending on any widget code, and so
/// the customize-toolbar settings screen can list every action generically.
enum FileManagerAction {
  search,
  add,
  viewToggle,
  sort,
  playMedia;

  /// Human-readable label, used by the customize-toolbar settings screen.
  String get label => switch (this) {
        FileManagerAction.search => 'Search',
        FileManagerAction.add => 'Add',
        FileManagerAction.viewToggle => 'View mode',
        FileManagerAction.sort => 'Sort',
        FileManagerAction.playMedia => 'Play media',
      };

  /// Static icon shown in the customize-toolbar settings screen. The live
  /// action bar may render a different, state-dependent icon for some
  /// actions (e.g. "view toggle" shows the *target* mode's icon) — see
  /// FileBrowserScreen's action builders for that logic.
  IconData get icon => switch (this) {
        FileManagerAction.search => Icons.search_rounded,
        FileManagerAction.add => Icons.add_rounded,
        FileManagerAction.viewToggle => Icons.grid_view_rounded,
        FileManagerAction.sort => Icons.sort_by_alpha_rounded,
        FileManagerAction.playMedia => Icons.play_circle_outline_rounded,
      };

  String toJson() => name;

  static FileManagerAction? fromJson(String? value) {
    for (final a in FileManagerAction.values) {
      if (a.name == value) return a;
    }
    return null;
  }
}
