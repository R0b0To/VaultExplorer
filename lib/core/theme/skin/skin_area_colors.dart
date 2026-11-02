import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';

/// The fully resolved colors of one page.
///
/// Every token always has a value: the page's own override when the skin sets
/// one, otherwise a value derived from the skin's shared palette. [custom]
/// records which tokens came from an override, so the skin editor can show
/// "custom" versus "inherited" and offer a reset.
@immutable
class SkinAreaColors {
  final SkinArea area;
  final Map<SkinToken, Color> colors;
  final Set<SkinToken> custom;

  const SkinAreaColors({
    required this.area,
    required this.colors,
    required this.custom,
  });

  Color color(SkinToken token) => colors[token] ?? const Color(0x00000000);

  Color operator [](SkinToken token) => color(token);

  bool isCustom(SkinToken token) => custom.contains(token);

  static SkinAreaColors lerp(SkinAreaColors a, SkinAreaColors b, double t) {
    final discrete = t < 0.5 ? a : b;
    return SkinAreaColors(
      area: discrete.area,
      colors: {
        for (final token in SkinToken.values)
          token: Color.lerp(a.color(token), b.color(token), t)!,
      },
      custom: discrete.custom,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkinAreaColors &&
          area == other.area &&
          mapEquals(colors, other.colors) &&
          setEquals(custom, other.custom);

  @override
  int get hashCode => Object.hash(
    area,
    Object.hashAll(
      SkinToken.values.map((token) => Object.hash(token, colors[token])),
    ),
    Object.hashAllUnordered(custom),
  );
}

/// Resolves every page's colors from the shared palette.
///
/// [overrideFor] returns the skin's own color for a page token, or null to
/// inherit. Only tokens a page actually exposes ([SkinArea.tokens]) are
/// consulted, so stale data for a token a page does not use is ignored.
///
/// With no overrides every page resolves to exactly what the shared palette
/// already produced, so a skin that never customizes a page looks the same as
/// it did before pages had colors of their own.
Map<SkinArea, SkinAreaColors> resolveSkinAreaColors({
  required ColorScheme scheme,
  required Color appBar,
  required Color onAppBar,
  required Color fab,
  required Color onFab,
  Color? Function(SkinArea area, SkinToken token)? overrideFor,
}) => {
  for (final area in SkinArea.values)
    area: _resolveArea(
      area: area,
      scheme: scheme,
      appBar: appBar,
      onAppBar: onAppBar,
      fab: fab,
      onFab: onFab,
      overrideFor: overrideFor,
    ),
};

/// The tokens of a page that has no overrides and no scheme remapping: what
/// the app theme itself (outside any [SkinArea]) is built from.
SkinAreaColors resolveSharedSkinColors({
  required ColorScheme scheme,
  required Color appBar,
  required Color onAppBar,
  required Color fab,
  required Color onFab,
}) => _resolveArea(
  area: SkinArea.settings,
  scheme: scheme,
  appBar: appBar,
  onAppBar: onAppBar,
  fab: fab,
  onFab: onFab,
  overrideFor: null,
);

SkinAreaColors _resolveArea({
  required SkinArea area,
  required ColorScheme scheme,
  required Color appBar,
  required Color onAppBar,
  required Color fab,
  required Color onFab,
  required Color? Function(SkinArea area, SkinToken token)? overrideFor,
}) {
  final custom = <SkinToken>{};
  final exposed = area.tokens.toSet();

  Color pick(SkinToken token, Color fallback) {
    if (overrideFor == null || !exposed.contains(token)) return fallback;
    final value = overrideFor(area, token);
    if (value == null) return fallback;
    custom.add(token);
    return value;
  }

  final s = scheme;
  final isDrawer = area == SkinArea.drawer;
  final isDark = s.brightness == Brightness.dark;

  // Every default below comes straight from the shared palette, so two tokens
  // that start out the same color (card / field / dialog / chip ...) stay
  // independent: moving one never moves another. The surfaces that used to be
  // lerped between background and card no longer exist; menus, sheets and
  // dialogs have tokens of their own.
  final defaults = <SkinToken, Color>{
    SkinToken.surfacePage: isDrawer ? s.surfaceContainerLow : s.surface,
    SkinToken.surfaceCard: s.surfaceContainerHigh,
    SkinToken.surfaceTile: s.surfaceContainerHighest,
    SkinToken.surfacePanel: s.surfaceContainerLow,
    SkinToken.surfaceField: s.surfaceContainerHigh,
    SkinToken.contentPrimary: s.onSurface,
    SkinToken.contentSecondary: s.onSurfaceVariant,
    SkinToken.contentIcon: s.onSurfaceVariant,
    SkinToken.borderDivider: s.outlineVariant,
    SkinToken.borderOutline: s.outline,
    SkinToken.borderFocus: s.primary,
    SkinToken.chromeTopBar: appBar,
    SkinToken.chromeOnTopBar: onAppBar,
    SkinToken.chromeBar: s.surfaceContainer,
    SkinToken.accentPrimary: s.primary,
    SkinToken.accentSecondary: s.secondary,
    SkinToken.accentTertiary: s.tertiary,
    SkinToken.accentTertiaryContainer: s.tertiaryContainer,
    SkinToken.accentOnTertiaryContainer: s.onTertiaryContainer,
    SkinToken.actionPrimary: s.primary,
    SkinToken.actionOnPrimary: s.onPrimary,
    SkinToken.actionTonal: s.surfaceContainerHigh,
    SkinToken.actionOnTonal: s.primary,
    SkinToken.actionText: s.primary,
    SkinToken.controlActive: s.primary,
    SkinToken.controlOnActive: s.onPrimary,
    SkinToken.controlTrack: s.surfaceContainerHighest,
    SkinToken.controlInactive: s.outline,
    SkinToken.choiceBackground: s.surfaceContainerHigh,
    SkinToken.choiceSelected: s.secondaryContainer,
    SkinToken.choiceOnSelected: s.onSecondaryContainer,
    SkinToken.choiceBorder: s.outlineVariant,
    SkinToken.selectionFill: isDrawer
        ? s.secondaryContainer
        : s.primaryContainer,
    SkinToken.selectionOn: isDrawer
        ? s.onSecondaryContainer
        : s.onPrimaryContainer,
    SkinToken.statusDanger: s.error,
    SkinToken.statusOnDanger: s.onError,
    SkinToken.statusDangerContainer: s.errorContainer,
    SkinToken.statusOnDangerContainer: s.onErrorContainer,
    SkinToken.statusInfo: s.secondaryContainer,
    SkinToken.statusOnInfo: s.onSecondaryContainer,
    SkinToken.overlayMenu: s.surfaceContainer,
    SkinToken.overlayOnMenu: s.onSurface,
    SkinToken.overlayDialog: s.surfaceContainerHigh,
    SkinToken.overlayOnDialog: s.onSurface,
    SkinToken.overlaySheet: s.surfaceContainerLow,
    SkinToken.overlayOnSheet: s.onSurface,
    SkinToken.overlayScrim: s.scrim,
    SkinToken.floatingFab: fab,
    SkinToken.floatingOnFab: onFab,
    SkinToken.floatingToast: s.inverseSurface,
    SkinToken.floatingOnToast: s.onInverseSurface,
    SkinToken.floatingTooltip: s.inverseSurface,
    SkinToken.floatingOnTooltip: s.onInverseSurface,
  };

  final colors = <SkinToken, Color>{};
  for (final token in SkinToken.values) {
    if (token == SkinToken.surfaceCardActive) continue;
    colors[token] = pick(token, defaults[token]!);
  }
  // The one derived default: the "active" card (an unlocked vault) is the card
  // tinted toward the page's selection color, unless the skin sets it.
  colors[SkinToken.surfaceCardActive] = pick(
    SkinToken.surfaceCardActive,
    Color.alphaBlend(
      colors[SkinToken.selectionFill]!.withValues(alpha: isDark ? 0.35 : 0.55),
      colors[SkinToken.surfaceCard]!,
    ),
  );

  return SkinAreaColors(area: area, colors: colors, custom: custom);
}

/// Re-maps a page's tokens onto Material color roles.
///
/// This is a compatibility bridge, not the way new code should read colors.
/// Component themes (see `buildSkinAreaTheme`) are built from the tokens
/// directly, so a switch, chip, dialog or text field no longer depends on what
/// is painted with the matching Material role. The bridge only keeps widgets
/// that still read `Theme.of(context).colorScheme.*` by hand following *one*
/// clearly named token per role:
///
///   surface -> surface.page            surfaceContainer -> chrome.bar
///   surfaceContainerLow -> surface.panel
///   surfaceContainerHigh -> surface.card
///   surfaceContainerHighest -> surface.tile
///   onSurface -> content.primary       onSurfaceVariant -> content.secondary
///   primary -> accent.primary          onPrimary -> action.onPrimary
///   secondary -> accent.secondary      tertiary -> accent.tertiary
///   tertiaryContainer pair -> accent.tertiaryContainer / accent.onTertiaryContainer
///   error / onError -> status.danger / status.onDanger
///   errorContainer pair -> status.dangerContainer / status.onDangerContainer
///   outline / outlineVariant -> border.outline / border.divider
///   inverseSurface pair -> floating.toast / floating.onToast
///   primaryContainer pair -> selection.fill / selection.on
///   secondaryContainer pair -> choice.selected / choice.onSelected
///   (the side menu maps secondaryContainer to selection.fill / selection.on)
///
/// Note `primary` follows `accent.primary`, not `action.primary`: buttons read
/// their own tokens, so recoloring the filled button no longer recolors the
/// hundreds of hand-painted accents. Migrate a direct read to
/// `SkinAreaScope.colorOf` (or a component theme) when it needs to follow a
/// different token than the one above.
ColorScheme applySkinAreaToScheme(ColorScheme base, SkinAreaColors area) {
  // The side menu's default fill is a step above the page surface; leave the
  // surface role alone there unless the skin actually sets the menu's fill.
  final keepSurface =
      area.area == SkinArea.drawer && !area.isCustom(SkinToken.surfacePage);
  final scheme = base.copyWith(
    surface: keepSurface ? base.surface : area.color(SkinToken.surfacePage),
    surfaceContainer: area.color(SkinToken.chromeBar),
    surfaceContainerLow: area.color(SkinToken.surfacePanel),
    surfaceContainerHigh: area.color(SkinToken.surfaceCard),
    surfaceContainerHighest: area.color(SkinToken.surfaceTile),
    onSurface: area.color(SkinToken.contentPrimary),
    onSurfaceVariant: area.color(SkinToken.contentSecondary),
    primary: area.color(SkinToken.accentPrimary),
    onPrimary: area.color(SkinToken.actionOnPrimary),
    secondary: area.color(SkinToken.accentSecondary),
    tertiary: area.color(SkinToken.accentTertiary),
    tertiaryContainer: area.color(SkinToken.accentTertiaryContainer),
    onTertiaryContainer: area.color(SkinToken.accentOnTertiaryContainer),
    error: area.color(SkinToken.statusDanger),
    onError: area.color(SkinToken.statusOnDanger),
    errorContainer: area.color(SkinToken.statusDangerContainer),
    onErrorContainer: area.color(SkinToken.statusOnDangerContainer),
    outline: area.color(SkinToken.borderOutline),
    outlineVariant: area.color(SkinToken.borderDivider),
    inverseSurface: area.color(SkinToken.floatingToast),
    onInverseSurface: area.color(SkinToken.floatingOnToast),
  );
  if (area.area == SkinArea.drawer) {
    return scheme.copyWith(
      secondaryContainer: area.color(SkinToken.selectionFill),
      onSecondaryContainer: area.color(SkinToken.selectionOn),
    );
  }
  return scheme.copyWith(
    primaryContainer: area.color(SkinToken.selectionFill),
    onPrimaryContainer: area.color(SkinToken.selectionOn),
    secondaryContainer: area.color(SkinToken.choiceSelected),
    onSecondaryContainer: area.color(SkinToken.choiceOnSelected),
  );
}
