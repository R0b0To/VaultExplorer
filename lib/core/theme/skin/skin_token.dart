import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// What a token is *for*. Tokens are grouped by the job a color does in the
/// interface (a surface, text, a border, a button, ...), never by the Material
/// color role it happens to be painted from. The skin editor lists a page's
/// tokens under these headings.
enum SkinTokenGroup {
  surface,
  content,
  border,
  chrome,
  action,
  control,
  choice,
  selection,
  overlay,
  floating;

  String get id => name;

  String label(AppLocalizations l10n) => switch (this) {
    SkinTokenGroup.surface => l10n.skinTokenGroupSurface,
    SkinTokenGroup.content => l10n.skinTokenGroupContent,
    SkinTokenGroup.border => l10n.skinTokenGroupBorder,
    SkinTokenGroup.chrome => l10n.skinTokenGroupChrome,
    SkinTokenGroup.action => l10n.skinTokenGroupAction,
    SkinTokenGroup.control => l10n.skinTokenGroupControl,
    SkinTokenGroup.choice => l10n.skinTokenGroupChoice,
    SkinTokenGroup.selection => l10n.skinTokenGroupSelection,
    SkinTokenGroup.overlay => l10n.skinTokenGroupOverlay,
    SkinTokenGroup.floating => l10n.skinTokenGroupFloating,
  };
}

/// The vocabulary shared by every page. Each token is stored per page, so
/// changing `surface.card` on Tools never touches Files or the Dashboard.
///
/// Rules this vocabulary keeps:
///  * One token = one job. Where several components used to share one color
///    they now have a token each (`surface.field`, `action.tonal`,
///    `choice.background` and `overlay.dialog` all *default* to the same
///    palette step as `surface.card`, but are edited independently of it).
///  * Defaults come from the shared palette, never from another token. The one
///    documented exception is `surface.cardActive`, which blends
///    `selection.fill` into `surface.card`.
///  * `on*` tokens are the text/icon color drawn on the token they follow.
///
/// [id] is the stable, dotted storage key (`group.name`).
enum SkinToken {
  surfacePage('surface.page', SkinTokenGroup.surface),
  surfaceCard('surface.card', SkinTokenGroup.surface),
  surfaceCardActive('surface.cardActive', SkinTokenGroup.surface),
  surfaceTile('surface.tile', SkinTokenGroup.surface),
  surfaceField('surface.field', SkinTokenGroup.surface),
  contentPrimary('content.primary', SkinTokenGroup.content),
  contentSecondary('content.secondary', SkinTokenGroup.content),
  contentIcon('content.icon', SkinTokenGroup.content),
  borderDivider('border.divider', SkinTokenGroup.border),
  borderOutline('border.outline', SkinTokenGroup.border),
  borderFocus('border.focus', SkinTokenGroup.border),
  chromeTopBar('chrome.topBar', SkinTokenGroup.chrome),
  chromeOnTopBar('chrome.onTopBar', SkinTokenGroup.chrome),
  actionPrimary('action.primary', SkinTokenGroup.action),
  actionOnPrimary('action.onPrimary', SkinTokenGroup.action),
  actionTonal('action.tonal', SkinTokenGroup.action),
  actionOnTonal('action.onTonal', SkinTokenGroup.action),
  actionText('action.text', SkinTokenGroup.action),
  controlActive('control.active', SkinTokenGroup.control),
  controlOnActive('control.onActive', SkinTokenGroup.control),
  controlTrack('control.track', SkinTokenGroup.control),
  controlInactive('control.inactive', SkinTokenGroup.control),
  choiceBackground('choice.background', SkinTokenGroup.choice),
  choiceSelected('choice.selected', SkinTokenGroup.choice),
  choiceOnSelected('choice.onSelected', SkinTokenGroup.choice),
  choiceBorder('choice.border', SkinTokenGroup.choice),
  selectionFill('selection.fill', SkinTokenGroup.selection),
  selectionOn('selection.on', SkinTokenGroup.selection),
  overlayMenu('overlay.menu', SkinTokenGroup.overlay),
  overlayOnMenu('overlay.onMenu', SkinTokenGroup.overlay),
  overlayDialog('overlay.dialog', SkinTokenGroup.overlay),
  overlayOnDialog('overlay.onDialog', SkinTokenGroup.overlay),
  overlaySheet('overlay.sheet', SkinTokenGroup.overlay),
  overlayOnSheet('overlay.onSheet', SkinTokenGroup.overlay),
  overlayScrim('overlay.scrim', SkinTokenGroup.overlay),
  floatingFab('floating.fab', SkinTokenGroup.floating),
  floatingOnFab('floating.onFab', SkinTokenGroup.floating),
  floatingToast('floating.toast', SkinTokenGroup.floating),
  floatingOnToast('floating.onToast', SkinTokenGroup.floating),
  floatingTooltip('floating.tooltip', SkinTokenGroup.floating),
  floatingOnTooltip('floating.onTooltip', SkinTokenGroup.floating);

