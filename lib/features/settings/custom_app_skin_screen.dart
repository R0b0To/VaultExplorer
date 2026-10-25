import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/core/theme/app_skin_tokens.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_colors.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_theme.dart';
import 'package:vaultexplorer/features/settings/widgets/skin_color_picker_sheet.dart';
import 'package:vaultexplorer/features/settings/widgets/skin_role_copy.dart';
import 'package:vaultexplorer/features/skin_editor/skin_edit_session.dart';
import 'package:vaultexplorer/features/settings/file_manager_skin_screen.dart';
import 'package:vaultexplorer/features/settings/widgets/file_manager_skin_mode_notice.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';

CustomAppSkin createCustomAppSkinFromCurrent(AppSkinSettings settings) {
  final light = buildLightTheme(
    appSkin: settings.preset,
    customAppSkin: settings.customAppSkin,
    manualFileManagerSkin: settings.fileManagerSkin,
    fileManagerFollowsAppSkin: settings.fileManagerFollowsAppSkin,
    editorFollowsAppSkin: settings.editorFollowsAppSkin,
  );
  final dark = buildDarkTheme(
    appSkin: settings.preset,
    customAppSkin: settings.customAppSkin,

    manualFileManagerSkin: settings.fileManagerSkin,
    fileManagerFollowsAppSkin: settings.fileManagerFollowsAppSkin,
    editorFollowsAppSkin: settings.editorFollowsAppSkin,
  );
  final lightTokens = light.extension<AppSkinTokens>()!;
  final darkTokens = dark.extension<AppSkinTokens>()!;
  final lightSemantic = light.extension<AppSemanticColors>()!;
  final darkSemantic = dark.extension<AppSemanticColors>()!;
  return CustomAppSkin(
    lightColors: colorSchemeToMap(light.colorScheme),
    darkColors: colorSchemeToMap(dark.colorScheme),
    lightSemanticColors: _semanticMap(lightSemantic),
    darkSemanticColors: _semanticMap(darkSemantic),
    lightEditorColors: _editorColorMap(lightTokens),
    darkEditorColors: _editorColorMap(darkTokens),
    lightEditorOptions: _editorOptionMap(lightTokens),
    darkEditorOptions: _editorOptionMap(darkTokens),
    fileManagerSkin: settings.fileManagerFollowsAppSkin
        ? lightTokens.fileManagerSkin
        : settings.fileManagerSkin,
    editorBackground: lightTokens.editorBackground.toARGB32(),
    editorForeground: lightTokens.editorForeground.toARGB32(),
    editorGutter: lightTokens.editorGutter.toARGB32(),
    editorCursor: lightTokens.editorCursor.toARGB32(),
    editorSelection: lightTokens.editorSelection.toARGB32(),
    editorBackgroundOption: lightTokens.editorBackgroundOption,
    editorSyntaxThemeOption: lightTokens.editorSyntaxThemeOption,
  );
}

Map<String, int> _semanticMap(AppSemanticColors colors) => {
  'success': colors.success.toARGB32(),
  'onSuccess': colors.onSuccess.toARGB32(),
  'successContainer': colors.successContainer.toARGB32(),
  'onSuccessContainer': colors.onSuccessContainer.toARGB32(),
  'warning': colors.warning.toARGB32(),
  'onWarning': colors.onWarning.toARGB32(),
  'warningContainer': colors.warningContainer.toARGB32(),
  'onWarningContainer': colors.onWarningContainer.toARGB32(),
  'bookmark': colors.bookmark.toARGB32(),
};

Map<String, int> _editorColorMap(AppSkinTokens tokens) => {
  'background': tokens.editorBackground.toARGB32(),
  'foreground': tokens.editorForeground.toARGB32(),
  'chromeForeground': tokens.editorChromeForeground.toARGB32(),
  'panel': tokens.editorPanelBackground.toARGB32(),
  'gutter': tokens.editorGutter.toARGB32(),
  'cursor': tokens.editorCursor.toARGB32(),
  'selection': tokens.editorSelection.toARGB32(),
  for (final entry in tokens.editorSyntaxColors.entries)
    entry.key: entry.value.toARGB32(),
};

Map<String, String> _editorOptionMap(AppSkinTokens tokens) => {
  'background': tokens.editorBackgroundOption,
  'syntax': tokens.editorSyntaxThemeOption,
};

