import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_colors.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';

/// Derives a readable editor-interface foreground independently of the
/// editor's code text color, including when the canvas brightness differs
/// from the app's current brightness.
Color resolveEditorChromeForeground(Color background, ColorScheme appScheme) {
  final brightness = ThemeData.estimateBrightnessForColor(background);
  if (brightness == appScheme.brightness) return appScheme.onSurface;
  return ColorScheme.fromSeed(
    seedColor: appScheme.primary,
    brightness: brightness,
  ).onSurface;
}

AppSkinTokens buildAppSkinTokens({
  required AppSkinPreset preset,
  CustomAppSkin customAppSkin = const CustomAppSkin(),
  required bool isDark,
  required ColorScheme colorScheme,
  required FileManagerSkin manualFileManagerSkin,
  required bool fileManagerFollowsAppSkin,
  required bool editorFollowsAppSkin,
}) {
  final fileManagerSkin = switch (preset) {
    AppSkinPreset.defaultSkin ||
    AppSkinPreset.oledPureBlack => FileManagerSkin.classic,
    AppSkinPreset.custom => customAppSkin.fileManagerSkin,
  };
  final editorBackground = switch (preset) {
    AppSkinPreset.oledPureBlack => Colors.black,
    AppSkinPreset.defaultSkin => colorScheme.surface,
    AppSkinPreset.custom => customAppSkin.editorColor(
      'background',
      dark: isDark,
    ),
  };
  final derivedEditorChromeForeground = resolveEditorChromeForeground(
    editorBackground,
    colorScheme,
  );
  // The code canvas foreground is deliberately independent from editor UI
  // text (toolbar, menus, sidebar, and status bar). Older skins have no
  // chrome token, so derive a readable value from the editor's own brightness.
  final editorChromeForeground = preset == AppSkinPreset.custom
      ? customAppSkin.editorColorOrNull('chromeForeground', dark: isDark) ??
            derivedEditorChromeForeground
      : derivedEditorChromeForeground;
  final editorForeground = switch (preset) {
    AppSkinPreset.custom => customAppSkin.editorColor(
      'foreground',
      dark: isDark,
    ),
    _ => colorScheme.onSurface,
  };
  // Keep editor chrome visually separate from the code canvas. Blending a
  // little interface text into panel surfaces also supports legacy skins
  // that do not store a panel background token.
  final editorPanelBackground = preset == AppSkinPreset.custom
      ? customAppSkin.editorColorOrNull('panel', dark: isDark) ??
            Color.alphaBlend(
              editorChromeForeground.withValues(alpha: 0.10),
              editorBackground,
            )
      : Color.alphaBlend(
          editorChromeForeground.withValues(alpha: 0.10),
          editorBackground,
        );
  final editorAccent = preset == AppSkinPreset.custom
      ? customAppSkin.editorColor('cursor', dark: isDark)
      : colorScheme.primary;
  // Colors shared by every page that does not set its own.
  final appBarBackground = preset == AppSkinPreset.custom
      ? customAppSkin.componentColorFor(
          'appBarBackground',
          dark: isDark,
          fallback: colorScheme.surfaceContainerHigh,
        )
      : colorScheme.surfaceContainerHigh;
  final appBarForeground = preset == AppSkinPreset.custom
      ? customAppSkin.componentColorFor(
          'appBarForeground',
          dark: isDark,
          fallback: colorScheme.onSurface,
        )
      : colorScheme.onSurface;
  final fabBackground = preset == AppSkinPreset.custom
      ? customAppSkin.componentColorFor(
          'fabBackground',
          dark: isDark,
          fallback: colorScheme.primaryContainer,
        )
      : colorScheme.primaryContainer;
  final fabForeground = preset == AppSkinPreset.custom
      ? customAppSkin.componentColorFor(
          'fabForeground',
          dark: isDark,
          fallback: colorScheme.onPrimaryContainer,
        )
      : colorScheme.onPrimaryContainer;
  final areas = resolveSkinAreaColors(
    scheme: colorScheme,
    appBar: appBarBackground,
    onAppBar: appBarForeground,
    fab: fabBackground,
    onFab: fabForeground,
    overrideFor: preset == AppSkinPreset.custom
        ? (area, token) =>
              customAppSkin.areaColorOrNull(area, token, dark: isDark)
        : null,
  );
  return AppSkinTokens(
    preset: preset,
    appBarBackground: appBarBackground,
    appBarForeground: appBarForeground,
    fabBackground: fabBackground,
    fabForeground: fabForeground,
    areas: areas,
    manualFileManagerSkin: manualFileManagerSkin,
    fileManagerSkin: fileManagerSkin,
    editorBackground: editorBackground,
    editorForeground: editorForeground,
    editorChromeForeground: editorChromeForeground,
    editorPanelBackground: editorPanelBackground,
    editorGutter: preset == AppSkinPreset.custom
        ? customAppSkin.editorColor('gutter', dark: isDark)
        : editorForeground.withValues(alpha: 0.48),
    editorCursor: editorAccent,
    editorSelection: preset == AppSkinPreset.custom
        ? customAppSkin.editorColor('selection', dark: isDark)
        : editorAccent.withValues(alpha: 0.28),
    editorBackgroundOption: preset == AppSkinPreset.oledPureBlack
        ? 'amoledBlack'
        : preset == AppSkinPreset.custom
        ? customAppSkin.editorOption('background', dark: isDark)
        : 'matchSyntaxTheme',
    editorSyntaxThemeOption: switch (preset) {
      AppSkinPreset.oledPureBlack => 'oneDark',
      AppSkinPreset.defaultSkin => 'auto',
      AppSkinPreset.custom => customAppSkin.editorOption(
        'syntax',
        dark: isDark,
      ),
    },
    editorSyntaxColors: {
      if (preset == AppSkinPreset.custom)
        for (final role in editorSyntaxColorRoles)
          if (customAppSkin.editorColorOrNull(role, dark: isDark) != null)
            role: customAppSkin.editorColorOrNull(role, dark: isDark)!,
    },
    fileManagerFollowsAppSkin: fileManagerFollowsAppSkin,
    editorFollowsAppSkin: editorFollowsAppSkin,
  );
}

