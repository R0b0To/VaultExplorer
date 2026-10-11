import 'package:material_ui/material_ui.dart';
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
  'background',
  'gutter',
  'cursor',
  'selection',
  ...editorSyntaxColorRoles,
];

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

    int color(String key, int fallback) =>
        raw[key] is num ? (raw[key] as num).toInt() : fallback;
    return CustomAppSkin(
      id: raw['id'] is String && (raw['id'] as String).isNotEmpty
          ? raw['id'] as String
          : 'legacy-custom',
      name: raw['name'] is String ? raw['name'] as String : 'My Custom Skin',
      lightColors: colors('lightColors'),
      darkColors: colors('darkColors'),
      lightSemanticColors: colors('lightSemanticColors'),
      darkSemanticColors: colors('darkSemanticColors'),
      lightComponentColors: colors('lightComponentColors'),
      darkComponentColors: colors('darkComponentColors'),
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
