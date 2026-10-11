import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';

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
  final editorForeground = switch (preset) {
    AppSkinPreset.custom => customAppSkin.editorColor(
      'foreground',
      dark: isDark,
    ),
    _ => colorScheme.onSurface,
  };
  final editorAccent = preset == AppSkinPreset.custom
      ? customAppSkin.editorColor('cursor', dark: isDark)
      : colorScheme.primary;
  final baseVaultCard = colorScheme.surfaceContainerHigh;
  final mountedVaultCard = Color.alphaBlend(
    colorScheme.primaryContainer.withValues(alpha: isDark ? 0.35 : 0.55),
    baseVaultCard,
  );
  return AppSkinTokens(
    preset: preset,
    appBarBackground: preset == AppSkinPreset.custom
        ? customAppSkin.componentColorFor(
            'appBarBackground',
            dark: isDark,
            fallback: colorScheme.surfaceContainerHigh,
          )
        : colorScheme.surfaceContainerHigh,
    appBarForeground: preset == AppSkinPreset.custom
        ? customAppSkin.componentColorFor(
            'appBarForeground',
            dark: isDark,
            fallback: colorScheme.onSurface,
          )
        : colorScheme.onSurface,
    fabBackground: preset == AppSkinPreset.custom
        ? customAppSkin.componentColorFor(
            'fabBackground',
            dark: isDark,
            fallback: colorScheme.primaryContainer,
          )
        : colorScheme.primaryContainer,
    fabForeground: preset == AppSkinPreset.custom
        ? customAppSkin.componentColorFor(
            'fabForeground',
            dark: isDark,
            fallback: colorScheme.onPrimaryContainer,
          )
        : colorScheme.onPrimaryContainer,
    vaultCardBackground: preset == AppSkinPreset.custom
        ? customAppSkin.componentColorFor(
            'vaultCardBackground',
            dark: isDark,
            fallback: baseVaultCard,
          )
        : baseVaultCard,
    mountedVaultCardBackground: preset == AppSkinPreset.custom
        ? customAppSkin.componentColorFor(
            'mountedVaultCardBackground',
            dark: isDark,
            fallback: mountedVaultCard,
          )
        : mountedVaultCard,
    manualFileManagerSkin: manualFileManagerSkin,
    fileManagerSkin: fileManagerSkin,
    editorBackground: editorBackground,
    editorForeground: editorForeground,
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
  final Color vaultCardBackground;
  final Color mountedVaultCardBackground;
  final FileManagerSkin manualFileManagerSkin;
  final FileManagerSkin fileManagerSkin;
  final Color editorBackground;
  final Color editorForeground;
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
    required this.vaultCardBackground,
    required this.mountedVaultCardBackground,
    required this.manualFileManagerSkin,
    required this.fileManagerSkin,
    required this.editorBackground,
    required this.editorForeground,
    required this.editorGutter,
    required this.editorCursor,
    required this.editorSelection,
    required this.editorBackgroundOption,
    required this.editorSyntaxThemeOption,
    this.editorSyntaxColors = const {},
    required this.fileManagerFollowsAppSkin,
    required this.editorFollowsAppSkin,
  });

  @override
  AppSkinTokens copyWith({
    AppSkinPreset? preset,
    Color? appBarBackground,
    Color? appBarForeground,
    Color? fabBackground,
    Color? fabForeground,
    Color? vaultCardBackground,
    Color? mountedVaultCardBackground,
    FileManagerSkin? manualFileManagerSkin,
    FileManagerSkin? fileManagerSkin,
    Color? editorBackground,
    Color? editorForeground,
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
    vaultCardBackground: vaultCardBackground ?? this.vaultCardBackground,
    mountedVaultCardBackground:
        mountedVaultCardBackground ?? this.mountedVaultCardBackground,
    manualFileManagerSkin: manualFileManagerSkin ?? this.manualFileManagerSkin,
    fileManagerSkin: fileManagerSkin ?? this.fileManagerSkin,
    editorBackground: editorBackground ?? this.editorBackground,
    editorForeground: editorForeground ?? this.editorForeground,
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
      vaultCardBackground: Color.lerp(
        vaultCardBackground,
        other.vaultCardBackground,
        t,
      )!,
      mountedVaultCardBackground: Color.lerp(
        mountedVaultCardBackground,
        other.mountedVaultCardBackground,
        t,
      )!,
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
          vaultCardBackground == other.vaultCardBackground &&
          mountedVaultCardBackground == other.mountedVaultCardBackground &&
          manualFileManagerSkin == other.manualFileManagerSkin &&
          fileManagerSkin == other.fileManagerSkin &&
          editorBackground == other.editorBackground &&
          editorForeground == other.editorForeground &&
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
    vaultCardBackground,
    mountedVaultCardBackground,
    manualFileManagerSkin,
    fileManagerSkin,
    editorBackground,
    editorForeground,
    editorGutter,
    editorCursor,
    editorSelection,
    editorBackgroundOption,
    editorSyntaxThemeOption,
    Object.hashAll(editorSyntaxColors.entries.map((e) => Object.hash(e.key, e.value))),
    fileManagerFollowsAppSkin,
    editorFollowsAppSkin,
  ]);
}
