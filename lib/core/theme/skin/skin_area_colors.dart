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

  /// The three surface steps between the page background and [SkinToken.card].
  /// They follow the page automatically, so customizing a page background does
  /// not leave half of its surfaces on the old ramp.
  final Color surfaceLowest;
  final Color surfaceLow;
  final Color surfaceMid;

  const SkinAreaColors({
    required this.area,
    required this.colors,
    required this.custom,
    required this.surfaceLowest,
    required this.surfaceLow,
    required this.surfaceMid,
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
      surfaceLowest: Color.lerp(a.surfaceLowest, b.surfaceLowest, t)!,
      surfaceLow: Color.lerp(a.surfaceLow, b.surfaceLow, t)!,
      surfaceMid: Color.lerp(a.surfaceMid, b.surfaceMid, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkinAreaColors &&
          area == other.area &&
          mapEquals(colors, other.colors) &&
          setEquals(custom, other.custom) &&
          surfaceLowest == other.surfaceLowest &&
          surfaceLow == other.surfaceLow &&
          surfaceMid == other.surfaceMid;

  @override
  int get hashCode => Object.hash(
    area,
    Object.hashAll(
      SkinToken.values.map((token) => Object.hash(token, colors[token])),
    ),
    Object.hashAllUnordered(custom),
    surfaceLowest,
    surfaceLow,
    surfaceMid,
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
  final exposed = area.tokens;

  Color pick(SkinToken token, Color fallback) {
    if (overrideFor == null || !exposed.contains(token)) return fallback;
    final value = overrideFor(area, token);
    if (value == null) return fallback;
    custom.add(token);
    return value;
  }

  final isDrawer = area == SkinArea.drawer;
  final isDark = scheme.brightness == Brightness.dark;
  final defaultBackground = isDrawer
      ? scheme.surfaceContainerLow
      : scheme.surface;

  final background = pick(SkinToken.background, defaultBackground);
  final card = pick(SkinToken.card, scheme.surfaceContainerHigh);

  // Only regenerate the surface ramp when the page really moved its
  // background or card color; otherwise keep the palette's own steps.
  final surfacesMoved =
      background != defaultBackground || card != scheme.surfaceContainerHigh;
  Color step(double t, Color paletteStep) =>
      surfacesMoved ? Color.lerp(background, card, t)! : paletteStep;

  final surfaceLowest = step(-0.25, scheme.surfaceContainerLowest);
  final surfaceLow = step(0.35, scheme.surfaceContainerLow);
  final surfaceMid = step(0.6, scheme.surfaceContainer);

  final selection = pick(
    SkinToken.selection,
    isDrawer ? scheme.secondaryContainer : scheme.primaryContainer,
  );
  final onSelection = pick(
    SkinToken.onSelection,
    isDrawer ? scheme.onSecondaryContainer : scheme.onPrimaryContainer,
  );

  final colors = <SkinToken, Color>{
    SkinToken.background: background,
    SkinToken.text: pick(SkinToken.text, scheme.onSurface),
    SkinToken.textSecondary: pick(
      SkinToken.textSecondary,
      scheme.onSurfaceVariant,
    ),
    SkinToken.appBar: pick(SkinToken.appBar, appBar),
    SkinToken.onAppBar: pick(SkinToken.onAppBar, onAppBar),
    SkinToken.card: card,
    SkinToken.raised: pick(
      SkinToken.raised,
      step(1.5, scheme.surfaceContainerHighest),
    ),
    SkinToken.overlay: pick(SkinToken.overlay, scheme.surfaceContainer),
    SkinToken.accent: pick(SkinToken.accent, scheme.primary),
    SkinToken.onAccent: pick(SkinToken.onAccent, scheme.onPrimary),
    SkinToken.selection: selection,
    SkinToken.onSelection: onSelection,
    SkinToken.divider: pick(SkinToken.divider, scheme.outlineVariant),
    SkinToken.outline: pick(SkinToken.outline, scheme.outline),
    SkinToken.fab: pick(SkinToken.fab, fab),
    SkinToken.onFab: pick(SkinToken.onFab, onFab),
  };

  // The "active" card (an unlocked vault) is the card tinted toward the
  // page's selection color, exactly as before unless the skin overrides it.
  colors[SkinToken.cardActive] = pick(
    SkinToken.cardActive,
    Color.alphaBlend(
      selection.withValues(alpha: isDark ? 0.35 : 0.55),
      card,
    ),
  );

  return SkinAreaColors(
    area: area,
    colors: colors,
    custom: custom,
    surfaceLowest: surfaceLowest,
    surfaceLow: surfaceLow,
    surfaceMid: surfaceMid,
  );
}

/// Re-maps a page's tokens onto Material color roles.
///
/// This is what lets a page's existing widgets (which read
/// `Theme.of(context).colorScheme.*`) pick up the page's own colors without
/// every widget being rewritten: inside a [SkinArea] the roles *are* that
/// page's tokens.
ColorScheme applySkinAreaToScheme(ColorScheme base, SkinAreaColors area) {
  // The side menu's default fill is a step above the page surface; leave the
  // surface role alone there unless the skin actually sets the menu's fill.
  final keepSurface =
      area.area == SkinArea.drawer && !area.isCustom(SkinToken.background);
  final scheme = base.copyWith(
    surface: keepSurface ? base.surface : area.color(SkinToken.background),
    onSurface: area.color(SkinToken.text),
    onSurfaceVariant: area.color(SkinToken.textSecondary),
    surfaceContainerLowest: area.surfaceLowest,
    surfaceContainerLow: area.surfaceLow,
    surfaceContainer: area.surfaceMid,
    surfaceContainerHigh: area.color(SkinToken.card),
    surfaceContainerHighest: area.color(SkinToken.raised),
    primary: area.color(SkinToken.accent),
    onPrimary: area.color(SkinToken.onAccent),
    outline: area.color(SkinToken.outline),
    outlineVariant: area.color(SkinToken.divider),
  );
  // The side menu highlights its current destination with the secondary
  // container; every other page uses the primary container for selection.
  if (area.area == SkinArea.drawer) {
    return scheme.copyWith(
      secondaryContainer: area.color(SkinToken.selection),
      onSecondaryContainer: area.color(SkinToken.onSelection),
    );
  }
  return scheme.copyWith(
    primaryContainer: area.color(SkinToken.selection),
    onPrimaryContainer: area.color(SkinToken.onSelection),
  );
}