/// Semantic tokens shared by the app shell, file manager, and editor.
///
/// The active values travel through Flutter's normal ThemeData pipeline, so
/// widgets can depend on them with `Theme.of(context)` and rebuild when the
/// selected skin changes.
@immutable
class AppSkinTokens extends ThemeExtension<AppSkinTokens> {
  final AppSkinPreset preset;
  final Color appBarBackground;
  final Color appBarForeground;
  final Color fabBackground;
  final Color fabForeground;

  /// Every page's own resolved colors. Pages read these through
  /// `SkinAreaScope`; the top-level values above are only the shared defaults
  /// a page falls back to.
  final Map<SkinArea, SkinAreaColors> areas;
  final FileManagerSkin manualFileManagerSkin;
  final FileManagerSkin fileManagerSkin;
  final Color editorBackground;

  /// Default/plain code text drawn on the editor canvas.
  final Color editorForeground;

  /// Text and icons in editor chrome: toolbar, menus, sidebar, and status bar.
  final Color editorChromeForeground;
  final Color editorPanelBackground;
  final Color editorGutter;
  final Color editorCursor;
  final Color editorSelection;
  final String editorBackgroundOption;
  final String editorSyntaxThemeOption;
  final Map<String, Color> editorSyntaxColors;
  final bool fileManagerFollowsAppSkin;
  final bool editorFollowsAppSkin;

  const AppSkinTokens({
    required this.preset,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.fabBackground,
    required this.fabForeground,
    required this.areas,
    required this.manualFileManagerSkin,
    required this.fileManagerSkin,
    required this.editorBackground,
    required this.editorForeground,
    required this.editorChromeForeground,
    required this.editorPanelBackground,
    required this.editorGutter,
    required this.editorCursor,
    required this.editorSelection,
    required this.editorBackgroundOption,
    required this.editorSyntaxThemeOption,
    this.editorSyntaxColors = const {},
    required this.fileManagerFollowsAppSkin,
    required this.editorFollowsAppSkin,
  });

  /// The resolved colors of [area].
  SkinAreaColors areaColors(SkinArea area) => areas[area]!;

  @override
  AppSkinTokens copyWith({
    AppSkinPreset? preset,
    Color? appBarBackground,
    Color? appBarForeground,
    Color? fabBackground,
    Color? fabForeground,
    Map<SkinArea, SkinAreaColors>? areas,
    FileManagerSkin? manualFileManagerSkin,
    FileManagerSkin? fileManagerSkin,
    Color? editorBackground,
    Color? editorForeground,
    Color? editorChromeForeground,
    Color? editorPanelBackground,
    Color? editorGutter,
    Color? editorCursor,
    Color? editorSelection,
    String? editorBackgroundOption,
    String? editorSyntaxThemeOption,
    Map<String, Color>? editorSyntaxColors,
    bool? fileManagerFollowsAppSkin,
    bool? editorFollowsAppSkin,
  }) => AppSkinTokens(
    preset: preset ?? this.preset,
    appBarBackground: appBarBackground ?? this.appBarBackground,
    appBarForeground: appBarForeground ?? this.appBarForeground,
    fabBackground: fabBackground ?? this.fabBackground,
    fabForeground: fabForeground ?? this.fabForeground,
    areas: areas ?? this.areas,
    manualFileManagerSkin: manualFileManagerSkin ?? this.manualFileManagerSkin,
    fileManagerSkin: fileManagerSkin ?? this.fileManagerSkin,
    editorBackground: editorBackground ?? this.editorBackground,
    editorForeground: editorForeground ?? this.editorForeground,
    editorChromeForeground:
        editorChromeForeground ?? this.editorChromeForeground,
    editorPanelBackground: editorPanelBackground ?? this.editorPanelBackground,
    editorGutter: editorGutter ?? this.editorGutter,
    editorCursor: editorCursor ?? this.editorCursor,
    editorSelection: editorSelection ?? this.editorSelection,
    editorBackgroundOption:
        editorBackgroundOption ?? this.editorBackgroundOption,
    editorSyntaxThemeOption:
        editorSyntaxThemeOption ?? this.editorSyntaxThemeOption,
    editorSyntaxColors: editorSyntaxColors ?? this.editorSyntaxColors,
    fileManagerFollowsAppSkin:
        fileManagerFollowsAppSkin ?? this.fileManagerFollowsAppSkin,
    editorFollowsAppSkin: editorFollowsAppSkin ?? this.editorFollowsAppSkin,
  );

