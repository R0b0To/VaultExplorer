import 'package:vaultexplorer/core/theme/skin/skin_token.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

// Pages and tokens are always used together; keep one import for both.
export 'package:vaultexplorer/core/theme/skin/skin_token.dart';

/// A page (or family of pages) that owns an independent set of skin colors.
///
/// Anything not listed here (unlock, camera, authenticator, ...) simply uses
/// the skin's shared palette.
enum SkinArea {
  dashboard,
  drawer,
  files,
  editor,
  tools,
  settings;

  String get id => name;

  static SkinArea? tryParse(Object? value) {
    for (final area in SkinArea.values) {
      if (area.name == value) return area;
    }
    return null;
  }

  String label(AppLocalizations l10n) => switch (this) {
    SkinArea.dashboard => l10n.skinAreaDashboard,
    SkinArea.drawer => l10n.skinAreaDrawer,
    SkinArea.files => l10n.filesTabLabel,
    SkinArea.editor => l10n.skinEditor,
    SkinArea.tools => l10n.navBarToolsLabel,
    SkinArea.settings => l10n.settingsTooltip,
  };

  String description(AppLocalizations l10n) => switch (this) {
    SkinArea.dashboard => l10n.skinAreaDashboardDescription,
    SkinArea.drawer => l10n.skinAreaDrawerDescription,
    SkinArea.files => l10n.skinAreaFilesDescription,
    SkinArea.editor => l10n.skinAreaEditorDescription,
    SkinArea.tools => l10n.skinAreaToolsDescription,
    SkinArea.settings => l10n.skinAreaSettingsDescription,
  };

  /// The colors this page exposes in the skin editor, in display order (grouped
  /// by [SkinToken.group]). Every token a page does not list still resolves
  /// (from the shared palette) but is not editable for that page.
  List<SkinToken> get tokens => switch (this) {
    SkinArea.dashboard => _tokensOf(),
    SkinArea.files => _tokensOf(without: _cardActiveOnly),
    SkinArea.tools || SkinArea.settings => _tokensOf(
      without: _cardActiveAndFab,
    ),
    // The side menu has no top bar, round add button or vault card; everything
    // else it can show (rows, switches, chips, menus, dialogs, messages) is
    // editable.
    SkinArea.drawer => _tokensOf(without: _drawerExcluded),
    // The editor's canvas, syntax and gutter colors live in the editor color
    // map; only the toolbar belongs to the per-page token set.
    SkinArea.editor => const [SkinToken.chromeTopBar, SkinToken.chromeOnTopBar],
  };
}

const _cardActiveOnly = {SkinToken.surfaceCardActive};
const _cardActiveAndFab = {
  SkinToken.surfaceCardActive,
  SkinToken.floatingFab,
  SkinToken.floatingOnFab,
};
const _drawerExcluded = {
  SkinToken.surfaceCardActive,
  SkinToken.chromeTopBar,
  SkinToken.chromeOnTopBar,
  SkinToken.floatingFab,
  SkinToken.floatingOnFab,
};

List<SkinToken> _tokensOf({Set<SkinToken> without = const {}}) => [
  for (final token in SkinToken.values)
    if (!without.contains(token)) token,
];