List<(String, String, List<String>)> _appColorGroups(BuildContext context) => [
  (
    context.l10n.skinMainActions,
    context.l10n.skinPrimaryButtonsSelectionsAndFixedPrimaryAccents,
    [
      'primary',
      'onPrimary',
      'primaryContainer',
      'onPrimaryContainer',
      'primaryFixed',
      'primaryFixedDim',
      'onPrimaryFixed',
      'onPrimaryFixedVariant',
    ],
  ),
  (
    context.l10n.skinSupportingAccents,
    context.l10n.skinSecondaryAndTertiaryHighlightsAndTheirTextColors,
    [
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
    ],
  ),
  (
    'Errors',
    context.l10n.skinErrorMessagesAndDestructiveOrInvalidStates,
    ['error', 'onError', 'errorContainer', 'onErrorContainer'],
  ),
  (
    context.l10n.skinPagesCardsAndText,
    context.l10n.skinAppBackgroundsCardsMenusAndForegroundText,
    [
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
      'inverseSurface',
      'onInverseSurface',
      'inversePrimary',
      'surfaceTint',
    ],
  ),
  (
    context.l10n.skinBordersAndOverlays,
    context.l10n.skinOutlinesShadowsAndModalBackdrops,
    ['outline', 'outlineVariant', 'shadow', 'scrim'],
  ),
];

/// Every color and option of a custom skin as a list.
///
/// Colors are normally changed in place with the floating picker (see
/// `SkinEditorHost`); this page is its "more options" screen, for everything
/// the picker cannot reach by tapping: names, icon styles, editor templates,
/// and any color from a list. While a session is running it edits the same
/// draft as the picker.
class CustomAppSkinScreen extends ConsumerStatefulWidget {
  final bool? initialDarkColors;
  final bool showFileManagerSkinShortcut;

  const CustomAppSkinScreen({
    super.key,
    this.initialDarkColors,
    this.showFileManagerSkinShortcut = true,
  });

  @override
  ConsumerState<CustomAppSkinScreen> createState() =>
      _CustomAppSkinScreenState();
}

