import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

enum FileManagerAction {
  search,
  add,
  gallery,
  viewToggle,
  sort,
  filter,
  playMedia,
  options;

  String get label => switch (this) {
        FileManagerAction.search => 'Search',
        FileManagerAction.add => 'Add',
        FileManagerAction.gallery => 'Gallery',
        FileManagerAction.viewToggle => 'View mode',
        FileManagerAction.sort => 'Sort',
        FileManagerAction.filter => 'Filter',
        FileManagerAction.playMedia => 'Play media',
        FileManagerAction.options => 'Options',
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        FileManagerAction.search => l10n.search,
        FileManagerAction.add => l10n.add,
        FileManagerAction.gallery => l10n.galleryModeAction,
        FileManagerAction.viewToggle => l10n.viewModeAction,
        FileManagerAction.sort => l10n.sortAction,
        FileManagerAction.filter => l10n.filterAction,
        FileManagerAction.playMedia => l10n.playMediaAction,
        FileManagerAction.options => l10n.optionsAction,
      };

  IconData get icon => switch (this) {
        FileManagerAction.search => Icons.search_rounded,
        FileManagerAction.add => Icons.add_rounded,
        FileManagerAction.gallery => Icons.photo_library_outlined,
        FileManagerAction.viewToggle => Icons.grid_view_rounded,
        FileManagerAction.sort => Icons.sort_by_alpha_rounded,
        FileManagerAction.filter => Icons.filter_alt_outlined,
        FileManagerAction.playMedia => Icons.play_circle_outline_rounded,
        FileManagerAction.options => Icons.more_vert_rounded,
      };

  String toJson() => name;

  static FileManagerAction? fromJson(String? value) {
    for (final a in FileManagerAction.values) {
      if (a.name == value) return a;
    }
    return null;
  }
}