import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';

/// All editable Material 3 ColorScheme roles (brightness is selected by the
/// app and is intentionally not stored as a color).
const appColorSchemeRoles = <String>[
  'primary',
  'onPrimary',
  'primaryContainer',
  'onPrimaryContainer',
  'primaryFixed',
  'primaryFixedDim',
  'onPrimaryFixed',
  'onPrimaryFixedVariant',
  'secondary',
  'onSecondary',
  'secondaryContainer',
  'onSecondaryContainer',
  'secondaryFixed',
  'secondaryFixedDim',
  'onSecondaryFixed',
  'onSecondaryFixedVariant',
  'tertiary',
  'onTertiary',
  'tertiaryContainer',
  'onTertiaryContainer',
  'tertiaryFixed',
  'tertiaryFixedDim',
  'onTertiaryFixed',
  'onTertiaryFixedVariant',
  'error',
  'onError',
  'errorContainer',
  'onErrorContainer',
  'surface',
  'onSurface',
  'surfaceDim',
  'surfaceBright',
  'surfaceContainerLowest',
  'surfaceContainerLow',
  'surfaceContainer',
  'surfaceContainerHigh',
  'surfaceContainerHighest',
  'onSurfaceVariant',
  'outline',
  'outlineVariant',
  'shadow',
  'scrim',
  'inverseSurface',
  'onInverseSurface',
  'inversePrimary',
  'surfaceTint',
];

const appSemanticColorRoles = <String>[
  'success',
  'onSuccess',
  'successContainer',
  'onSuccessContainer',
  'warning',
  'onWarning',
  'warningContainer',
  'onWarningContainer',
  'bookmark',
];

const editorSyntaxColorRoles = <String>[
  'keyword',
  'type',
  'string',
  'number',
  'function',
  'comment',
];

const editorColorRoles = <String>[
  'foreground',
  'chromeForeground',
  'background',
  'panel',
  'gutter',
  'cursor',
  'selection',
  ...editorSyntaxColorRoles,
];

/// Colors shared by every page that does not set its own: the top bar and the
/// round add button. (The vault card colors that used to live here are now the
/// Dashboard page's own `card` / `cardActive` tokens.)
const appSharedComponentRoles = <String>[
  'appBarBackground',
  'appBarForeground',
  'fabBackground',
  'fabForeground',
];

// Old global vault-card keys -> the pre-split page key they used to become.
const _legacyVaultCardKeys = <String, String>{
  'vaultCardBackground': 'card',
  'mountedVaultCardBackground': 'cardActive',
};

/// Moves the old global vault-card colors onto the Dashboard page so skins
/// saved before pages had their own colors look identical and "reset" works.
(Map<String, int>, Map<String, Map<String, int>>) _foldLegacyVaultCards(
  Map<String, int> components,
  Map<String, Map<String, int>> areas,
) {
  if (!_legacyVaultCardKeys.keys.any(components.containsKey)) {
    return (components, areas);
  }
  final nextComponents = Map<String, int>.from(components);
  final dashboard = Map<String, int>.from(
    areas[SkinArea.dashboard.id] ?? const <String, int>{},
  );
  for (final entry in _legacyVaultCardKeys.entries) {
    final value = nextComponents.remove(entry.key);
    if (value == null) continue;
    for (final token in SkinToken.fromLegacyId(entry.value)) {
      dashboard.putIfAbsent(token.id, () => value);
    }
  }
  return (nextComponents, {...areas, SkinArea.dashboard.id: dashboard});
}

Color _color(Object? value, Color fallback) =>
    value is num ? Color(value.toInt()) : fallback;

/// A user-authored, complete skin. Color maps use ARGB integers so the full
/// configuration remains compatible with the normal settings JSON export.
@immutable
class CustomAppSkin {
  final String id;
  final String name;
  final Map<String, int> lightColors;
  final Map<String, int> darkColors;
  final Map<String, int> lightSemanticColors;
  final Map<String, int> darkSemanticColors;
  final Map<String, int> lightComponentColors;
  final Map<String, int> darkComponentColors;

  /// Per-page colors: page id -> token id -> ARGB. A page with no entry (or a
  /// token with no entry) inherits from the shared palette above.
  final Map<String, Map<String, int>> lightAreaColors;
  final Map<String, Map<String, int>> darkAreaColors;
  final FileManagerSkin fileManagerSkin;
  final int editorBackground;
  final int editorForeground;
  final int editorGutter;
  final int editorCursor;
  final int editorSelection;
  final Map<String, int> lightEditorColors;
  final Map<String, int> darkEditorColors;
  final Map<String, String> lightEditorOptions;
  final Map<String, String> darkEditorOptions;
  final String editorBackgroundOption;
  final String editorSyntaxThemeOption;