class _CustomAppSkinScreenState extends ConsumerState<CustomAppSkinScreen> {
  bool _darkColors = false;
  bool _didInitializeBrightness = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitializeBrightness) return;
    _darkColors =
        widget.initialDarkColors ??
        Theme.of(context).brightness == Brightness.dark;
    _didInitializeBrightness = true;
  }

  /// The skin being edited: the live draft while a floating-picker session is
  /// running, otherwise the saved custom skin.
  CustomAppSkin get _skin =>
      ref.read(skinEditSessionProvider)?.draft ??
      ref.read(appSkinSettingsProvider).customAppSkin;

  void _save(CustomAppSkin skin) {
    if (ref.read(skinEditSessionProvider) != null) {
      ref.read(skinEditSessionProvider.notifier).replaceDraft(skin);
    } else {
      ref.read(appSkinSettingsProvider.notifier).setCustomAppSkin(skin);
    }
  }

  Future<void> _pickColor({
    required String title,
    required Color current,
    required ValueChanged<Color> onColor,
    bool allowDefault = false,
    VoidCallback? onDefault,
  }) async {
    final result = await showSkinColorPicker(
      context,
      title: title,
      initial: current,
      allowDefault: allowDefault,
    );
    if (result == null || !mounted) return;
    if (result.color != null) {
      onColor(result.color!);
    } else {
      onDefault?.call();
    }
  }

  Map<String, int> _schemeColors() =>
      _darkColors ? _skin.darkColors : _skin.lightColors;

  Map<String, int> _semanticColors() =>
      _darkColors ? _skin.darkSemanticColors : _skin.lightSemanticColors;

  Map<String, int> _componentColors() =>
      _darkColors ? _skin.darkComponentColors : _skin.lightComponentColors;

  ColorScheme _editorColorScheme() {
    final base = _darkColors
        ? buildDarkTheme().colorScheme
        : buildLightTheme().colorScheme;
    return applyColorSchemeOverrides(base, _schemeColors());
  }

  Color _componentFallback(String role) {
    final cs = _editorColorScheme();
    return switch (role) {
      'appBarBackground' => cs.surfaceContainerHigh,
      'appBarForeground' => cs.onSurface,
      'fabBackground' => cs.primaryContainer,
      'fabForeground' => cs.onPrimaryContainer,
      'vaultCardBackground' => cs.surfaceContainerHigh,
      'mountedVaultCardBackground' => Color.alphaBlend(
        cs.primaryContainer.withValues(alpha: _darkColors ? 0.35 : 0.55),
        cs.surfaceContainerHigh,
      ),
      _ => cs.primary,
    };
  }

  Color _componentColor(String role) =>
      Color(_componentColors()[role] ?? _componentFallback(role).toARGB32());

  void _setSchemeColor(String role, Color color) {
    final values = Map<String, int>.from(_schemeColors())
      ..[role] = color.toARGB32();
    _save(
      _darkColors
          ? _skin.copyWith(darkColors: values)
          : _skin.copyWith(lightColors: values),
    );
  }

  void _clearSchemeColor(String role) {
    final values = Map<String, int>.from(_schemeColors())..remove(role);
    _save(
      _darkColors
          ? _skin.copyWith(darkColors: values)
          : _skin.copyWith(lightColors: values),
    );
  }

  void _setSemanticColor(String role, Color color) {
    final values = Map<String, int>.from(_semanticColors())
      ..[role] = color.toARGB32();
    _save(
      _darkColors
          ? _skin.copyWith(darkSemanticColors: values)
          : _skin.copyWith(lightSemanticColors: values),
    );
  }

  void _clearSemanticColor(String role) {
    final values = Map<String, int>.from(_semanticColors())..remove(role);
    _save(
      _darkColors
          ? _skin.copyWith(darkSemanticColors: values)
          : _skin.copyWith(lightSemanticColors: values),
    );
  }

  void _setComponentColor(String role, Color color) {
    final values = Map<String, int>.from(_componentColors())
      ..[role] = color.toARGB32();
    _save(
      _darkColors
          ? _skin.copyWith(darkComponentColors: values)
          : _skin.copyWith(lightComponentColors: values),
    );
  }

  void _clearComponentColor(String role) {
    final values = Map<String, int>.from(_componentColors())..remove(role);
    _save(
      _darkColors
          ? _skin.copyWith(darkComponentColors: values)
          : _skin.copyWith(lightComponentColors: values),
    );
  }

  void _setEditorColor(String role, Color color) {
    final values = Map<String, int>.from(
      _darkColors ? _skin.darkEditorColors : _skin.lightEditorColors,
    )..[role] = color.toARGB32();
    if (_darkColors) {
      _save(_skin.copyWith(darkEditorColors: values));
    } else {
      final updated = _skin.copyWith(lightEditorColors: values);
      // Keep the original flat fields populated so older versions can still
      // read a newly edited custom skin.
      _save(_withLegacyEditorColor(updated, role, color.toARGB32()));
    }
  }

  CustomAppSkin _withLegacyEditorColor(
    CustomAppSkin skin,
    String role,
    int value,
  ) => switch (role) {
    'background' => skin.copyWith(editorBackground: value),
    'foreground' => skin.copyWith(editorForeground: value),
    'gutter' => skin.copyWith(editorGutter: value),
    'cursor' => skin.copyWith(editorCursor: value),
    'selection' => skin.copyWith(editorSelection: value),
    _ => skin,
  };

  void _setEditorOption(String role, String value) {
    final options = Map<String, String>.from(
      _darkColors ? _skin.darkEditorOptions : _skin.lightEditorOptions,
    )..[role] = value;
    final backgroundName = role == 'background'
        ? value
        : _editorOption('background');
    final background = EditorBackgroundOption.values.firstWhere(
      (option) => option.name == backgroundName,
      orElse: () => EditorBackgroundOption.matchSyntaxTheme,
    );
    final shouldResolveCanvas =
        role == 'background' ||
        (role == 'syntax' &&
            background == EditorBackgroundOption.matchSyntaxTheme);
    var updated = _darkColors
        ? _skin.copyWith(darkEditorOptions: options)
        : _skin.copyWith(lightEditorOptions: options);
    if (shouldResolveCanvas) {
      final syntaxName = role == 'syntax' ? value : _editorOption('syntax');
      final syntax = EditorSyntaxThemeOption.values.firstWhere(
        (option) => option.name == syntaxName,
        orElse: () => EditorSyntaxThemeOption.auto,
      );
      final root = syntax.themeMap(
        _darkColors ? Brightness.dark : Brightness.light,
      )['root'];
      final canvas = background.overrideColor ?? root?.backgroundColor;
      final foreground = background.overrideColor == null
          ? root?.color
          : background.fallbackTextColor;
      if (canvas != null || foreground != null) {
        final editorColors = Map<String, int>.from(
          _darkColors ? _skin.darkEditorColors : _skin.lightEditorColors,
        );
        if (canvas != null) editorColors['background'] = canvas.toARGB32();
        if (foreground != null) {
          editorColors['foreground'] = foreground.toARGB32();
        }
        updated = _darkColors
            ? updated.copyWith(darkEditorColors: editorColors)
            : updated.copyWith(lightEditorColors: editorColors);
        if (!_darkColors) {
          if (canvas != null) {
            updated = updated.copyWith(editorBackground: canvas.toARGB32());
          }
          if (foreground != null) {
            updated = updated.copyWith(editorForeground: foreground.toARGB32());
          }
        }
      }
    }
    _save(updated);
  }

  void _clearEditorColor(String role) {
    final values = Map<String, int>.from(
      _darkColors ? _skin.darkEditorColors : _skin.lightEditorColors,
    )..remove(role);
    if (_darkColors) {
      _save(_skin.copyWith(darkEditorColors: values));
    } else {
      _save(_skin.copyWith(lightEditorColors: values));
    }
  }

  Color _editorColor(String role) {
    final custom = _skin.editorColorOrNull(role, dark: _darkColors);
    if (custom != null) return custom;
    if (role == 'panel') {
      return Color.alphaBlend(
        _editorColor('chromeForeground').withValues(alpha: 0.10),
        _editorColor('background'),
      );
    }
    if (role == 'chromeForeground') {
      return resolveEditorChromeForeground(
        _editorColor('background'),
        _editorColorScheme(),
      );
    }
    if (editorSyntaxColorRoles.contains(role)) {
      final syntaxOption = EditorSyntaxThemeOption.values.firstWhere(
        (option) => option.name == _editorOption('syntax'),
        orElse: () => EditorSyntaxThemeOption.auto,
      );
      final styles = syntaxOption.themeMap(
        _darkColors ? Brightness.dark : Brightness.light,
      );
      final key = switch (role) {
        'keyword' => 'keyword',
        'type' => 'title.class_',
        'string' => 'string',
        'number' => 'number',
        'function' => 'built_in',
        'comment' => 'comment',
        _ => role,
      };
      return styles[key]?.color ??
          _skin.editorColor('foreground', dark: _darkColors);
    }
    return _skin.editorColor(role, dark: _darkColors);
  }

  String _editorOption(String role) =>
      _skin.editorOption(role, dark: _darkColors);

  Color _storedColor(Map<String, int> colors, String role) => Color(
    colors[role] ?? colorSchemeToMap(_editorColorScheme())[role] ?? 0xFF808080,
  );

  Color _schemeColor(String role) => _storedColor(_schemeColors(), role);

  Color _semanticColor(String role) => Color(
    _semanticMap(_previewBase(_skin).extension<AppSemanticColors>()!)[role] ??
        0xFF808080,
  );

  // The very theme the app builds for this skin, used to work out what an
  // un-customized ("inherited") color currently resolves to.
  ThemeData? _previewBaseCache;
  CustomAppSkin? _previewBaseSkin;
  bool? _previewBaseDark;

  ThemeData _previewBase(CustomAppSkin skin) {
    final cached = _previewBaseCache;
    if (cached != null &&
        identical(_previewBaseSkin, skin) &&
        _previewBaseDark == _darkColors) {
      return cached;
    }
    final built = _darkColors
        ? buildDarkTheme(appSkin: AppSkinPreset.custom, customAppSkin: skin)
        : buildLightTheme(appSkin: AppSkinPreset.custom, customAppSkin: skin);
    _previewBaseCache = built;
    _previewBaseSkin = skin;
    _previewBaseDark = _darkColors;
    return built;
  }

  SkinAreaColors _areaColors(CustomAppSkin skin, SkinArea area) =>
      _previewBase(skin).extension<AppSkinTokens>()!.areaColors(area);

  /// The editor's toolbar follows the editor theme unless the skin overrides
  /// it, so its "inherited" value is derived from the editor's own colors.
  Color _editorToolbarColor(SkinToken token) {
    final custom = _skin.areaColorOrNull(
      SkinArea.editor,
      token,
      dark: _darkColors,
    );
    if (custom != null) return custom;
    final chrome = _editorColor('chromeForeground');
    return token == SkinToken.appBar
        ? Color.alphaBlend(
            chrome.withValues(alpha: 0.04),
            _editorColor('background'),
          )
        : chrome;
  }

  Color _areaTokenColor(SkinArea area, SkinToken token) =>
      area == SkinArea.editor
      ? _editorToolbarColor(token)
      : _areaColors(_skin, area).color(token);

  Future<void> _pickAreaColor(
    SkinArea area,
    SkinToken token, {
    required String title,
  }) => _pickColor(
    title: title,
    current: _areaTokenColor(area, token),
    allowDefault: true,
    onColor: (value) =>
        _save(_skin.withAreaColor(area, token, value, dark: _darkColors)),
    onDefault: () =>
        _save(_skin.withAreaColor(area, token, null, dark: _darkColors)),
  );

  @override
  Widget build(BuildContext context) {
    final skin =
        ref.watch(skinEditSessionProvider.select((s) => s?.draft)) ??
        ref.watch(appSkinSettingsProvider).customAppSkin;
    return _buildControlsPage(skin);
  }

  Widget _buildControlsPage(CustomAppSkin skin) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.skinCustomizeSkin)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: _settingsSections(skin),
          ),
        ),
      ),
    ),
  );

  List<Widget> _settingsSections(CustomAppSkin skin) {
    const guidedRoles = {
      'surface',
      'onSurface',
      'onSurfaceVariant',
      'primary',
      'primaryContainer',
      'onPrimaryContainer',
    };
    final advancedRoles = appColorSchemeRoles
        .where((role) => !guidedRoles.contains(role))
        .toList();
    final advancedGroups = [
      for (final group in _appColorGroups(context))
        if (group.$3.where((role) => !guidedRoles.contains(role)).isNotEmpty)
          (
            group.$1,
            group.$2,
            group.$3.where((role) => !guidedRoles.contains(role)).toList(),
          ),
    ];
    return [
      _sectionCard(
        title: context.l10n.skinSkinDetails,
        subtitle: context.l10n.skinNameYourSkinAndChooseWhichPaletteToEdit,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextFormField(
              key: ValueKey(skin.name),
              initialValue: skin.name,
              decoration: InputDecoration(labelText: context.l10n.skinSkinName),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (value) => _save(
                skin.copyWith(
                  name: value.trim().isEmpty
                      ? context.l10n.skinMyCustomSkin
                      : value.trim(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(context.l10n.skinLightColors),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(context.l10n.skinDarkColors),
                ),
              ],
              selected: {_darkColors},
              onSelectionChanged: (selection) =>
                  setState(() => _darkColors = selection.first),
            ),
          ),
        ],
      ),
      _groupHeader(
        context.l10n.skinSharedPaletteTitle,
        context.l10n.skinSharedPaletteDescription,
      ),
      _colorRolesSection(
        title: context.l10n.skinPageAndActions,
        description: context.l10n.skinTheMainBackgroundTextAndActionColors,
        roles: const [
          'surface',
          'onSurface',
          'onSurfaceVariant',
          'primary',
          'primaryContainer',
          'onPrimaryContainer',
        ],
        colorFor: _schemeColor,
        onPick: (role) => _pickColor(
          title: skinColorRoleCopy(context)[role]?.$1 ?? skinRoleFallbackLabel(role),
          current: _schemeColor(role),
          allowDefault: true,
          onColor: (value) => _setSchemeColor(role, value),
          onDefault: () => _clearSchemeColor(role),
        ),
      ),
      _componentColorsSection(
        title: context.l10n.skinAppBar,
        subtitle: context.l10n.skinSharedBarDescription,
        roles: [
          (
            'appBarBackground',
            context.l10n.textEditorBackgroundSectionTitle,
            context.l10n.skinTopBarFillColor,
          ),
          (
            'appBarForeground',
            context.l10n.skinTitleAndIcons,
            context.l10n.skinTopBarTextAndIconColor,
          ),
        ],
      ),
      _componentColorsSection(
        title: context.l10n.skinFloatingActionButton,
        subtitle: context.l10n.skinSharedFabDescription,
        roles: [
          (
            'fabBackground',
            context.l10n.skinButtonFill,
            context.l10n.skinBackgroundOfTheRoundButton,
          ),
          (
            'fabForeground',
            context.l10n.skinButtonIcon,
            context.l10n.skinIconColorOnTheRoundButton,
          ),
        ],
      ),
      _colorRolesSection(
        title: context.l10n.skinFineTuneAppColors,
        description:
            context.l10n.skinAdvancedMaterialColorsForLessCommonElements,
        roles: advancedRoles,
        groups: advancedGroups,
        colorFor: _schemeColor,
        onPick: (role) => _pickColor(
          title: skinColorRoleCopy(context)[role]?.$1 ?? skinRoleFallbackLabel(role),
          current: _schemeColor(role),
          allowDefault: true,
          onColor: (value) => _setSchemeColor(role, value),
          onDefault: () => _clearSchemeColor(role),
        ),
      ),
      _colorRolesSection(
        title: context.l10n.skinStatusAndBookmarkColors,
        description:
            context.l10n.skinColorsForSuccessWarningsErrorsAndBookmarks,
        roles: appSemanticColorRoles,
        colorFor: _semanticColor,
        onPick: (role) => _pickColor(
          title: skinColorRoleCopy(context)[role]?.$1 ?? skinRoleFallbackLabel(role),
          current: _semanticColor(role),
          allowDefault: true,
          onColor: (value) => _setSemanticColor(role, value),
          onDefault: () => _clearSemanticColor(role),
        ),
      ),
      _groupHeader(
        context.l10n.skinPagesTitle,
        context.l10n.skinPagesDescription,
      ),
      for (final area in SkinArea.values) _areaSection(skin, area),
      const FileManagerSkinModeNotice(),
      _fileManagerSection(
        skin,
        showIndependentSkinShortcut: widget.showFileManagerSkinShortcut,
      ),
      _editorSection(skin),
      const SizedBox(height: 20),
      Text(
        context.l10n.skinTheCustomSkinIsActive971ce3,
        textAlign: TextAlign.center,
      ),
    ];
  }

  Widget _groupHeader(String title, String description) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  /// One page's colors. Every row edits only this page; "inherited" rows
  /// follow the shared palette until you pick a color of your own.
  Widget _areaSection(CustomAppSkin skin, SkinArea area) {
    final l10n = context.l10n;
    final overrides =
        (_darkColors ? skin.darkAreaColors : skin.lightAreaColors)[area.id];
    return _sectionCard(
      title: area.label(l10n),
      subtitle: area.description(l10n),
      children: [
        for (final token in area.tokens)
          ListTile(
            title: Text(token.label(l10n)),
            subtitle: Text(
              skin.areaColorOrNull(area, token, dark: _darkColors) != null
                  ? l10n.skinCustomColorTapToChangeOrReset
                  : token.hint(l10n),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _ColorDot(color: _areaTokenColor(area, token)),
            onTap: () => _pickAreaColor(
              area,
              token,
              title: '${token.label(l10n)} · ${area.label(l10n)}',
            ),
          ),
        if (overrides != null && overrides.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextButton.icon(
                onPressed: () => _save(
                  skin.withoutAreaColors(area, dark: _darkColors),
                ),
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(l10n.skinResetPageColors),
              ),
            ),
          ),
      ],
    );
  }

  Widget _componentColorsSection({
    required String title,
    required String subtitle,
    required List<(String, String, String)> roles,
  }) => _sectionCard(
    title: title,
    subtitle: subtitle,
    children: [
      for (final (role, label, explanation) in roles)
        ListTile(
          title: Text(label),
          subtitle: Text(
            _componentColors().containsKey(role)
                ? context.l10n.skinCustomColorTapToChangeOrReset
                : explanation,
          ),
          trailing: _ColorDot(color: _componentColor(role)),
          onTap: () => _pickColor(
            title: label,
            current: _componentColor(role),
            allowDefault: true,
            onColor: (value) => _setComponentColor(role, value),
            onDefault: () => _clearComponentColor(role),
          ),
        ),
    ],
  );

  Widget _colorRolesSection({
    required String title,
    required String description,
    required List<String> roles,
    List<(String, String, List<String>)>? groups,
    required Color Function(String role) colorFor,
    required ValueChanged<String> onPick,
  }) => _sectionCard(
    title: title,
    subtitle: description,
    children: [
      if (groups == null)
        for (final role in roles) _colorRoleTile(role, colorFor, onPick)
      else
        for (final group in groups)
          ExpansionTile(
            title: Text(group.$1),
            subtitle: Text(group.$2),
            children: [
              for (final role in group.$3)
                _colorRoleTile(role, colorFor, onPick),
            ],
          ),
    ],
  );

  Widget _colorRoleTile(
    String role,
    Color Function(String role) colorFor,
    ValueChanged<String> onPick,
  ) => ListTile(
    title: Text(skinColorRoleCopy(context)[role]?.$1 ?? skinRoleFallbackLabel(role)),
    subtitle: Text(
      skinColorRoleCopy(context)[role]?.$2 ??
          context.l10n.skinTapTheColorCircleToChooseAColor,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: _ColorDot(color: colorFor(role)),
    onTap: () => onPick(role),
  );

  Widget _fileManagerSection(
    CustomAppSkin skin, {
    required bool showIndependentSkinShortcut,
  }) => _sectionCard(
    title: context.l10n.skinFileManager,
    subtitle: context.l10n.skinFolderAndFileGlyphsTilesAndLabelColors,
    children: [
      _itemStyleEditor(
        context.l10n.fileSkinFoldersHeader,
        skin.fileManagerSkin.folders,
        (style) => _save(
          skin.copyWith(
            fileManagerSkin: skin.fileManagerSkin.copyWith(folders: style),
          ),
        ),
      ),
      _itemStyleEditor(
        context.l10n.filesTabLabel,
        skin.fileManagerSkin.files,
        (style) => _save(
          skin.copyWith(
            fileManagerSkin: skin.fileManagerSkin.copyWith(files: style),
          ),
        ),
      ),
      ListTile(
        title: Text(context.l10n.skinDetailsTextColor),
        subtitle: Text(
          skin.fileManagerSkin.detailsColor == null
              ? context.l10n.skinUseTheAppSSupportingTextColor
              : context.l10n.skinCustomColor,
        ),
        trailing: _ColorDot(color: skin.fileManagerSkin.detailsColor),
        onTap: () => _pickColor(
          title: context.l10n.skinDetailsTextColor,
          current:
              skin.fileManagerSkin.detailsColor ??
              Theme.of(context).colorScheme.onSurfaceVariant,
          allowDefault: true,
          onColor: (color) => _save(
            skin.copyWith(
              fileManagerSkin: skin.fileManagerSkin.copyWith(
                detailsColor: color,
              ),
            ),
          ),
          onDefault: () => _save(
            skin.copyWith(
              fileManagerSkin: skin.fileManagerSkin.copyWith(
                clearDetailsColor: true,
              ),
            ),
          ),
        ),
      ),
      SwitchListTile(
        value: skin.fileManagerSkin.monospaceNames,
        title: Text(context.l10n.skinMonospaceFileNames),
        onChanged: (value) => _save(
          skin.copyWith(
            fileManagerSkin: skin.fileManagerSkin.copyWith(
              monospaceNames: value,
            ),
          ),
        ),
      ),
      if (showIndependentSkinShortcut)
        ListTile(
          leading: Icon(
            Icons.folder_special_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(context.l10n.fileSkinScreenTitle),
          subtitle: Text(context.l10n.fileSkinUseIndependentStylesDescription),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const FileManagerSkinScreen(
                showAppSkinShortcut: false,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _itemStyleEditor(
    String title,
    SkinItemStyle style,
    ValueChanged<SkinItemStyle> onChanged,
  ) => ExpansionTile(
    title: Text(title),
    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    children: [
      _dropdown<SkinIconFamily>(
        label: context.l10n.fileSkinIconStyleLabel,
        value: style.iconFamily,
        options: SkinIconFamily.values,
        onChanged: (value) => onChanged(style.copyWith(iconFamily: value)),
      ),
      _dropdown<SkinContainerStyle>(
        label: context.l10n.skinBackgroundBehindTheIcon,
        value: style.container,
        options: SkinContainerStyle.values,
        onChanged: (value) => onChanged(style.copyWith(container: value)),
      ),
      _dropdown<SkinIconColorMode>(
        label: context.l10n.skinIconColorSource,
        value: style.iconColorMode,
        options: SkinIconColorMode.values,
        onChanged: (value) => onChanged(style.copyWith(iconColorMode: value)),
      ),
      if (style.iconColorMode == SkinIconColorMode.custom)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.fileSkinCustomIconColorLabel),
          trailing: _ColorDot(color: style.customIconColor),
          onTap: () => _pickColor(
            title: context.l10n.skinIconColorForItem(title),
            current:
                style.customIconColor ?? Theme.of(context).colorScheme.primary,
            onColor: (color) =>
                onChanged(style.copyWith(customIconColor: color)),
          ),
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.fileSkinNameColorLabel),
        subtitle: Text(
          style.nameColor == null
              ? context.l10n.skinUseTheAppSMainTextColor
              : context.l10n.skinCustomColor,
        ),
        trailing: _ColorDot(color: style.nameColor),
        onTap: () => _pickColor(
          title: context.l10n.skinNameColorForItem(title),
          current: style.nameColor ?? Theme.of(context).colorScheme.onSurface,
          allowDefault: true,
          onColor: (color) => onChanged(style.copyWith(nameColor: color)),
          onDefault: () => onChanged(style.copyWith(clearNameColor: true)),
        ),
      ),
    ],
  );

  Widget _editorSection(CustomAppSkin skin) => _sectionCard(
    title: context.l10n.skinTextEditor,
    subtitle:
        context.l10n.skinCanvasGutterCursorSelectionBackgroundAndSyntaxTemplate,
    children: [
      _editorColorTile(
        context.l10n.skinEditorTextColor,
        'foreground',
        subtitle: context.l10n.skinEditorCodeTextColorDescription,
      ),
      _editorColorTile(
        context.l10n.skinEditorInterfaceText,
        'chromeForeground',
        subtitle: context.l10n.skinEditorInterfaceTextDescription,
        allowDefault: true,
      ),
      _editorColorTile(
        context.l10n.skinEditorBackground,
        'background',
        subtitle: context.l10n.skinTheCanvasColorBehindTheCode,
      ),
      _editorColorTile(
        context.l10n.skinEditorPanelBackground,
        'panel',
        subtitle: context.l10n.skinEditorPanelBackgroundDescription,
        allowDefault: true,
      ),
      _editorColorTile(
        context.l10n.skinEditorLineNumbers,
        'gutter',
        subtitle: context.l10n.skinTheGutterAndLineNumbersBesideTheCode,
      ),
      _editorColorTile(
        context.l10n.skinEditorCursor,
        'cursor',
        subtitle: context.l10n.skinTheInsertionCaretColor,
      ),
      _editorColorTile(
        context.l10n.skinEditorSelectionHighlight,
        'selection',
        subtitle: context.l10n.skinTheBackgroundUsedToHighlightSelectedCode,
      ),
      const Divider(height: 24),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Text(
          context.l10n.textEditorSyntaxColorsSectionTitle,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      _editorColorTile(
        context.l10n.skinEditorKeywords,
        'keyword',
        allowDefault: true,
      ),
      _editorColorTile(
        context.l10n.skinEditorTypes,
        'type',
        allowDefault: true,
      ),
      _editorColorTile(
        context.l10n.skinEditorStrings,
        'string',
        allowDefault: true,
      ),
      _editorColorTile(
        context.l10n.skinEditorNumbers,
        'number',
        allowDefault: true,
      ),
      _editorColorTile(
        context.l10n.skinEditorFunctions,
        'function',
        allowDefault: true,
      ),
      _editorColorTile(
        context.l10n.skinEditorComments,
        'comment',
        allowDefault: true,
      ),
      const Divider(height: 24),
      _dropdown<EditorBackgroundOption>(
        label: context.l10n.skinEditorBackgroundTemplate,
        value: EditorBackgroundOption.values.firstWhere(
          (v) => v.name == _editorOption('background'),
          orElse: () => EditorBackgroundOption.matchSyntaxTheme,
        ),
        options: EditorBackgroundOption.values,
        onChanged: (value) => _setEditorOption('background', value.name),
      ),
      _dropdown<EditorSyntaxThemeOption>(
        label: context.l10n.skinSyntaxTemplate,
        value: EditorSyntaxThemeOption.values.firstWhere(
          (v) => v.name == _editorOption('syntax'),
          orElse: () => EditorSyntaxThemeOption.auto,
        ),
        options: EditorSyntaxThemeOption.values,
        onChanged: (value) => _setEditorOption('syntax', value.name),
      ),
    ],
  );

  Widget _editorColorTile(
    String title,
    String role, {
    String? subtitle,
    bool allowDefault = false,
  }) {
    final isCustom = _skin.editorColorOrNull(role, dark: _darkColors) != null;
    final sub =
        subtitle ??
        (allowDefault
            ? (isCustom
                  ? context.l10n.skinCustomColor
                  : context.l10n.textEditorDefaultFromTheme)
            : context.l10n.skinTapTheColorCircleToChooseAColor246981);
    return ListTile(
      title: Text(title),
      subtitle: Text(sub),
      trailing: _ColorDot(color: _editorColor(role)),
      onTap: () => _pickColor(
        title: title,
        current: _editorColor(role),
        allowDefault: allowDefault,
        onColor: (color) => _setEditorColor(role, color),
        onDefault: allowDefault ? () => _clearEditorColor(role) : null,
      ),
    );
  }

  Widget _dropdown<T extends Enum>({
    required String label,
    required T value,
    required List<T> options,
    required ValueChanged<T> onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: DropdownButtonFormField<T>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(
              _optionLabel(context, option),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (option) {
        if (option != null) onChanged(option);
      },
    ),
  );

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    ),
  );
}

String _optionLabel(BuildContext context, Enum option) {
  if (option is SkinIconFamily) {
    return switch (option) {
      SkinIconFamily.classic => context.l10n.skinDefaultVaultExplorerIcons,
      SkinIconFamily.filled => context.l10n.skinSolidIcons,
      SkinIconFamily.rounded => context.l10n.skinRoundedIcons,
      SkinIconFamily.outlined => context.l10n.skinOutlineIcons,
      SkinIconFamily.sharp => context.l10n.skinSquareCornerIcons,
    };
  }
  if (option is SkinContainerStyle) {
    return switch (option) {
      SkinContainerStyle.filled => context.l10n.skinTintedTileBehindTheIcon,
      SkinContainerStyle.outlined => context.l10n.skinOutlinedTileBehindTheIcon,
      SkinContainerStyle.none => context.l10n.skinNoTile,
    };
  }
  if (option is SkinIconColorMode) {
    return switch (option) {
      SkinIconColorMode.auto => context.l10n.skinAutomaticFileTypeOrFolderColor,
      SkinIconColorMode.primary => context.l10n.skinUseTheMainAppAccent,
      SkinIconColorMode.neutral => context.l10n.skinUseAMutedNeutralColor,
      SkinIconColorMode.custom => context.l10n.skinChooseAColorBelow,
    };
  }
  if (option is EditorBackgroundOption) {
    return switch (option) {
      EditorBackgroundOption.matchSyntaxTheme =>
        context.l10n.skinUseTheSyntaxThemeBackground,
      EditorBackgroundOption.amoledBlack => context.l10n.skinPureBlack,
      EditorBackgroundOption.darkSlate => context.l10n.skinDarkSlate,
      EditorBackgroundOption.classicLight => context.l10n.skinCleanWhite,
      EditorBackgroundOption.sepia => context.l10n.skinWarmSepia,
    };
  }
  if (option is EditorSyntaxThemeOption) {
    return switch (option) {
      EditorSyntaxThemeOption.auto =>
        context.l10n.skinAutomaticMatchLightOrDarkMode,
      EditorSyntaxThemeOption.oneDark =>
        context.l10n.textEditorSyntaxThemeOneDark,
      EditorSyntaxThemeOption.dracula =>
        context.l10n.textEditorSyntaxThemeDracula,
      EditorSyntaxThemeOption.githubLight =>
        context.l10n.textEditorSyntaxThemeGithubLight,
      EditorSyntaxThemeOption.monokai =>
        context.l10n.textEditorSyntaxThemeMonokai,
      EditorSyntaxThemeOption.nord => context.l10n.textEditorSyntaxThemeNord,
    };
  }
  return skinRoleFallbackLabel(option.name);
}

class _ColorDot extends StatelessWidget {
  final Color? color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
}
