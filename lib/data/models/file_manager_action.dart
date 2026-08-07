import 'package:flutter/material.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

enum FileManagerAction {
  search,
  add,
  viewToggle,
  sort,
  filter,
  playMedia;

  String get label => switch (this) {
        FileManagerAction.search => 'Search',
        FileManagerAction.add => 'Add',
        FileManagerAction.viewToggle => 'View mode',
        FileManagerAction.sort => 'Sort',
        FileManagerAction.filter => 'Filter',
        FileManagerAction.playMedia => 'Play media',
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        FileManagerAction.search => l10n.search,
        FileManagerAction.add => l10n.add,
        FileManagerAction.viewToggle => l10n.viewModeAction,
        FileManagerAction.sort => l10n.sortAction,
        FileManagerAction.filter => l10n.filterAction,
        FileManagerAction.playMedia => l10n.playMediaAction,
      };

  IconData get icon => switch (this) {
        FileManagerAction.search => Icons.search_rounded,
        FileManagerAction.add => Icons.add_rounded,
        FileManagerAction.viewToggle => Icons.grid_view_rounded,
        FileManagerAction.sort => Icons.sort_by_alpha_rounded,
        FileManagerAction.filter => Icons.filter_alt_outlined,
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