  const CustomAppSkin({
    this.id = 'custom-default',
    this.name = 'My Custom Skin',
    this.lightColors = const {},
    this.darkColors = const {},
    this.lightSemanticColors = const {},
    this.darkSemanticColors = const {},
    this.lightComponentColors = const {},
    this.darkComponentColors = const {},
    this.lightAreaColors = const {},
    this.darkAreaColors = const {},
    this.fileManagerSkin = FileManagerSkin.classic,
    this.editorBackground = 0xFF111318,
    this.editorForeground = 0xFFE2E2E9,
    this.editorGutter = 0xFF85878D,
    this.editorCursor = 0xFFA8C7FA,
    this.editorSelection = 0x47A8C7FA,
    this.lightEditorColors = const {},
    this.darkEditorColors = const {},
    this.lightEditorOptions = const {},
    this.darkEditorOptions = const {},
    this.editorBackgroundOption = 'matchSyntaxTheme',
    this.editorSyntaxThemeOption = 'auto',
  });

  Color colorFor(String role, {required bool dark, required Color fallback}) =>
      _color((dark ? darkColors : lightColors)[role], fallback);

  Color semanticColorFor(
    String role, {
    required bool dark,
    required Color fallback,
  }) =>
      _color((dark ? darkSemanticColors : lightSemanticColors)[role], fallback);

  Color componentColorFor(
    String role, {
    required bool dark,
    required Color fallback,
  }) => _color(
    (dark ? darkComponentColors : lightComponentColors)[role],
    fallback,
  );

  /// This page's own color for [token], or null when it inherits.
  Color? areaColorOrNull(
    SkinArea area,
    SkinToken token, {
    required bool dark,
  }) {
    final value = (dark ? darkAreaColors : lightAreaColors)[area.id]?[token.id];
    return value == null ? null : Color(value);
  }

  /// A copy with [token] set on [area] (or cleared back to inheriting when
  /// [color] is null) for the light or dark palette.
  CustomAppSkin withAreaColor(
    SkinArea area,
    SkinToken token,
    Color? color, {
    required bool dark,
  }) {
    final source = dark ? darkAreaColors : lightAreaColors;
    final tokens = Map<String, int>.from(
      source[area.id] ?? const <String, int>{},
    );
    if (color == null) {
      tokens.remove(token.id);
    } else {
      tokens[token.id] = color.toARGB32();
    }
    final next = Map<String, Map<String, int>>.from(source);
    if (tokens.isEmpty) {
      next.remove(area.id);
    } else {
      next[area.id] = tokens;
    }
    return dark
        ? copyWith(darkAreaColors: next)
        : copyWith(lightAreaColors: next);
  }

  /// A copy with every override of [area] cleared for the light or dark
  /// palette, so the page inherits the shared palette again.
  CustomAppSkin withoutAreaColors(SkinArea area, {required bool dark}) {
    final source = dark ? darkAreaColors : lightAreaColors;
    if (!source.containsKey(area.id)) return this;
    final next = Map<String, Map<String, int>>.from(source)..remove(area.id);
    return dark
        ? copyWith(darkAreaColors: next)
        : copyWith(lightAreaColors: next);
  }

  Color editorColor(String role, {required bool dark}) {
    final colors = dark ? darkEditorColors : lightEditorColors;
    final legacy = switch (role) {
      'background' => editorBackground,
      'foreground' => editorForeground,
      'gutter' => editorGutter,
      'cursor' => editorCursor,
      'selection' => editorSelection,
      _ => 0xFF808080,
    };
    return _color(colors[role], Color(legacy));
  }

  Color? editorColorOrNull(String role, {required bool dark}) {
    final colors = dark ? darkEditorColors : lightEditorColors;
    final val = colors[role];
    return val != null ? Color(val) : null;
  }

  String editorOption(String role, {required bool dark}) =>
      (dark ? darkEditorOptions : lightEditorOptions)[role] ??
      switch (role) {
        'background' => editorBackgroundOption,
        'syntax' => editorSyntaxThemeOption,
        _ => '',
      };