  const SkinToken(this.id, this.group);

  final String id;
  final SkinTokenGroup group;

  static SkinToken? tryParse(Object? value) {
    for (final token in SkinToken.values) {
      if (token.id == value) return token;
    }
    return null;
  }

  /// The tokens a pre-split key (`card`, `accent`, ...) used to drive. Loading
  /// an old skin copies the old value onto each of them, so the skin looks
  /// identical afterwards but every token can now be edited on its own.
  /// Empty for a key that was never part of the old vocabulary.
  static List<SkinToken> fromLegacyId(Object? value) =>
      _legacyFanOut[value] ?? const <SkinToken>[];

  /// Legacy keys in the order they are applied; a later key wins where two of
  /// them fan out to the same token (`overlay` beats `card` for dialogs).
  static const List<String> legacyIdsInApplyOrder = ['background', 'text', 'textSecondary', 'appBar', 'onAppBar', 'card', 'cardActive', 'raised', 'accent', 'onAccent', 'selection', 'onSelection', 'divider', 'outline', 'fab', 'onFab', 'overlay'];

  String label(AppLocalizations l10n) => switch (this) {
    SkinToken.surfacePage => l10n.skinTokenSurfacePage,
    SkinToken.surfaceCard => l10n.skinTokenSurfaceCard,
    SkinToken.surfaceCardActive => l10n.skinTokenSurfaceCardActive,
    SkinToken.surfaceTile => l10n.skinTokenSurfaceTile,
    SkinToken.surfaceField => l10n.skinTokenSurfaceField,
    SkinToken.contentPrimary => l10n.skinTokenContentPrimary,
    SkinToken.contentSecondary => l10n.skinTokenContentSecondary,
    SkinToken.contentIcon => l10n.skinTokenContentIcon,
    SkinToken.borderDivider => l10n.skinTokenBorderDivider,
    SkinToken.borderOutline => l10n.skinTokenBorderOutline,
    SkinToken.borderFocus => l10n.skinTokenBorderFocus,
    SkinToken.chromeTopBar => l10n.skinTokenChromeTopBar,
    SkinToken.chromeOnTopBar => l10n.skinTokenChromeOnTopBar,
    SkinToken.actionPrimary => l10n.skinTokenActionPrimary,
    SkinToken.actionOnPrimary => l10n.skinTokenActionOnPrimary,
    SkinToken.actionTonal => l10n.skinTokenActionTonal,
    SkinToken.actionOnTonal => l10n.skinTokenActionOnTonal,
    SkinToken.actionText => l10n.skinTokenActionText,
    SkinToken.controlActive => l10n.skinTokenControlActive,
    SkinToken.controlOnActive => l10n.skinTokenControlOnActive,
    SkinToken.controlTrack => l10n.skinTokenControlTrack,
    SkinToken.controlInactive => l10n.skinTokenControlInactive,
    SkinToken.choiceBackground => l10n.skinTokenChoiceBackground,
    SkinToken.choiceSelected => l10n.skinTokenChoiceSelected,
    SkinToken.choiceOnSelected => l10n.skinTokenChoiceOnSelected,
    SkinToken.choiceBorder => l10n.skinTokenChoiceBorder,
    SkinToken.selectionFill => l10n.skinTokenSelectionFill,
    SkinToken.selectionOn => l10n.skinTokenSelectionOn,
    SkinToken.overlayMenu => l10n.skinTokenOverlayMenu,
    SkinToken.overlayOnMenu => l10n.skinTokenOverlayOnMenu,
    SkinToken.overlayDialog => l10n.skinTokenOverlayDialog,
    SkinToken.overlayOnDialog => l10n.skinTokenOverlayOnDialog,
    SkinToken.overlaySheet => l10n.skinTokenOverlaySheet,
    SkinToken.overlayOnSheet => l10n.skinTokenOverlayOnSheet,
    SkinToken.overlayScrim => l10n.skinTokenOverlayScrim,
    SkinToken.floatingFab => l10n.skinTokenFloatingFab,
    SkinToken.floatingOnFab => l10n.skinTokenFloatingOnFab,
    SkinToken.floatingToast => l10n.skinTokenFloatingToast,
    SkinToken.floatingOnToast => l10n.skinTokenFloatingOnToast,
    SkinToken.floatingTooltip => l10n.skinTokenFloatingTooltip,
    SkinToken.floatingOnTooltip => l10n.skinTokenFloatingOnTooltip,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    SkinToken.surfacePage => l10n.skinTokenSurfacePageHint,
    SkinToken.surfaceCard => l10n.skinTokenSurfaceCardHint,
    SkinToken.surfaceCardActive => l10n.skinTokenSurfaceCardActiveHint,
    SkinToken.surfaceTile => l10n.skinTokenSurfaceTileHint,
    SkinToken.surfaceField => l10n.skinTokenSurfaceFieldHint,
    SkinToken.contentPrimary => l10n.skinTokenContentPrimaryHint,
    SkinToken.contentSecondary => l10n.skinTokenContentSecondaryHint,
    SkinToken.contentIcon => l10n.skinTokenContentIconHint,
    SkinToken.borderDivider => l10n.skinTokenBorderDividerHint,
    SkinToken.borderOutline => l10n.skinTokenBorderOutlineHint,
    SkinToken.borderFocus => l10n.skinTokenBorderFocusHint,
    SkinToken.chromeTopBar => l10n.skinTokenChromeTopBarHint,
    SkinToken.chromeOnTopBar => l10n.skinTokenChromeOnTopBarHint,
    SkinToken.actionPrimary => l10n.skinTokenActionPrimaryHint,
    SkinToken.actionOnPrimary => l10n.skinTokenActionOnPrimaryHint,
    SkinToken.actionTonal => l10n.skinTokenActionTonalHint,
    SkinToken.actionOnTonal => l10n.skinTokenActionOnTonalHint,
    SkinToken.actionText => l10n.skinTokenActionTextHint,
    SkinToken.controlActive => l10n.skinTokenControlActiveHint,
    SkinToken.controlOnActive => l10n.skinTokenControlOnActiveHint,
    SkinToken.controlTrack => l10n.skinTokenControlTrackHint,
    SkinToken.controlInactive => l10n.skinTokenControlInactiveHint,
    SkinToken.choiceBackground => l10n.skinTokenChoiceBackgroundHint,
    SkinToken.choiceSelected => l10n.skinTokenChoiceSelectedHint,
    SkinToken.choiceOnSelected => l10n.skinTokenChoiceOnSelectedHint,
    SkinToken.choiceBorder => l10n.skinTokenChoiceBorderHint,
    SkinToken.selectionFill => l10n.skinTokenSelectionFillHint,
    SkinToken.selectionOn => l10n.skinTokenSelectionOnHint,
    SkinToken.overlayMenu => l10n.skinTokenOverlayMenuHint,
    SkinToken.overlayOnMenu => l10n.skinTokenOverlayOnMenuHint,
    SkinToken.overlayDialog => l10n.skinTokenOverlayDialogHint,
    SkinToken.overlayOnDialog => l10n.skinTokenOverlayOnDialogHint,
    SkinToken.overlaySheet => l10n.skinTokenOverlaySheetHint,
    SkinToken.overlayOnSheet => l10n.skinTokenOverlayOnSheetHint,
    SkinToken.overlayScrim => l10n.skinTokenOverlayScrimHint,
    SkinToken.floatingFab => l10n.skinTokenFloatingFabHint,
    SkinToken.floatingOnFab => l10n.skinTokenFloatingOnFabHint,
    SkinToken.floatingToast => l10n.skinTokenFloatingToastHint,
    SkinToken.floatingOnToast => l10n.skinTokenFloatingOnToastHint,
    SkinToken.floatingTooltip => l10n.skinTokenFloatingTooltipHint,
    SkinToken.floatingOnTooltip => l10n.skinTokenFloatingOnTooltipHint,
  };
}

