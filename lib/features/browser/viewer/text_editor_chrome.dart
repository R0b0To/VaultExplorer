// Makes the whole TextEditorScreen -- app bar, tab strip, status bar,
// accessory key bar, find panel, drawer, popup menus, system navigation bar --
// follow the editor's own background/syntax theme instead of only the text
// area following it.
//
// The editor background and text color come from resolveEditorSyntaxStyle
// (text_editor_language.dart), which is the single place they're decided.
// This file turns that pair into a full [ColorScheme]/[ThemeData], so the
// screen's existing `Theme.of(context).colorScheme` lookups keep working
// unchanged and simply resolve to editor colors.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/app_skin_tokens.dart';

@immutable
class EditorChrome {
  final Color background;
  final Color foreground;
  final ColorScheme appScheme;
  final AppSkinTokens? appSkinTokens;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final SystemUiOverlayStyle overlayStyle;

  const EditorChrome._({
    required this.background,
    required this.foreground,
    required this.appScheme,
    required this.appSkinTokens,
    required this.colorScheme,
    required this.theme,
    required this.overlayStyle,
  });

  /// Building a [ThemeData] is not free and the editor screen rebuilds on
  /// every cursor move, so the screen keeps the last result and only calls
  /// [EditorChrome.resolve] again when one of these inputs changed.
  bool matches(
    Color background,
    Color foreground,
    ColorScheme appScheme, {
    AppSkinTokens? appSkinTokens,
  }) =>
      this.background == background &&
      this.foreground == foreground &&
      this.appScheme == appScheme &&
      this.appSkinTokens == appSkinTokens;

  factory EditorChrome.resolve({
    required Color background,
    required Color foreground,
    required ColorScheme appScheme,
    AppSkinTokens? appSkinTokens,
  }) {
    final brightness = ThemeData.estimateBrightnessForColor(background);
    final isDark = brightness == Brightness.dark;

    // A solid blend of the text color over the background: a slightly
    // lifted/dimmed surface that stays in the same hue family as the editor,
    // whichever background was picked.
    Color tone(double alpha) =>
        Color.alphaBlend(foreground.withValues(alpha: alpha), background);

    // When the editor's brightness differs from the app's (a light "Sepia"
    // editor inside the dark app, or AMOLED black inside the light app), the
    // app's accent and error colors were tuned for the other brightness and
    // would sit at poor contrast. Re-derive them from the same seed for the
    // editor's brightness; keep the app's exact palette (Material You
    // included) when the two agree.
    final accents = appScheme.brightness == brightness
        ? appScheme
        : ColorScheme.fromSeed(
            seedColor: appScheme.primary,
            brightness: brightness,
          );

    final scheme = accents.copyWith(
      brightness: brightness,
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: tone(0.72),
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: tone(0.04),
      surfaceContainerHigh: tone(0.07),
      surfaceContainerHighest: tone(0.11),
      outline: tone(0.45),
      outlineVariant: tone(0.14),
    );

    // The bottom edge is the status bar (same color as the editor), so the
    // system navigation bar is painted to match and -- the part that matters
    // with gesture navigation -- the gesture pill gets icons that contrast
    // with the *editor's* background rather than the app's.
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: brightness,
      systemNavigationBarColor: scheme.surfaceContainerLow,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );

    return EditorChrome._(
      background: background,
      foreground: foreground,
      appScheme: appScheme,
      colorScheme: scheme,
      theme: buildThemeFromColorScheme(scheme, appSkinTokens: appSkinTokens),
      overlayStyle: overlay,
      appSkinTokens: appSkinTokens,
    );
  }
}
