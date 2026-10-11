import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/core/theme/app_skin_tokens.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_theme.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_card.dart';
import 'package:vaultexplorer/features/settings/widgets/skin_color_picker_sheet.dart';

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

Map<String, (String, String)> _colorRoleCopy(BuildContext context) => {
  'primary': (
    context.l10n.skinActionAccent,
    context.l10n.skinEmphasisForActionIconsActiveControlsProgressAndLinks,
  ),
  'onPrimary': (
    context.l10n.skinTextAndIconsOnAccentButtons,
    context.l10n.skinForegroundForButtonsFilledWithTheActionAccentColor,
  ),
  'primaryContainer': (
    context.l10n.skinSelectionAndIconTileBackground,
    context.l10n.skinSelectedFilesAndVaultFormat076e52,
  ),
  'onPrimaryContainer': (
    context.l10n.skinTextAndIconsOnSelectionColors,
    context.l10n.skinForegroundForIconTilesAndOtherPrimaryContainerSurfaces,
  ),
  'primaryFixed': (
    context.l10n.skinSteadyMainAccent,
    context.l10n.skinAPrimaryAccentThatStaysTheSameInLightAndDarkSurfaces,
  ),
  'primaryFixedDim': (
    context.l10n.skinMutedSteadyMainAccent,
    context.l10n.skinASofterVersionOfTheSteadyPrimaryAccent,
  ),
  'onPrimaryFixed': (
    context.l10n.skinTextOnSteadyMainAccent,
    context.l10n.skinForegroundForPrimaryFixedColors,
  ),
  'onPrimaryFixedVariant': (
    context.l10n.skinMutedTextOnSteadyMainAccent,
    context.l10n.skinSecondaryForegroundForPrimaryFixedColors,
  ),
  'secondary': (
    context.l10n.skinSecondaryAccent,
    context.l10n.skinSupportingActionsAndLessProminentHighlights,
  ),
  'onSecondary': (
    context.l10n.skinTextOnSecondaryAccent,
    context.l10n.skinLabelsAndIconsOnSecondaryColoredAreas,
  ),
  'secondaryContainer': (
    context.l10n.skinSecondaryBackground,
    context.l10n.skinSoftFillForSupportingContent,
  ),
  'onSecondaryContainer': (
    context.l10n.skinTextOnSecondaryBackgrounds,
    context.l10n.skinForegroundForSecondaryContainers,
  ),
  'secondaryFixed': (
    context.l10n.skinSteadySecondaryAccent,
    context.l10n.skinASecondaryAccentThatStaysTheSameAcrossSurfaces,
  ),
  'secondaryFixedDim': (
    context.l10n.skinMutedSteadySecondaryAccent,
    context.l10n.skinASofterVersionOfTheSteadySecondaryAccent,
  ),
  'onSecondaryFixed': (
    context.l10n.skinTextOnSteadySecondaryAccent,
    context.l10n.skinForegroundForSecondaryFixedColors,
  ),
  'onSecondaryFixedVariant': (
    context.l10n.skinMutedTextOnSteadySecondaryAccent,
    context.l10n.skinSecondaryForegroundForSecondaryFixedColors,
  ),
  'tertiary': (
    context.l10n.skinExtraAccentColor,
    context.l10n.skinDecorativeHighlightsAndContrastingAccents,
  ),
  'onTertiary': (
    context.l10n.skinTextOnExtraAccent,
    context.l10n.skinLabelsAndIconsOnTertiaryColoredAreas,
  ),
  'tertiaryContainer': (
    context.l10n.skinExtraAccentBackground,
    context.l10n.skinSoftFillForTertiaryContent,
  ),
  'onTertiaryContainer': (
    context.l10n.skinTextOnExtraAccentBackgrounds,
    context.l10n.skinForegroundForTertiaryContainers,
  ),
  'tertiaryFixed': (
    context.l10n.skinSteadyExtraAccent,
    context.l10n.skinATertiaryAccentThatStaysTheSameAcrossSurfaces,
  ),
  'tertiaryFixedDim': (
    context.l10n.skinMutedSteadyExtraAccent,
    context.l10n.skinASofterVersionOfTheSteadyTertiaryAccent,
  ),
  'onTertiaryFixed': (
    context.l10n.skinTextOnSteadyExtraAccent,
    context.l10n.skinForegroundForTertiaryFixedColors,
  ),
  'onTertiaryFixedVariant': (
    context.l10n.skinMutedTextOnSteadyExtraAccent,
    context.l10n.skinSecondaryForegroundForTertiaryFixedColors,
  ),
  'error': (
    context.l10n.skinErrorColor,
    context.l10n.skinErrorsDestructiveActionsAndInvalidInput,
  ),
  'onError': (
    context.l10n.skinTextOnErrorColor,
    context.l10n.skinLabelsAndIconsOnErrorColoredAreas,
  ),
  'errorContainer': (
    context.l10n.skinErrorBackground,
    context.l10n.skinSoftFillBehindErrorMessages,
  ),
  'onErrorContainer': (
    context.l10n.skinTextOnErrorBackgrounds,
    context.l10n.skinForegroundForErrorContainers,
  ),
  'surface': (
    context.l10n.skinPageBackground,
    context.l10n.skinTheMainBackgroundBehindAppContent,
  ),
  'onSurface': (
    context.l10n.skinMainTextAndIcons,
    context.l10n.skinPrimaryContentDrawnOnPageAndCardBackgrounds,
  ),
  'surfaceDim': (
    context.l10n.skinDimmedBackground,
    context.l10n.skinTheDarkestNeutralSurfaceLayer,
  ),
  'surfaceBright': (
    context.l10n.skinBrightBackground,
    context.l10n.skinTheLightestNeutralSurfaceLayer,
  ),
  'surfaceContainerLowest': (
    context.l10n.skinDeepestCardLayer,
    context.l10n.skinTheLowestAndQuietestSurfaceContainer,
  ),
  'surfaceContainerLow': (
    context.l10n.skinLowCardLayer,
    context.l10n.skinSubtleCardsAndRecessedAreas,
  ),
  'surfaceContainer': (
    context.l10n.skinStandardCardLayer,
    context.l10n.skinCommonCardsAndGroupedContent,
  ),
  'surfaceContainerHigh': (
    context.l10n.skinRaisedCardLayer,
    context.l10n.skinRaisedCardsMenusAndAppBars,
  ),
  'surfaceContainerHighest': (
    context.l10n.skinTopCardLayer,
    context.l10n.skinProminentPanelsAndSelectedSurfaces,
  ),
  'onSurfaceVariant': (
    context.l10n.skinSecondaryTextAndIcons,
    context.l10n.skinDetailsHintsAndSupportingLabels,
  ),
  'outline': (
    context.l10n.skinStrongBorder,
    context.l10n.skinVisibleBordersAndSeparators,
  ),
  'outlineVariant': (
    context.l10n.skinSubtleBorder,
    context.l10n.skinQuietOutlinesAndLowEmphasisSeparators,
  ),
  'shadow': (
    context.l10n.skinShadowTint,
    context.l10n.skinTintUsedByElevatedSurfaces,
  ),
  'scrim': (
    context.l10n.skinModalBackdrop,
    context.l10n.skinTintBehindDialogsAndModalSheets,
  ),
  'inverseSurface': (
    context.l10n.skinInvertedSurface,
    context.l10n.skinAContrastingSurfaceForInverseElements,
  ),
  'onInverseSurface': (
    context.l10n.skinTextOnInvertedSurfaces,
    context.l10n.skinForegroundUsedOverInverseSurfaces,
  ),
  'inversePrimary': (
    context.l10n.skinInvertedMainAccent,
    context.l10n.skinPrimaryAccentUsedOnInverseSurfaces,
  ),
  'surfaceTint': (
    context.l10n.skinElevationTint,
    context.l10n.skinTintAppliedToElevatedSurfaces,
  ),
  'success': (
    context.l10n.skinSuccessColor,
    context.l10n.skinCompletedActionsAndPositiveStatus,
  ),
  'onSuccess': (
    context.l10n.skinTextOnSuccessColor,
    context.l10n.skinForegroundForSuccessColoredContent,
  ),
  'successContainer': (
    context.l10n.skinSuccessBackground,
    context.l10n.skinSoftFillBehindPositiveStatusMessages,
  ),
  'onSuccessContainer': (
    context.l10n.skinTextOnSuccessBackgrounds,
    context.l10n.skinForegroundForSuccessContainers,
  ),
  'warning': (
    context.l10n.skinWarningColor,
    context.l10n.skinCautionAttentionAndPendingStatus,
  ),
  'onWarning': (
    context.l10n.skinTextOnWarningColor,
    context.l10n.skinForegroundForWarningColoredContent,
  ),
  'warningContainer': (
    context.l10n.skinWarningBackground,
    context.l10n.skinSoftFillBehindWarningMessages,
  ),
  'onWarningContainer': (
    context.l10n.skinTextOnWarningBackgrounds,
    context.l10n.skinForegroundForWarningContainers,
  ),
  'bookmark': (
    context.l10n.skinBookmarkColor,
    context.l10n.skinSavedAndBookmarkedItems,
  ),
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

class CustomAppSkinScreen extends ConsumerStatefulWidget {
  final bool showControls;
  final bool? initialDarkColors;

  const CustomAppSkinScreen({
    super.key,
    this.showControls = false,
    this.initialDarkColors,
  });

  @override
  ConsumerState<CustomAppSkinScreen> createState() =>
      _CustomAppSkinScreenState();
}

class _CustomAppSkinScreenState extends ConsumerState<CustomAppSkinScreen> {
  bool _darkColors = false;
  bool _didInitializeBrightness = false;
  _PreviewPane _previewPane = _PreviewPane.app;
  _PreviewSelection? _previewSelection;
  bool _showAppOverflowMenu = false;
  bool _showFileOverflowMenu = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitializeBrightness) return;
    _darkColors =
        widget.initialDarkColors ??
        Theme.of(context).brightness == Brightness.dark;
    _didInitializeBrightness = true;
  }

  CustomAppSkin get _skin => ref.read(appSkinSettingsProvider).customAppSkin;

  void _save(CustomAppSkin skin) =>
      ref.read(appSkinSettingsProvider.notifier).setCustomAppSkin(skin);

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

  void _setSemanticColor(String role, Color color) {
    final values = Map<String, int>.from(_semanticColors())
      ..[role] = color.toARGB32();
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

  Color _storedColor(Map<String, int> colors, String role) =>
      Color(colors[role] ?? 0xFF808080);

  void _selectPreview(String id, String title, String explanation) {
    setState(() {
      _previewSelection = _PreviewSelection(id, title, explanation);
    });
  }

  Color _previewSelectionColor(String id) {
    final cs = Theme.of(context).colorScheme;
    final appColors = _schemeColors();
    if (id.startsWith('app:')) {
      final role = id.substring(4);
      return _storedColor(appColors, role);
    }
    if (id.startsWith('semantic:')) {
      return _storedColor(_semanticColors(), id.substring(9));
    }
    if (id.startsWith('component:')) {
      return _componentColor(id.substring(10));
    }
    if (id.startsWith('editor:')) return _editorColor(id.substring(7));
    final skin = _skin.fileManagerSkin;
    Color iconColor(SkinItemStyle style, {required bool folder}) =>
        switch (style.iconColorMode) {
          SkinIconColorMode.primary => _storedColor(appColors, 'primary'),
          SkinIconColorMode.neutral => _storedColor(
            appColors,
            'onSurfaceVariant',
          ),
          SkinIconColorMode.custom =>
            style.customIconColor ?? _storedColor(appColors, 'primary'),
          SkinIconColorMode.auto => _storedColor(
            appColors,
            folder ? 'secondary' : 'primary',
          ),
        };
    return switch (id) {
      'file:folderIcon' => iconColor(skin.folders, folder: true),
      'file:folderName' =>
        skin.folders.nameColor ?? _storedColor(appColors, 'onSurface'),
      'file:fileIcon' => iconColor(skin.files, folder: false),
      'file:fileName' =>
        skin.files.nameColor ?? _storedColor(appColors, 'onSurface'),
      'file:details' =>
        skin.detailsColor ?? _storedColor(appColors, 'onSurfaceVariant'),
      _ => cs.primary,
    };
  }

  Future<void> _editPreviewSelection() async {
    final selection = _previewSelection;
    if (selection == null) return;
    final id = selection.id;
    if (id.startsWith('app:')) {
      final role = id.substring(4);
      return _pickColor(
        title: selection.title,
        current: _previewSelectionColor(id),
        onColor: (value) => _setSchemeColor(role, value),
      );
    }
    if (id.startsWith('semantic:')) {
      final role = id.substring(9);
      return _pickColor(
        title: selection.title,
        current: _previewSelectionColor(id),
        onColor: (value) => _setSemanticColor(role, value),
      );
    }
    if (id.startsWith('component:')) {
      final role = id.substring(10);
      return _pickColor(
        title: selection.title,
        current: _componentColor(role),
        allowDefault: true,
        onColor: (value) => _setComponentColor(role, value),
        onDefault: () => _clearComponentColor(role),
      );
    }
    if (id.startsWith('editor:')) {
      final role = id.substring(7);
      final allowDefault = editorSyntaxColorRoles.contains(role);
      return _pickColor(
        title: selection.title,
        current: _editorColor(role),
        allowDefault: allowDefault,
        onColor: (value) => _setEditorColor(role, value),
        onDefault: allowDefault ? () => _clearEditorColor(role) : null,
      );
    }
    final customSkin = _skin;
    final fileSkin = customSkin.fileManagerSkin;
    switch (id) {
      case 'file:folderIcon':
        final style = fileSkin.folders;
        return _pickColor(
          title: selection.title,
          current: style.customIconColor ?? _previewSelectionColor(id),
          onColor: (value) => _save(
            customSkin.copyWith(
              fileManagerSkin: fileSkin.copyWith(
                folders: style.copyWith(
                  iconColorMode: SkinIconColorMode.custom,
                  customIconColor: value,
                ),
              ),
            ),
          ),
        );
      case 'file:folderName':
        final style = fileSkin.folders;
        return _pickColor(
          title: selection.title,
          current: style.nameColor ?? _previewSelectionColor(id),
          allowDefault: true,
          onColor: (value) => _save(
            customSkin.copyWith(
              fileManagerSkin: fileSkin.copyWith(
                folders: style.copyWith(nameColor: value),
              ),
            ),
          ),
          onDefault: () => _save(
            customSkin.copyWith(
              fileManagerSkin: fileSkin.copyWith(
                folders: style.copyWith(clearNameColor: true),
              ),
            ),
          ),
        );
      case 'file:fileIcon':
        final style = fileSkin.files;
        return _pickColor(
          title: selection.title,
          current: style.customIconColor ?? _previewSelectionColor(id),
          onColor: (value) => _save(
            customSkin.copyWith(
              fileManagerSkin: fileSkin.copyWith(
                files: style.copyWith(
                  iconColorMode: SkinIconColorMode.custom,
                  customIconColor: value,
                ),
              ),
            ),
          ),
        );
      case 'file:fileName':
        final style = fileSkin.files;
        return _pickColor(
          title: selection.title,
          current: style.nameColor ?? _previewSelectionColor(id),
          allowDefault: true,
          onColor: (value) => _save(
            customSkin.copyWith(
              fileManagerSkin: fileSkin.copyWith(
                files: style.copyWith(nameColor: value),
              ),
            ),
          ),
          onDefault: () => _save(
            customSkin.copyWith(
              fileManagerSkin: fileSkin.copyWith(
                files: style.copyWith(clearNameColor: true),
              ),
            ),
          ),
        );
      case 'file:details':
        return _pickColor(
          title: selection.title,
          current: fileSkin.detailsColor ?? _previewSelectionColor(id),
          allowDefault: true,
          onColor: (value) => _save(
            customSkin.copyWith(
              fileManagerSkin: fileSkin.copyWith(detailsColor: value),
            ),
          ),
          onDefault: () => _save(
            customSkin.copyWith(
              fileManagerSkin: fileSkin.copyWith(clearDetailsColor: true),
            ),
          ),
        );
    }
  }

  Widget _previewTarget({
    required String id,
    required String title,
    required String explanation,
    required Widget child,
    VoidCallback? onTap,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
  }) {
    final isSelected = _previewSelection?.id == id;
    return Tooltip(
      message: context.l10n.skinSelectPreviewElement(title),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap ?? () => _selectPreview(id, title, explanation),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: isSelected
                  ? _storedColor(_schemeColors(), 'primary')
                  : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: child,
        ),
      ),
    );
  }

  Widget _previewInspector() {
    final selection = _previewSelection;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (selection != null) ...[
              _ColorDot(color: _previewSelectionColor(selection.id)),
              const SizedBox(width: 12),
            ] else ...[
              Icon(Icons.touch_app_rounded, color: cs.primary),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selection?.title ?? context.l10n.skinTapAnyPreviewElement,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    selection == null
                        ? '${context.l10n.skinChooseAnAppFileOrEditorColorToSeeWhatItControls} ${context.l10n.skinMatchingElementsHighlightTogether}'
                        : '${selection.explanation} ${context.l10n.skinMatchingElementsHighlightTogether}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (selection != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: _editPreviewSelection,
                  icon: const Icon(Icons.colorize_rounded),
                  label: Text(context.l10n.hashVerifierChangeManifestButton),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(appSkinSettingsProvider).customAppSkin;
    if (widget.showControls) return _buildControlsPage(skin);
    return _buildPreviewPage(skin);
  }

  Widget _buildPreviewPage(CustomAppSkin skin) => Scaffold(
    appBar: AppBar(
      title: Text(skin.name),
      actions: [
        IconButton(
          tooltip: context.l10n.skinCustomizeSkin,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CustomAppSkinScreen(
                showControls: true,
                initialDarkColors: _darkColors,
              ),
            ),
          ),
          icon: const Icon(Icons.tune_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.fileSkinPreviewHeader,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.light_mode_rounded),
                      label: Text(context.l10n.skinLight),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.dark_mode_rounded),
                      label: Text(context.l10n.skinDark),
                    ),
                  ],
                  selected: {_darkColors},
                  onSelectionChanged: (selection) => setState(() {
                    _darkColors = selection.first;
                    _previewSelection = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _previewPaneChip(
                  _PreviewPane.app,
                  context.l10n.skinApp,
                  Icons.dashboard_rounded,
                ),
                _previewPaneChip(
                  _PreviewPane.fileManager,
                  context.l10n.filesTabLabel,
                  Icons.folder_copy_rounded,
                ),
                _previewPaneChip(
                  _PreviewPane.editor,
                  context.l10n.skinEditor,
                  Icons.code_rounded,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(child: _livePreview(skin)),
            const SizedBox(height: 10),
            _previewInspector(),
          ],
        ),
      ),
    ),
  );

  Widget _previewPaneChip(_PreviewPane pane, String label, IconData icon) =>
      ChoiceChip(
        selected: _previewPane == pane,
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onSelected: (_) => setState(() {
          _previewPane = pane;
          _previewSelection = null;
        }),
      );

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
        colors: _schemeColors(),
        onPick: (role) => _pickColor(
          title: _colorRoleCopy(context)[role]?.$1 ?? _roleLabel(role),
          current: _storedColor(_schemeColors(), role),
          onColor: (value) => _setSchemeColor(role, value),
        ),
      ),
      _componentColorsSection(
        title: context.l10n.skinAppBar,
        subtitle:
            context.l10n.skinTheTopNavigationBarIsIndependentFromCardsAndPages,
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
        subtitle:
            context.l10n.skinItsFillAndIconColorAreSeparateFromSelectionColors,
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
      _componentColorsSection(
        title: context.l10n.skinDashboardVaultCards,
        subtitle:
            context.l10n.skinSetTheBackgroundForLockedAndMountedVaultCards,
        roles: [
          (
            'vaultCardBackground',
            context.l10n.skinLockedVaultCard,
            context.l10n.skinNeutralVaultCardFill,
          ),
          (
            'mountedVaultCardBackground',
            context.l10n.skinMountedVaultCard,
            context.l10n.skinSeparateFillForAnUnlockedMountedVault,
          ),
        ],
      ),
      _colorRolesSection(
        title: context.l10n.skinFineTuneAppColors,
        description:
            context.l10n.skinAdvancedMaterialColorsForLessCommonElements,
        roles: advancedRoles,
        groups: advancedGroups,
        colors: _schemeColors(),
        onPick: (role) => _pickColor(
          title: _colorRoleCopy(context)[role]?.$1 ?? _roleLabel(role),
          current: _storedColor(_schemeColors(), role),
          onColor: (value) => _setSchemeColor(role, value),
        ),
      ),
      _colorRolesSection(
        title: context.l10n.skinStatusAndBookmarkColors,
        description:
            context.l10n.skinColorsForSuccessWarningsErrorsAndBookmarks,
        roles: appSemanticColorRoles,
        colors: _semanticColors(),
        onPick: (role) => _pickColor(
          title: _colorRoleCopy(context)[role]?.$1 ?? _roleLabel(role),
          current: _storedColor(_semanticColors(), role),
          onColor: (value) => _setSemanticColor(role, value),
        ),
      ),
      _fileManagerSection(skin),
      _editorSection(skin),
      const SizedBox(height: 20),
      Text(
        context.l10n.skinTheCustomSkinIsActive971ce3,
        textAlign: TextAlign.center,
      ),
    ];
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
    required Map<String, int> colors,
    required ValueChanged<String> onPick,
  }) => _sectionCard(
    title: title,
    subtitle: description,
    children: [
      if (groups == null)
        for (final role in roles) _colorRoleTile(role, colors, onPick)
      else
        for (final group in groups)
          ExpansionTile(
            title: Text(group.$1),
            subtitle: Text(group.$2),
            children: [
              for (final role in group.$3) _colorRoleTile(role, colors, onPick),
            ],
          ),
    ],
  );

  Widget _colorRoleTile(
    String role,
    Map<String, int> colors,
    ValueChanged<String> onPick,
  ) => ListTile(
    title: Text(_colorRoleCopy(context)[role]?.$1 ?? _roleLabel(role)),
    subtitle: Text(
      _colorRoleCopy(context)[role]?.$2 ??
          context.l10n.skinTapTheColorCircleToChooseAColor,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: _ColorDot(color: _storedColor(colors, role)),
    onTap: () => onPick(role),
  );

  Widget _livePreview(CustomAppSkin skin) {
    final baseTheme = Theme.of(context);
    final previewColorScheme = _editorColorScheme();
    final baseSemantic =
        baseTheme.extension<AppSemanticColors>() ??
        (_darkColors ? AppSemanticColors.dark : AppSemanticColors.light);
    Color semantic(String role, Color fallback) =>
        Color(_semanticColors()[role] ?? fallback.toARGB32());
    final previewSemantic = baseSemantic.copyWith(
      success: semantic('success', baseSemantic.success),
      onSuccess: semantic('onSuccess', baseSemantic.onSuccess),
      successContainer: semantic(
        'successContainer',
        baseSemantic.successContainer,
      ),
      onSuccessContainer: semantic(
        'onSuccessContainer',
        baseSemantic.onSuccessContainer,
      ),
      warning: semantic('warning', baseSemantic.warning),
      onWarning: semantic('onWarning', baseSemantic.onWarning),
      warningContainer: semantic(
        'warningContainer',
        baseSemantic.warningContainer,
      ),
      onWarningContainer: semantic(
        'onWarningContainer',
        baseSemantic.onWarningContainer,
      ),
      bookmark: semantic('bookmark', baseSemantic.bookmark),
    );
    final previewTheme = baseTheme.copyWith(
      colorScheme: previewColorScheme,
      textTheme: baseTheme.textTheme.apply(
        bodyColor: previewColorScheme.onSurface,
        displayColor: previewColorScheme.onSurface,
      ),
      extensions: [
        for (final extension in baseTheme.extensions.values)
          if (extension is! AppSemanticColors) extension,
        previewSemantic,
      ],
    );
    final child = switch (_previewPane) {
      _PreviewPane.app => _appShellPreview(previewColorScheme),
      _PreviewPane.fileManager => _fileManagerPreview(
        skin,
        (role, fallback) => Color(_schemeColors()[role] ?? fallback.toARGB32()),
        previewColorScheme,
      ),
      _PreviewPane.editor => _editorScreenPreview(
        (role, fallback) => Color(_schemeColors()[role] ?? fallback.toARGB32()),
        previewColorScheme,
      ),
    };
    return Theme(
      data: previewTheme,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  Widget _appShellPreview(ColorScheme cs) {
    final page = cs.surface;
    return _previewCanvas(
      page,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewTarget(
            id: 'component:appBarBackground',
            title: context.l10n.skinAppBarBackground,
            explanation: context
                .l10n
                .skinTheDashboardAndOtherAppBarsUseThisIndependentColor,
            child: Container(
              height: 64,
              color: _componentColor('appBarBackground'),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _previewTarget(
                    id: 'component:appBarForeground',
                    title: context.l10n.skinDashboardMenuIcon,
                    explanation: context
                        .l10n
                        .skinTheHamburgerButtonUsesTheAppBarIconColor,
                    child: Icon(
                      Icons.menu_rounded,
                      color: _componentColor('appBarForeground'),
                    ),
                  ),
                  const SizedBox(width: 24),
                  _previewTarget(
                    id: 'component:appBarForeground',
                    title: context.l10n.skinDashboardTitle,
                    explanation: context
                        .l10n
                        .skinTheDashboardTitleUsesTheAppBarForegroundColor,
                    child: Text(
                      context.l10n.appNameVaultExplorer,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _componentColor('appBarForeground'),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _mountedVaultCardPreview(cs),
                ),
                if (_showAppOverflowMenu)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _dashboardOverflowMenu(cs),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _lockedVaultCardPreview(cs),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _statusBannerExamples(),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _surfaceTokenExamples(cs),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _previewTarget(
                        id: 'app:primary',
                        title: context.l10n.skinActionLabelAndIcon,
                        explanation:
                            context.l10n.skinTheActionAccentColorsLabelsb08a63,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded, color: cs.primary),
                              const SizedBox(width: 6),
                              Text(
                                context.l10n.addAVaultTitle,
                                style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _floatingActionPreview(
                        title: context.l10n.skinDashboardAddButton,
                        explanation: context
                            .l10n
                            .skinTheButtonFillAndPlusIconHaveSeparateSkinColors,
                        size: 56,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBannerExamples() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          context.l10n.skinStatusBannerExamples,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      _statusBannerPreview(
        fillId: 'semantic:successContainer',
        foregroundId: 'semantic:onSuccessContainer',
        title: context.l10n.skinSuccessBanner,
        message: context.l10n.skinPreviewChangesSaved,
        explanation: context.l10n.skinSuccessBannerUsesSuccessContainer,
      ),
      _statusBannerPreview(
        fillId: 'semantic:warningContainer',
        foregroundId: 'semantic:onWarningContainer',
        title: context.l10n.skinWarningBanner,
        message: context.l10n.skinPreviewStorageAlmostFull,
        explanation: context.l10n.skinWarningBannerUsesWarningContainer,
      ),
      _statusBannerPreview(
        fillId: 'app:errorContainer',
        foregroundId: 'app:onErrorContainer',
        title: context.l10n.skinErrorBanner,
        message: context.l10n.skinPreviewCouldNotUnlockVault,
        explanation: context.l10n.skinErrorBannerUsesErrorContainer,
      ),
    ],
  );

  Widget _statusBannerPreview({
    required String fillId,
    required String foregroundId,
    required String title,
    required String message,
    required String explanation,
  }) {
    final fill = _previewSelectionColor(fillId);
    final foreground = _previewSelectionColor(foregroundId);
    return _previewTarget(
      id: fillId,
      title: title,
      explanation: explanation,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: _previewTarget(
          id: foregroundId,
          title: title,
          explanation: context.l10n.skinStatusBannerTextColor,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _surfaceTokenExamples(ColorScheme colorScheme) {
    final roleCopy = _colorRoleCopy(context);
    final schemeColors = colorSchemeToMap(colorScheme);

    Widget sample(String role, Widget child) => _previewTarget(
      id: 'app:$role',
      title: roleCopy[role]!.$1,
      explanation: roleCopy[role]!.$2,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Color(schemeColors[role]!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      ),
    );

    Widget sampleLabel(String role) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          roleCopy[role]!.$1,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          roleCopy[role]!.$2,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            context.l10n.skinSurfaceAndBorderExamples,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        sample('surfaceContainerLowest', sampleLabel('surfaceContainerLowest')),
        sample(
          'surfaceContainerLow',
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.palette_outlined,
                  color: colorScheme.onSurface,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: sampleLabel('surfaceContainerLow')),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        sample(
          'surfaceContainer',
          Column(
            children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.tune_rounded, color: colorScheme.onSurface),
                title: Text(context.l10n.edit),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.error,
                ),
                title: Text(
                  context.l10n.remove,
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            ],
          ),
        ),
        sample(
          'surfaceContainerHigh',
          Row(
            children: [
              Icon(
                Icons.folder_open_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(child: sampleLabel('surfaceContainerHigh')),
              Icon(
                Icons.more_vert_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        sample(
          'surfaceContainerHighest',
          Row(
            children: [
              Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(child: sampleLabel('surfaceContainerHighest')),
              Icon(Icons.keyboard_rounded, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: _previewTarget(
                  id: 'app:outlineVariant',
                  title: roleCopy['outlineVariant']!.$1,
                  explanation: roleCopy['outlineVariant']!.$2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roleCopy['outlineVariant']!.$1,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Divider(height: 12, color: colorScheme.outlineVariant),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _previewTarget(
                  id: 'app:outline',
                  title: roleCopy['outline']!.$1,
                  explanation: roleCopy['outline']!.$2,
                  child: OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colorScheme.outline),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: Text(roleCopy['outline']!.$1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mountedVaultCardPreview(ColorScheme cs) {
    final isLight = !_darkColors;
    final usedFraction = 0.66;
    final cardTint = _componentColor('mountedVaultCardBackground');
    final progressColor = usedFraction > 0.90
        ? (isLight ? cs.error.withValues(alpha: 0.6) : cs.error)
        : usedFraction > 0.70
        ? (isLight ? cs.tertiary.withValues(alpha: 0.6) : cs.tertiary)
        : (isLight ? cs.primary.withValues(alpha: 0.6) : cs.primary);
    final progressBackground = isLight
        ? cs.primary.withValues(alpha: 0.12)
        : cs.onPrimaryContainer.withValues(alpha: 0.15);
    final icon = _previewTarget(
      id: 'app:primaryContainer',
      title: context.l10n.skinVaultCardAndIconBackground,
      explanation: context.l10n.skinTheIconTileUsesPrimary5c2f93,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: _previewTarget(
            id: 'app:onPrimaryContainer',
            title: context.l10n.skinVaultFormatIconColor,
            explanation:
                context.l10n.skinVaultFormatInitialsUseOnPrimaryContainer,
            child: ContainerFormatIcon(
              format: ContainerFormat.veracrypt,
              size: 26,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _previewTarget(
          id: 'app:onSurfaceVariant',
          title: context.l10n.skinVaultStorageDetails,
          explanation:
              context.l10n.skinFreeSpaceAndCapacityUseTheSupportingTextColor,
          child: Text(
            context.l10n.skin17GBFree5GB,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11.5,
              letterSpacing: -0.2,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 4),
        _previewTarget(
          id: 'app:primary',
          title: context.l10n.skinVaultStorageProgress,
          explanation: context.l10n.skinTheProgressBarUsesTheba7c98,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: usedFraction,
              minHeight: 4,
              backgroundColor: progressBackground,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ),
      ],
    );
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _previewTarget(
          id: 'app:primaryContainer',
          title: context.l10n.skinLockActionBackground,
          explanation:
              context.l10n.skinTheMountedVaultLockButtonUsesPrimaryContainer,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_open_rounded,
              size: 20,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 6),
        _previewTarget(
          id: 'app:onSurfaceVariant',
          title: context.l10n.skinVaultActionsIconColor,
          explanation:
              context.l10n.skinTheOverflowMenuUsesTheSupportingIconColor,
          onTap: () {
            _selectPreview(
              'app:onSurfaceVariant',
              context.l10n.skinVaultActionsIconColor,
              context.l10n.skinTheOverflowMenuUsesTheSupportingIconColor,
            );
            setState(() => _showAppOverflowMenu = !_showAppOverflowMenu);
          },
          child: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
        ),
      ],
    );
    final badge = Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(
        Icons.timer_outlined,
        size: 16,
        color: cs.onSurfaceVariant.withValues(alpha: 0.75),
      ),
    );

    return BaseContainerCard(
      onTap: () => _selectPreview(
        'component:mountedVaultCardBackground',
        context.l10n.skinMountedVaultCardBackground,
        context.l10n.skinThisIsTheBackgroundOfa8d0d3,
      ),
      icon: icon,
      iconBackgroundColor: cs.primaryContainer,
      avatarBadge: badge,
      title: context.l10n.skinPreviewMountedVaultName,
      titleContent: _previewTarget(
        id: 'app:onSurface',
        title: context.l10n.skinPreviewVaultName,
        explanation: context.l10n.skinMainTextColorAlsoColorsRegularMenuItems,
        child: Text(
          context.l10n.skinPreviewMountedVaultName,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.1,
            height: 1.2,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
      subtitle: subtitle,
      trailingAction: trailing,
      backgroundColor: cardTint,
    );
  }

  Widget _lockedVaultCardPreview(ColorScheme cs) => BaseContainerCard(
    onTap: () => _selectPreview(
      'component:vaultCardBackground',
      context.l10n.skinLockedVaultCardBackground,
      context.l10n.skinThisColorIsIndependentFromTheAppBarAndMountedVaultCard,
    ),
    icon: _previewTarget(
      id: 'app:onSurfaceVariant',
      title: context.l10n.skinLockedVaultFormatIcon,
      explanation:
          context.l10n.skinLockedVaultIconsUseTheSupportingTextAndIconColor,
      child: ContainerFormatIcon(
        format: ContainerFormat.cryptomator,
        size: 26,
        color: cs.onSurfaceVariant,
      ),
    ),
    iconBackgroundColor: cs.surfaceContainerHighest,
    title: context.l10n.skinSharedArchive,
    titleContent: _previewTarget(
      id: 'app:onSurface',
      title: context.l10n.skinPreviewVaultName,
      explanation: context.l10n.skinMainTextColorAlsoColorsRegularMenuItems,
      child: Text(
        context.l10n.skinSharedArchive,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.1,
          height: 1.2,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    ),
    subtitle: _previewTarget(
      id: 'app:onSurfaceVariant',
      title: context.l10n.skinLockedVaultStatusText,
      explanation:
          context.l10n.skinTheLockedStatusLabelUsesTheSupportingTextColor,
      child: Text(
        context.l10n.lockedContainerLabel,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontSize: 11.5,
          letterSpacing: -0.2,
          height: 1.2,
        ),
      ),
    ),
    trailingAction: _previewTarget(
      id: 'app:onSurfaceVariant',
      title: context.l10n.skinLockedVaultActionsIcon,
      explanation: context.l10n.skinTheOverflowMenuUsesTheSupportingIconColor,
      child: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
    ),
    backgroundColor: _componentColor('vaultCardBackground'),
  );

  Widget _dashboardOverflowMenu(ColorScheme cs) => _previewTarget(
    id: 'app:surfaceContainer',
    title: context.l10n.skinVaultActionsMenuBackground,
    explanation: context.l10n.skinTheEditAndRemovePopupUsesTheMenuSurfaceColor,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: 190,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _previewTarget(
            id: 'app:onSurface',
            title: context.l10n.skinEditMenuItem,
            explanation:
                context.l10n.skinMainTextColorAlsoColorsRegularMenuItems,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.tune_rounded, size: 20),
              title: Text(context.l10n.edit),
            ),
          ),
          _previewTarget(
            id: 'app:error',
            title: context.l10n.skinRemoveMenuItem,
            explanation: context.l10n.skinDestructiveActionsUseTheErrorColor,
            child: ListTile(
              dense: true,
              leading: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: cs.error,
              ),
              title: Text(
                context.l10n.remove,
                style: TextStyle(color: cs.error),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _fileManagerPreview(
    CustomAppSkin skin,
    Color Function(String, Color) color,
    ColorScheme cs,
  ) {
    final page = color('surface', cs.surface);
    final foreground = color('onSurface', cs.onSurface);
    final secondaryText = color('onSurfaceVariant', cs.onSurfaceVariant);
    final accent = color('primary', cs.primary);
    final details = skin.fileManagerSkin.detailsColor ?? secondaryText;
    return _previewCanvas(
      page,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewTarget(
            id: 'component:appBarBackground',
            title: context.l10n.skinFileManagerAppBar,
            explanation:
                context.l10n.skinFileBrowserToolbarsUseTheSameAppBarBackground,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: _componentColor('appBarBackground'),
                border: Border(
                  bottom: BorderSide(
                    color: color('outlineVariant', cs.outlineVariant),
                  ),
                ),
              ),
              child: Row(
                children: [
                  _previewTarget(
                    id: 'component:appBarForeground',
                    title: context.l10n.skinFileManagerBackButton,
                    explanation:
                        context.l10n.skinToolbarNavigationIconsUseThisColor,
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: _componentColor('appBarForeground'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _previewTarget(
                      id: 'component:appBarForeground',
                      title: context.l10n.skinFileManagerTitle,
                      explanation: context
                          .l10n
                          .skinTheCurrentFolderNameUsesTheAppBarForeground,
                      child: Text(
                        context.l10n.filesFilterDocuments,
                        style: TextStyle(
                          color: _componentColor('appBarForeground'),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  _previewTarget(
                    id: 'component:appBarForeground',
                    title: context.l10n.skinFileManagerAppBarActions,
                    explanation:
                        context.l10n.skinToolbarActionsUseThisIconColor,
                    child: Icon(
                      Icons.search_rounded,
                      color: _componentColor('appBarForeground'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.sort_rounded,
                    color: _componentColor('appBarForeground'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  context.l10n.vaultLabel,
                  style: TextStyle(color: secondaryText),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: secondaryText,
                  size: 18,
                ),
                Text(
                  context.l10n.filesFilterDocuments,
                  style: TextStyle(color: foreground),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Column(
              children: [
                _filePreviewRow(
                  label: context.l10n.skinProjects,
                  details: context.l10n.skinFolder12Items,
                  style: skin.fileManagerSkin.folders,
                  isFolder: true,
                  selected: false,
                  colorScheme: cs,
                  foreground: foreground,
                  secondary: secondaryText,
                  primary: accent,
                  monospaceNames: skin.fileManagerSkin.monospaceNames,
                  detailsColor: details,
                  onOverflowTap: () => setState(
                    () => _showFileOverflowMenu = !_showFileOverflowMenu,
                  ),
                ),
                Divider(
                  height: 1,
                  indent: 58,
                  color: color('outlineVariant', cs.outlineVariant),
                ),
                _filePreviewRow(
                  label: 'Notes.txt',
                  details: context.l10n.skinTextFile4KB,
                  style: skin.fileManagerSkin.files,
                  isFolder: false,
                  selected: true,
                  colorScheme: cs,
                  foreground: foreground,
                  secondary: secondaryText,
                  primary: accent,
                  monospaceNames: skin.fileManagerSkin.monospaceNames,
                  detailsColor: details,
                  onOverflowTap: () => setState(
                    () => _showFileOverflowMenu = !_showFileOverflowMenu,
                  ),
                ),
                Divider(
                  height: 1,
                  indent: 58,
                  color: color('outlineVariant', cs.outlineVariant),
                ),
                _filePreviewRow(
                  label: 'Archive.zip',
                  details: context.l10n.skinCompressedFile28MB,
                  style: skin.fileManagerSkin.files,
                  isFolder: false,
                  selected: false,
                  colorScheme: cs,
                  foreground: foreground,
                  secondary: secondaryText,
                  primary: accent,
                  monospaceNames: skin.fileManagerSkin.monospaceNames,
                  detailsColor: details,
                  onOverflowTap: () => setState(
                    () => _showFileOverflowMenu = !_showFileOverflowMenu,
                  ),
                ),
                if (_showFileOverflowMenu)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _fileOverflowMenu(cs),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: accent, size: 18),
                const SizedBox(width: 6),
                Text(
                  context.l10n.skin3Items,
                  style: TextStyle(color: secondaryText, fontSize: 12),
                ),
                const Spacer(),
                _floatingActionPreview(
                  title: context.l10n.skinFileManagerAddButton,
                  explanation: context
                      .l10n
                      .skinTheButtonFillAndPlusIconHaveSeparateSkinColors,
                  size: 56,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingActionPreview({
    required String title,
    required String explanation,
    double size = 56,
  }) => _previewTarget(
    id: 'component:fabBackground',
    title: title,
    explanation: explanation,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _componentColor('fabBackground'),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: _previewTarget(
          id: 'component:fabForeground',
          title: context.l10n.skinAddButtonIconColor,
          explanation: context.l10n.skinThePlusIconUsesTheButtonForegroundColor,
          child: Icon(
            Icons.add_rounded,
            color: _componentColor('fabForeground'),
          ),
        ),
      ),
    ),
  );

  Widget _editorScreenPreview(
    Color Function(String, Color) color,
    ColorScheme cs,
  ) => Container(
    decoration: BoxDecoration(
      color: _editorColor('background'),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: color('surfaceContainerHigh', cs.surfaceContainerHigh),
          child: Row(
            children: [
              Icon(
                Icons.arrow_back_rounded,
                color: color('onSurfaceVariant', cs.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _previewTarget(
                  id: 'app:onSurface',
                  title: context.l10n.skinEditorFileName,
                  explanation: context
                      .l10n
                      .skinTheEditorToolbarUsesTheAppForegroundColor,
                  child: Text(
                    'main.dart',
                    style: TextStyle(
                      color: color('onSurface', cs.onSurface),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.undo_rounded,
                color: color('onSurfaceVariant', cs.onSurfaceVariant),
              ),
              const SizedBox(width: 10),
              Icon(Icons.save_outlined, color: color('primary', cs.primary)),
            ],
          ),
        ),
        _editorPreview(color('onSurface', cs.onSurface)),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          color: color(
            'surfaceContainerHigh',
            cs.surfaceContainerHigh,
          ).withValues(alpha: 0.5),
          child: Row(
            children: [
              Icon(
                Icons.code_rounded,
                color: color('primary', cs.primary),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.skinDartUTF8Ln3Col12,
                style: TextStyle(
                  color: color('onSurfaceVariant', cs.onSurfaceVariant),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.keyboard_rounded,
                color: color('onSurfaceVariant', cs.onSurfaceVariant),
                size: 18,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _previewCanvas(Color background, Widget child) => _previewTarget(
    id: 'app:surface',
    title: context.l10n.skinPageBackground,
    explanation: context.l10n.skinTheMainBackgroundBehindThisScreen,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      decoration: BoxDecoration(color: background),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: DefaultTextStyle(
          style: TextStyle(color: _storedColor(_schemeColors(), 'onSurface')),
          child: child,
        ),
      ),
    ),
  );

  Widget _filePreviewRow({
    required String label,
    required String details,
    required SkinItemStyle style,
    required bool isFolder,
    required bool selected,
    required ColorScheme colorScheme,
    required Color foreground,
    required Color secondary,
    required Color primary,
    required bool monospaceNames,
    required Color detailsColor,
    required VoidCallback onOverflowTap,
  }) {
    final iconColor = switch (style.iconColorMode) {
      SkinIconColorMode.primary => primary,
      SkinIconColorMode.neutral => secondary,
      SkinIconColorMode.custom => style.customIconColor ?? primary,
      SkinIconColorMode.auto => isFolder ? secondary : primary,
    };
    final icon = _filePreviewIcon(style.iconFamily, isFolder);
    final iconBackground = selected
        ? colorScheme.primaryContainer
        : isFolder
        ? colorScheme.secondaryContainer.withValues(alpha: 0.4)
        : colorScheme.surfaceContainerHighest;
    final decoration = switch (style.container) {
      SkinContainerStyle.filled => BoxDecoration(
        color: iconBackground,
        borderRadius: BorderRadius.circular(9),
      ),
      SkinContainerStyle.outlined => BoxDecoration(
        border: Border.all(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      SkinContainerStyle.none => null,
    };
    final row = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: selected ? 4 : 8,
        vertical: selected ? 3 : 7,
      ),
      child: Row(
        children: [
          _previewTarget(
            id: isFolder ? 'file:folderIcon' : 'file:fileIcon',
            title: isFolder
                ? context.l10n.skinFolderIconColor
                : context.l10n.skinFileIconColor,
            explanation: context.l10n.skinFileIconColorSettingDescription,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: decoration,
              child: Icon(icon, size: 21, color: iconColor),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewTarget(
                  id: isFolder ? 'file:folderName' : 'file:fileName',
                  title: isFolder
                      ? context.l10n.skinFolderNameColor
                      : context.l10n.skinFileNameColor,
                  explanation: context.l10n.skinFileNameColorSettingDescription,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: style.nameColor ?? foreground,
                      fontFamily: monospaceNames ? 'monospace' : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _previewTarget(
                  id: 'file:details',
                  title: context.l10n.skinFileRowDetailsColor,
                  explanation: context
                      .l10n
                      .skinTheSmallerDateSizeAndTypeLabelsUseThisColor,
                  child: Text(
                    details,
                    style: TextStyle(color: detailsColor, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          _previewTarget(
            id: 'app:onSurfaceVariant',
            title: context.l10n.skinFileActionOverflowIconColor,
            explanation: context
                .l10n
                .skinEachRowSThreeDotButtonUsesTheSupportingIconColor,
            onTap: () {
              _selectPreview(
                'app:onSurfaceVariant',
                context.l10n.skinFileActionOverflowIconColor,
                context
                    .l10n
                    .skinEachRowSThreeDotButtonUsesTheSupportingIconColor,
              );
              onOverflowTap();
            },
            child: Icon(Icons.more_vert_rounded, size: 20, color: secondary),
          ),
        ],
      ),
    );
    if (!selected) return row;
    return _previewTarget(
      id: 'app:primaryContainer',
      title: context.l10n.skinSelectedFileRow,
      explanation: context.l10n.skinSelectedRowsUseATranslucente0ff21,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: row,
      ),
    );
  }

  Widget _fileOverflowMenu(ColorScheme cs) => Theme(
    data: Theme.of(context).copyWith(colorScheme: cs),
    child: _previewTarget(
      id: 'app:surfaceContainer',
      title: context.l10n.skinFileActionsMenuBackground,
      explanation: context.l10n.skinTheFileActionsPopupUsesTheMenuSurfaceColor,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 190,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _previewTarget(
              id: 'app:onSurface',
              title: context.l10n.skinOpenFileMenuItem,
              explanation:
                  context.l10n.skinRegularFileActionsUseTheMainTextColor,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.open_in_new_rounded, size: 20),
                title: Text(context.l10n.skinOpen),
              ),
            ),
            _previewTarget(
              id: 'app:error',
              title: context.l10n.skinDeleteFileMenuItem,
              explanation: context.l10n.skinDestructiveActionsUseTheErrorColor,
              child: ListTile(
                dense: true,
                leading: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: cs.error,
                ),
                title: Text(
                  context.l10n.delete,
                  style: TextStyle(color: cs.error),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  IconData _filePreviewIcon(SkinIconFamily family, bool isFolder) =>
      switch ((family, isFolder)) {
        (SkinIconFamily.classic, true) ||
        (SkinIconFamily.rounded, true) => Icons.folder_rounded,
        (SkinIconFamily.outlined, true) => Icons.folder_outlined,
        (SkinIconFamily.filled, true) ||
        (SkinIconFamily.sharp, true) => Icons.folder,
        (SkinIconFamily.classic, false) ||
        (SkinIconFamily.rounded, false) => Icons.description_rounded,
        (SkinIconFamily.outlined, false) => Icons.description_outlined,
        (SkinIconFamily.filled, false) ||
        (SkinIconFamily.sharp, false) => Icons.description,
      };

  Widget _editorPreview(Color foreground) {
    final background = _editorColor('background');
    final gutter = _editorColor('gutter');
    final fontColor = _editorColor('foreground');
    final syntaxOption = EditorSyntaxThemeOption.values.firstWhere(
      (option) => option.name == _editorOption('syntax'),
      orElse: () => EditorSyntaxThemeOption.auto,
    );
    final styles = syntaxOption.themeMap(
      _darkColors ? Brightness.dark : Brightness.light,
    );

    TextStyle syntax(String role) {
      final custom = _skin.editorColorOrNull(role, dark: _darkColors);
      if (custom != null) {
        return TextStyle(color: custom, fontFamily: 'monospace', height: 1.55);
      }
      final key = switch (role) {
        'keyword' => 'keyword',
        'type' => 'title.class_',
        'string' => 'string',
        'number' => 'number',
        'comment' => 'comment',
        'function' => 'built_in',
        _ => role,
      };
      return (styles[key] ?? styles['root'] ?? TextStyle(color: fontColor))
          .copyWith(fontFamily: 'monospace', height: 1.55);
    }

    final codeTextStyle = TextStyle(
      color: fontColor,
      fontFamily: 'monospace',
      height: 1.55,
    );

    return _previewTarget(
      id: 'editor:background',
      title: context.l10n.skinEditorBackground,
      explanation: context.l10n.skinTheCanvasColorBehindTheCode,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: gutter.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _previewTarget(
              id: 'editor:gutter',
              title: context.l10n.skinEditorLineNumbers,
              explanation:
                  context.l10n.skinTheGutterAndLineNumbersBesideTheCode,
              child: Text(
                '1\n2\n3\n4\n5',
                style: TextStyle(
                  color: gutter,
                  fontFamily: 'monospace',
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: DefaultTextStyle(
                style: codeTextStyle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line 1: // Vault model
                    _previewTarget(
                      id: 'editor:comment',
                      title: context.l10n.skinEditorComments,
                      explanation: context.l10n.skinEditorCommentsExplanation,
                      child: Text(
                        '// Vault model',
                        style: syntax('comment'),
                      ),
                    ),
                    // Line 2: class Vault {
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _previewTarget(
                          id: 'editor:keyword',
                          title: context.l10n.skinEditorKeywords,
                          explanation:
                              context.l10n.skinEditorKeywordsExplanation,
                          child: Text('class ', style: syntax('keyword')),
                        ),
                        _previewTarget(
                          id: 'editor:type',
                          title: context.l10n.skinEditorTypes,
                          explanation: context.l10n.skinEditorTypesExplanation,
                          child: Text('Vault', style: syntax('type')),
                        ),
                        _previewTarget(
                          id: 'editor:foreground',
                          title: context.l10n.skinEditorTextColor,
                          explanation:
                              context.l10n.skinTheDefaultCodeAndEditorTextColor,
                          child: Text(' {', style: codeTextStyle),
                        ),
                      ],
                    ),
                    // Line 3:   name = "My vault";
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _previewTarget(
                          id: 'editor:foreground',
                          title: context.l10n.skinEditorTextColor,
                          explanation:
                              context.l10n.skinTheDefaultCodeAndEditorTextColor,
                          child: Text('  name = ', style: codeTextStyle),
                        ),
                        _previewTarget(
                          id: 'editor:string',
                          title: context.l10n.skinEditorStrings,
                          explanation:
                              context.l10n.skinEditorStringsExplanation,
                          child: Text('"My vault"', style: syntax('string')),
                        ),
                        _previewTarget(
                          id: 'editor:foreground',
                          title: context.l10n.skinEditorTextColor,
                          explanation:
                              context.l10n.skinTheDefaultCodeAndEditorTextColor,
                          child: Text(';', style: codeTextStyle),
                        ),
                      ],
                    ),
                    // Line 4:   count = 42;
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _previewTarget(
                          id: 'editor:foreground',
                          title: context.l10n.skinEditorTextColor,
                          explanation:
                              context.l10n.skinTheDefaultCodeAndEditorTextColor,
                          child: Text('  count = ', style: codeTextStyle),
                        ),
                        _previewTarget(
                          id: 'editor:number',
                          title: context.l10n.skinEditorNumbers,
                          explanation:
                              context.l10n.skinEditorNumbersExplanation,
                          child: Text('42', style: syntax('number')),
                        ),
                        _previewTarget(
                          id: 'editor:foreground',
                          title: context.l10n.skinEditorTextColor,
                          explanation:
                              context.l10n.skinTheDefaultCodeAndEditorTextColor,
                          child: Text(';', style: codeTextStyle),
                        ),
                      ],
                    ),
                    // Line 5:   | [open()] ; }
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _previewTarget(
                          id: 'editor:foreground',
                          title: context.l10n.skinEditorTextColor,
                          explanation:
                              context.l10n.skinTheDefaultCodeAndEditorTextColor,
                          child: Text('  ', style: codeTextStyle),
                        ),
                        _previewTarget(
                          id: 'editor:cursor',
                          title: context.l10n.skinEditorCursor,
                          explanation:
                              context.l10n.skinTheInsertionCaretColor,
                          child: SizedBox(
                            width: 14,
                            height: 20,
                            child: Center(
                              child: Container(
                                width: 2,
                                height: 16,
                                color: _editorColor('cursor'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        _previewTarget(
                          id: 'editor:selection',
                          title: context.l10n.skinEditorSelectionHighlight,
                          explanation: context
                              .l10n
                              .skinTheBackgroundUsedToHighlightSelectedCode,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                            ),
                            color: _editorColor('selection'),
                            child: _previewTarget(
                              id: 'editor:function',
                              title: context.l10n.skinEditorFunctions,
                              explanation:
                                  context.l10n.skinEditorFunctionsExplanation,
                              child: Text('open()', style: syntax('function')),
                            ),
                          ),
                        ),
                        _previewTarget(
                          id: 'editor:foreground',
                          title: context.l10n.skinEditorTextColor,
                          explanation:
                              context.l10n.skinTheDefaultCodeAndEditorTextColor,
                          child: Text('; }', style: codeTextStyle),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileManagerSection(CustomAppSkin skin) => _sectionCard(
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
        subtitle: context.l10n.skinTheDefaultCodeAndEditorTextColor,
      ),
      _editorColorTile(
        context.l10n.skinEditorBackground,
        'background',
        subtitle: context.l10n.skinTheCanvasColorBehindTheCode,
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
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
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
    final sub = subtitle ??
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

class _PreviewSelection {
  final String id;
  final String title;
  final String explanation;

  const _PreviewSelection(this.id, this.title, this.explanation);
}

enum _PreviewPane { app, fileManager, editor }

String _roleLabel(String role) => role
    .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
    .replaceFirstMapped(
      RegExp(r'^[a-z]'),
      (match) => match.group(0)!.toUpperCase(),
    );

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
  return _roleLabel(option.name);
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