  CustomAppSkin copyWith({
    String? id,
    String? name,
    Map<String, int>? lightColors,
    Map<String, int>? darkColors,
    Map<String, int>? lightSemanticColors,
    Map<String, int>? darkSemanticColors,
    Map<String, int>? lightComponentColors,
    Map<String, int>? darkComponentColors,
    Map<String, Map<String, int>>? lightAreaColors,
    Map<String, Map<String, int>>? darkAreaColors,
    FileManagerSkin? fileManagerSkin,
    int? editorBackground,
    int? editorForeground,
    int? editorGutter,
    int? editorCursor,
    int? editorSelection,
    Map<String, int>? lightEditorColors,
    Map<String, int>? darkEditorColors,
    Map<String, String>? lightEditorOptions,
    Map<String, String>? darkEditorOptions,
    String? editorBackgroundOption,
    String? editorSyntaxThemeOption,
  }) => CustomAppSkin(
    id: id ?? this.id,
    name: name ?? this.name,
    lightColors: lightColors ?? this.lightColors,
    darkColors: darkColors ?? this.darkColors,
    lightSemanticColors: lightSemanticColors ?? this.lightSemanticColors,
    darkSemanticColors: darkSemanticColors ?? this.darkSemanticColors,
    lightComponentColors: lightComponentColors ?? this.lightComponentColors,
    darkComponentColors: darkComponentColors ?? this.darkComponentColors,
    lightAreaColors: lightAreaColors ?? this.lightAreaColors,
    darkAreaColors: darkAreaColors ?? this.darkAreaColors,
    fileManagerSkin: fileManagerSkin ?? this.fileManagerSkin,
    editorBackground: editorBackground ?? this.editorBackground,
    editorForeground: editorForeground ?? this.editorForeground,
    editorGutter: editorGutter ?? this.editorGutter,
    editorCursor: editorCursor ?? this.editorCursor,
    editorSelection: editorSelection ?? this.editorSelection,
    lightEditorColors: lightEditorColors ?? this.lightEditorColors,
    darkEditorColors: darkEditorColors ?? this.darkEditorColors,
    lightEditorOptions: lightEditorOptions ?? this.lightEditorOptions,
    darkEditorOptions: darkEditorOptions ?? this.darkEditorOptions,
    editorBackgroundOption:
        editorBackgroundOption ?? this.editorBackgroundOption,
    editorSyntaxThemeOption:
        editorSyntaxThemeOption ?? this.editorSyntaxThemeOption,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lightColors': lightColors,
    'darkColors': darkColors,
    'lightSemanticColors': lightSemanticColors,
    'darkSemanticColors': darkSemanticColors,
    'lightComponentColors': lightComponentColors,
    'darkComponentColors': darkComponentColors,
    'lightAreaColors': lightAreaColors,
    'darkAreaColors': darkAreaColors,
    'fileManagerSkin': fileManagerSkin.toJson(),
    'editorBackground': editorBackground,
    'editorForeground': editorForeground,
    'editorGutter': editorGutter,
    'editorCursor': editorCursor,
    'editorSelection': editorSelection,
    'lightEditorColors': lightEditorColors,
    'darkEditorColors': darkEditorColors,
    'lightEditorOptions': lightEditorOptions,
    'darkEditorOptions': darkEditorOptions,
    'editorBackgroundOption': editorBackgroundOption,
    'editorSyntaxThemeOption': editorSyntaxThemeOption,
  };