const Map<String, List<SkinToken>> _legacyFanOut = {
  'background': [SkinToken.surfacePage],
  'text': [SkinToken.contentPrimary, SkinToken.overlayOnMenu, SkinToken.overlayOnDialog, SkinToken.overlayOnSheet],
  'textSecondary': [SkinToken.contentSecondary, SkinToken.contentIcon],
  'appBar': [SkinToken.chromeTopBar],
  'onAppBar': [SkinToken.chromeOnTopBar],
  'card': [SkinToken.surfaceCard, SkinToken.surfaceField, SkinToken.actionTonal, SkinToken.choiceBackground, SkinToken.overlayDialog],
  'cardActive': [SkinToken.surfaceCardActive],
  'raised': [SkinToken.surfaceTile, SkinToken.controlTrack],
  'accent': [SkinToken.borderFocus, SkinToken.actionPrimary, SkinToken.actionOnTonal, SkinToken.actionText, SkinToken.controlActive],
  'onAccent': [SkinToken.actionOnPrimary, SkinToken.controlOnActive],
  'selection': [SkinToken.selectionFill],
  'onSelection': [SkinToken.selectionOn],
  'divider': [SkinToken.borderDivider, SkinToken.choiceBorder],
  'outline': [SkinToken.borderOutline, SkinToken.controlInactive],
  'fab': [SkinToken.floatingFab],
  'onFab': [SkinToken.floatingOnFab],
  'overlay': [SkinToken.overlayMenu, SkinToken.overlayDialog, SkinToken.overlaySheet],
};