  @override
  AppSkinTokens lerp(ThemeExtension<AppSkinTokens>? other, double t) {
    if (other is! AppSkinTokens) return this;
    final discrete = t < 0.5 ? this : other;
    return AppSkinTokens(
      preset: discrete.preset,
      appBarBackground: Color.lerp(
        appBarBackground,
        other.appBarBackground,
        t,
      )!,
      appBarForeground: Color.lerp(
        appBarForeground,
        other.appBarForeground,
        t,
      )!,
      fabBackground: Color.lerp(fabBackground, other.fabBackground, t)!,
      fabForeground: Color.lerp(fabForeground, other.fabForeground, t)!,
      areas: {
        for (final area in SkinArea.values)
          area: SkinAreaColors.lerp(areaColors(area), other.areaColors(area), t),
      },
      manualFileManagerSkin: discrete.manualFileManagerSkin,
      fileManagerSkin: discrete.fileManagerSkin,
      editorBackground: Color.lerp(
        editorBackground,
        other.editorBackground,
        t,
      )!,
      editorForeground: Color.lerp(
        editorForeground,
        other.editorForeground,
        t,
      )!,
      editorChromeForeground: Color.lerp(
        editorChromeForeground,
        other.editorChromeForeground,
        t,
      )!,
      editorPanelBackground: Color.lerp(
        editorPanelBackground,
        other.editorPanelBackground,
        t,
      )!,
      editorGutter: Color.lerp(editorGutter, other.editorGutter, t)!,
      editorCursor: Color.lerp(editorCursor, other.editorCursor, t)!,
      editorSelection: Color.lerp(editorSelection, other.editorSelection, t)!,
      editorBackgroundOption: discrete.editorBackgroundOption,
      editorSyntaxThemeOption: discrete.editorSyntaxThemeOption,
      editorSyntaxColors: discrete.editorSyntaxColors,
      fileManagerFollowsAppSkin: discrete.fileManagerFollowsAppSkin,
      editorFollowsAppSkin: discrete.editorFollowsAppSkin,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSkinTokens &&
          preset == other.preset &&
          appBarBackground == other.appBarBackground &&
          appBarForeground == other.appBarForeground &&
          fabBackground == other.fabBackground &&
          fabForeground == other.fabForeground &&
          mapEquals(areas, other.areas) &&
          manualFileManagerSkin == other.manualFileManagerSkin &&
          fileManagerSkin == other.fileManagerSkin &&
          editorBackground == other.editorBackground &&
          editorForeground == other.editorForeground &&
          editorChromeForeground == other.editorChromeForeground &&
          editorPanelBackground == other.editorPanelBackground &&
          editorGutter == other.editorGutter &&
          editorCursor == other.editorCursor &&
          editorSelection == other.editorSelection &&
          editorBackgroundOption == other.editorBackgroundOption &&
          editorSyntaxThemeOption == other.editorSyntaxThemeOption &&
          mapEquals(editorSyntaxColors, other.editorSyntaxColors) &&
          fileManagerFollowsAppSkin == other.fileManagerFollowsAppSkin &&
          editorFollowsAppSkin == other.editorFollowsAppSkin;

  @override
  int get hashCode => Object.hashAll([
    preset,
    appBarBackground,
    appBarForeground,
    fabBackground,
    fabForeground,
    Object.hashAll(areas.entries.map((e) => Object.hash(e.key, e.value))),
    manualFileManagerSkin,
    fileManagerSkin,
    editorBackground,
    editorForeground,
    editorChromeForeground,
    editorPanelBackground,
    editorGutter,
    editorCursor,
    editorSelection,
    editorBackgroundOption,
    editorSyntaxThemeOption,
    Object.hashAll(
      editorSyntaxColors.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    fileManagerFollowsAppSkin,
    editorFollowsAppSkin,
  ]);
}