  factory CustomAppSkin.fromJson(Object? raw) {
    if (raw is! Map) return const CustomAppSkin();
    Map<String, int> colors(String key) {
      final value = raw[key];
      if (value is! Map) return const {};
      return value.map<String, int>(
        (key, value) =>
            MapEntry(key.toString(), value is num ? value.toInt() : 0),
      );
    }

    Map<String, String> options(String key) {
      final value = raw[key];
      if (value is! Map) return const {};
      return value.map<String, String>(
        (key, value) => MapEntry(key.toString(), value is String ? value : ''),
      );
    }

    // Unknown pages and tokens are dropped so a hand-edited or future file can
    // never inject a color the app does not know how to apply.
    //
    // Skins saved before the tokens were split use the old keys (`card`,
    // `accent`, ...). Each old value is copied onto every token that key used
    // to drive, so the skin looks the same and each token is now independent.
    // Keys in the current vocabulary are applied last and win.
    Map<String, Map<String, int>> areas(String key) {
      final value = raw[key];
      if (value is! Map) return const {};
      final result = <String, Map<String, int>>{};
      for (final entry in value.entries) {
        final area = SkinArea.tryParse(entry.key);
        final inner = entry.value;
        if (area == null || inner is! Map) continue;
        final tokens = <String, int>{};
        for (final legacy in SkinToken.legacyIdsInApplyOrder) {
          final argb = inner[legacy];
          if (argb is! num) continue;
          for (final token in SkinToken.fromLegacyId(legacy)) {
            tokens[token.id] = argb.toInt();
          }
        }
        for (final token in inner.entries) {
          final parsed = SkinToken.tryParse(token.key);
          final argb = token.value;
          if (parsed != null && argb is num) {
            tokens[parsed.id] = argb.toInt();
          }
        }
        if (tokens.isNotEmpty) result[area.id] = tokens;
      }
      return result;
    }

    int color(String key, int fallback) =>
        raw[key] is num ? (raw[key] as num).toInt() : fallback;
    final (lightComponents, lightAreas) = _foldLegacyVaultCards(
      colors('lightComponentColors'),
      areas('lightAreaColors'),
    );
    final (darkComponents, darkAreas) = _foldLegacyVaultCards(
      colors('darkComponentColors'),
      areas('darkAreaColors'),
    );
    return CustomAppSkin(
      id: raw['id'] is String && (raw['id'] as String).isNotEmpty
          ? raw['id'] as String
          : 'legacy-custom',
      name: raw['name'] is String ? raw['name'] as String : 'My Custom Skin',
      lightColors: colors('lightColors'),
      darkColors: colors('darkColors'),
      lightSemanticColors: colors('lightSemanticColors'),
      darkSemanticColors: colors('darkSemanticColors'),
      lightComponentColors: lightComponents,
      darkComponentColors: darkComponents,
      lightAreaColors: lightAreas,
      darkAreaColors: darkAreas,
      fileManagerSkin: FileManagerSkin.fromJson(raw['fileManagerSkin']),
      editorBackground: color('editorBackground', 0xFF111318),
      editorForeground: color('editorForeground', 0xFFE2E2E9),
      editorGutter: color('editorGutter', 0xFF85878D),
      editorCursor: color('editorCursor', 0xFFA8C7FA),
      editorSelection: color('editorSelection', 0x47A8C7FA),
      lightEditorColors: colors('lightEditorColors'),
      darkEditorColors: colors('darkEditorColors'),
      lightEditorOptions: options('lightEditorOptions'),
      darkEditorOptions: options('darkEditorOptions'),
      editorBackgroundOption: raw['editorBackgroundOption'] is String
          ? raw['editorBackgroundOption'] as String
          : 'matchSyntaxTheme',
      editorSyntaxThemeOption: raw['editorSyntaxThemeOption'] is String
          ? raw['editorSyntaxThemeOption'] as String
          : 'auto',
    );
  }
}

String createCustomAppSkinId() =>
    'skin-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

