import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

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

  /// The colors this page exposes in the skin editor, in display order. Every
  /// token a page does not list still resolves (from the shared palette) but
  /// is not editable for that page.
  List<SkinToken> get tokens => switch (this) {
    SkinArea.dashboard => const [
      SkinToken.background,
      SkinToken.text,
      SkinToken.textSecondary,
      SkinToken.appBar,
      SkinToken.onAppBar,
      SkinToken.card,
      SkinToken.cardActive,
      SkinToken.raised,
      SkinToken.overlay,
      SkinToken.accent,
      SkinToken.onAccent,
      SkinToken.selection,
      SkinToken.onSelection,
      SkinToken.divider,
      SkinToken.fab,
      SkinToken.onFab,
    ],
    SkinArea.drawer => const [
      SkinToken.background,
      SkinToken.text,
      SkinToken.textSecondary,
      SkinToken.card,
      SkinToken.raised,
      SkinToken.accent,
      SkinToken.selection,
      SkinToken.onSelection,
      SkinToken.divider,
    ],
    SkinArea.files => const [
      SkinToken.background,
      SkinToken.text,
      SkinToken.textSecondary,
      SkinToken.appBar,
      SkinToken.onAppBar,
      SkinToken.card,
      SkinToken.raised,
      SkinToken.overlay,
      SkinToken.accent,
      SkinToken.onAccent,
      SkinToken.selection,
      SkinToken.onSelection,
      SkinToken.divider,
      SkinToken.outline,
      SkinToken.fab,
      SkinToken.onFab,
    ],
    // The editor's canvas, syntax and gutter colors live in the editor color
    // map; only the toolbar belongs to the per-page token set.
    SkinArea.editor => const [SkinToken.appBar, SkinToken.onAppBar],
    SkinArea.tools || SkinArea.settings => const [
      SkinToken.background,
      SkinToken.text,
      SkinToken.textSecondary,
      SkinToken.appBar,
      SkinToken.onAppBar,
      SkinToken.card,
      SkinToken.raised,
      SkinToken.overlay,
      SkinToken.accent,
      SkinToken.onAccent,
      SkinToken.selection,
      SkinToken.onSelection,
      SkinToken.divider,
      SkinToken.outline,
    ],
  };
}

/// The vocabulary shared by every page. Each token is stored per page, so
/// changing "Cards & rows" on Tools never touches Files or the Dashboard.
enum SkinToken {
  background,
  text,
  textSecondary,
  appBar,
  onAppBar,
  card,
  cardActive,
  raised,
  overlay,
  accent,
  onAccent,
  selection,
  onSelection,
  divider,
  outline,
  fab,
  onFab;

  String get id => name;

  static SkinToken? tryParse(Object? value) {
    for (final token in SkinToken.values) {
      if (token.name == value) return token;
    }
    return null;
  }

  String label(AppLocalizations l10n) => switch (this) {
    SkinToken.background => l10n.skinTokenBackground,
    SkinToken.text => l10n.skinTokenText,
    SkinToken.textSecondary => l10n.skinTokenTextSecondary,
    SkinToken.appBar => l10n.skinTokenAppBar,
    SkinToken.onAppBar => l10n.skinTokenOnAppBar,
    SkinToken.card => l10n.skinTokenCard,
    SkinToken.cardActive => l10n.skinTokenCardActive,
    SkinToken.raised => l10n.skinTokenRaised,
    SkinToken.overlay => l10n.skinTokenOverlay,
    SkinToken.accent => l10n.skinTokenAccent,
    SkinToken.onAccent => l10n.skinTokenOnAccent,
    SkinToken.selection => l10n.skinTokenSelection,
    SkinToken.onSelection => l10n.skinTokenOnSelection,
    SkinToken.divider => l10n.skinTokenDivider,
    SkinToken.outline => l10n.skinTokenOutline,
    SkinToken.fab => l10n.skinTokenFab,
    SkinToken.onFab => l10n.skinTokenOnFab,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    SkinToken.background => l10n.skinTokenBackgroundHint,
    SkinToken.text => l10n.skinTokenTextHint,
    SkinToken.textSecondary => l10n.skinTokenTextSecondaryHint,
    SkinToken.appBar => l10n.skinTokenAppBarHint,
    SkinToken.onAppBar => l10n.skinTokenOnAppBarHint,
    SkinToken.card => l10n.skinTokenCardHint,
    SkinToken.cardActive => l10n.skinTokenCardActiveHint,
    SkinToken.raised => l10n.skinTokenRaisedHint,
    SkinToken.overlay => l10n.skinTokenOverlayHint,
    SkinToken.accent => l10n.skinTokenAccentHint,
    SkinToken.onAccent => l10n.skinTokenOnAccentHint,
    SkinToken.selection => l10n.skinTokenSelectionHint,
    SkinToken.onSelection => l10n.skinTokenOnSelectionHint,
    SkinToken.divider => l10n.skinTokenDividerHint,
    SkinToken.outline => l10n.skinTokenOutlineHint,
    SkinToken.fab => l10n.skinTokenFabHint,
    SkinToken.onFab => l10n.skinTokenOnFabHint,
  };
}
