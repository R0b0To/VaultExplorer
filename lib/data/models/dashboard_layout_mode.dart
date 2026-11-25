import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// How the vaults are laid out on the dashboard, like the View menu of a
/// file manager's "This PC" page (tiles, list, details, icons).
///
/// This is only about presentation. The order of the vaults is a separate
/// setting ([ContainerSortMode]) and applies to every layout.
enum DashboardLayoutMode {
  /// The original look: one large card per vault with its usage bar. Wide
  /// windows flow the cards into several columns.
  cards,

  /// Vertical tiles -- a large icon over the name and the usage bar -- packed
  /// into as many columns as fit, like a file manager's icon view.
  grid,

  /// One dense line per vault (icon, name, state). Wide windows flow the rows
  /// into several columns, like a file manager's list view.
  list,

  /// A table with a header row: name, format, state, free space, total size
  /// and a usage bar. Columns that do not fit the width drop out.
  details;

  String get label => switch (this) {
        DashboardLayoutMode.cards => 'Cards',
        DashboardLayoutMode.grid => 'Grid',
        DashboardLayoutMode.list => 'List',
        DashboardLayoutMode.details => 'Details',
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        DashboardLayoutMode.cards => l10n.dashboardLayoutCards,
        DashboardLayoutMode.grid => l10n.dashboardLayoutGrid,
        DashboardLayoutMode.list => l10n.dashboardLayoutList,
        DashboardLayoutMode.details => l10n.dashboardLayoutDetails,
      };

  String toJson() => name;

  /// Unknown or missing values fall back to [cards], so settings written by an
  /// older version (which has no such key) keep today's look.
  static DashboardLayoutMode fromJson(String? value) => switch (value) {
        'cards' => DashboardLayoutMode.cards,
        'grid' => DashboardLayoutMode.grid,
        'list' => DashboardLayoutMode.list,
        'details' => DashboardLayoutMode.details,
        _ => DashboardLayoutMode.cards,
      };
}