Map<String, int> colorSchemeToMap(ColorScheme s) => {
  'primary': s.primary.toARGB32(),
  'onPrimary': s.onPrimary.toARGB32(),
  'primaryContainer': s.primaryContainer.toARGB32(),
  'onPrimaryContainer': s.onPrimaryContainer.toARGB32(),
  'primaryFixed': s.primaryFixed.toARGB32(),
  'primaryFixedDim': s.primaryFixedDim.toARGB32(),
  'onPrimaryFixed': s.onPrimaryFixed.toARGB32(),
  'onPrimaryFixedVariant': s.onPrimaryFixedVariant.toARGB32(),
  'secondary': s.secondary.toARGB32(),
  'onSecondary': s.onSecondary.toARGB32(),
  'secondaryContainer': s.secondaryContainer.toARGB32(),
  'onSecondaryContainer': s.onSecondaryContainer.toARGB32(),
  'secondaryFixed': s.secondaryFixed.toARGB32(),
  'secondaryFixedDim': s.secondaryFixedDim.toARGB32(),
  'onSecondaryFixed': s.onSecondaryFixed.toARGB32(),
  'onSecondaryFixedVariant': s.onSecondaryFixedVariant.toARGB32(),
  'tertiary': s.tertiary.toARGB32(),
  'onTertiary': s.onTertiary.toARGB32(),
  'tertiaryContainer': s.tertiaryContainer.toARGB32(),
  'onTertiaryContainer': s.onTertiaryContainer.toARGB32(),
  'tertiaryFixed': s.tertiaryFixed.toARGB32(),
  'tertiaryFixedDim': s.tertiaryFixedDim.toARGB32(),
  'onTertiaryFixed': s.onTertiaryFixed.toARGB32(),
  'onTertiaryFixedVariant': s.onTertiaryFixedVariant.toARGB32(),
  'error': s.error.toARGB32(),
  'onError': s.onError.toARGB32(),
  'errorContainer': s.errorContainer.toARGB32(),
  'onErrorContainer': s.onErrorContainer.toARGB32(),
  'surface': s.surface.toARGB32(),
  'onSurface': s.onSurface.toARGB32(),
  'surfaceDim': s.surfaceDim.toARGB32(),
  'surfaceBright': s.surfaceBright.toARGB32(),
  'surfaceContainerLowest': s.surfaceContainerLowest.toARGB32(),
  'surfaceContainerLow': s.surfaceContainerLow.toARGB32(),
  'surfaceContainer': s.surfaceContainer.toARGB32(),
  'surfaceContainerHigh': s.surfaceContainerHigh.toARGB32(),
  'surfaceContainerHighest': s.surfaceContainerHighest.toARGB32(),
  'onSurfaceVariant': s.onSurfaceVariant.toARGB32(),
  'outline': s.outline.toARGB32(),
  'outlineVariant': s.outlineVariant.toARGB32(),
  'shadow': s.shadow.toARGB32(),
  'scrim': s.scrim.toARGB32(),
  'inverseSurface': s.inverseSurface.toARGB32(),
  'onInverseSurface': s.onInverseSurface.toARGB32(),
  'inversePrimary': s.inversePrimary.toARGB32(),
  'surfaceTint': s.surfaceTint.toARGB32(),
};

ColorScheme applyColorSchemeOverrides(ColorScheme s, Map<String, int> values) {
  Color? c(String role) => values[role] == null ? null : Color(values[role]!);
  return s.copyWith(
    primary: c('primary'),
    onPrimary: c('onPrimary'),
    primaryContainer: c('primaryContainer'),
    onPrimaryContainer: c('onPrimaryContainer'),
    primaryFixed: c('primaryFixed'),
    primaryFixedDim: c('primaryFixedDim'),
    onPrimaryFixed: c('onPrimaryFixed'),
    onPrimaryFixedVariant: c('onPrimaryFixedVariant'),
    secondary: c('secondary'),
    onSecondary: c('onSecondary'),
    secondaryContainer: c('secondaryContainer'),
    onSecondaryContainer: c('onSecondaryContainer'),
    secondaryFixed: c('secondaryFixed'),
    secondaryFixedDim: c('secondaryFixedDim'),
    onSecondaryFixed: c('onSecondaryFixed'),
    onSecondaryFixedVariant: c('onSecondaryFixedVariant'),
    tertiary: c('tertiary'),
    onTertiary: c('onTertiary'),
    tertiaryContainer: c('tertiaryContainer'),
    onTertiaryContainer: c('onTertiaryContainer'),
    tertiaryFixed: c('tertiaryFixed'),
    tertiaryFixedDim: c('tertiaryFixedDim'),
    onTertiaryFixed: c('onTertiaryFixed'),
    onTertiaryFixedVariant: c('onTertiaryFixedVariant'),
    error: c('error'),
    onError: c('onError'),
    errorContainer: c('errorContainer'),
    onErrorContainer: c('onErrorContainer'),
    surface: c('surface'),
    onSurface: c('onSurface'),
    surfaceDim: c('surfaceDim'),
    surfaceBright: c('surfaceBright'),
    surfaceContainerLowest: c('surfaceContainerLowest'),
    surfaceContainerLow: c('surfaceContainerLow'),
    surfaceContainer: c('surfaceContainer'),
    surfaceContainerHigh: c('surfaceContainerHigh'),
    surfaceContainerHighest: c('surfaceContainerHighest'),
    onSurfaceVariant: c('onSurfaceVariant'),
    outline: c('outline'),
    outlineVariant: c('outlineVariant'),
    shadow: c('shadow'),
    scrim: c('scrim'),
    inverseSurface: c('inverseSurface'),
    onInverseSurface: c('onInverseSurface'),
    inversePrimary: c('inversePrimary'),
    surfaceTint: c('surfaceTint'),
  );
}
