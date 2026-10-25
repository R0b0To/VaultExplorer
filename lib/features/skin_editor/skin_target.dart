import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_skin_tokens.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/features/settings/widgets/skin_role_copy.dart';

/// One color of a custom skin that the floating picker can change.
///
/// A target knows how to read its value out of a skin, write a new one (or
/// clear it back to "inherit the default"), and describe itself to the
/// person. Everything that edits a skin goes through [write], so the picker,
/// the undo history and the saved skin can never disagree about where a color
/// lives.
sealed class SkinTarget {
  const SkinTarget();

  /// Stable identity, used for equality and for remembering a selection.
  String get id;

  /// Short human name, e.g. "Card".
  String title(BuildContext context);

  /// Where the color lives, e.g. the page name or "Shared palette".
  String group(BuildContext context);

  /// The color this target resolves to when the skin does not override it.
  Color inherited(ThemeData base);

  /// The skin's own value for this target, or null when it inherits.
  Color? customValue(CustomAppSkin skin, {required bool dark});

  /// A copy of [skin] with this target set to [color], or cleared when
  /// [color] is null.
  CustomAppSkin write(CustomAppSkin skin, Color? color, {required bool dark});

  /// Whether "reset to default" is a meaningful choice for this color.
  bool get canReset => true;

  bool isCustom(CustomAppSkin skin, {required bool dark}) =>
      customValue(skin, dark: dark) != null;

  /// What the person currently sees for this color.
  Color current(CustomAppSkin skin, ThemeData base, {required bool dark}) =>
      customValue(skin, dark: dark) ?? inherited(base);

  @override
  bool operator ==(Object other) =>
      other is SkinTarget && other.runtimeType == runtimeType && other.id == id;

  @override
  int get hashCode => Object.hash(runtimeType, id);
}

/// A token of one page ("Card" on the Files page). These are the colors a
/// page owns; changing one never touches another page.
final class AreaTokenTarget extends SkinTarget {
  final SkinArea area;
  final SkinToken token;

  const AreaTokenTarget(this.area, this.token);

  @override
  String get id => 'area:${area.id}.${token.id}';

  @override
  String title(BuildContext context) => token.label(context.l10n);

  @override
  String group(BuildContext context) => area.label(context.l10n);

  /// What the token's hint says it controls.
  String hint(BuildContext context) => token.hint(context.l10n);

  @override
  Color inherited(ThemeData base) {
    final tokens = base.extension<AppSkinTokens>();
    if (tokens == null) return const Color(0xFF808080);
    if (area == SkinArea.editor) {
      // The editor toolbar follows the editor's own colors until overridden.
      final chrome = tokens.editorChromeForeground;
      return switch (token) {
        SkinToken.appBar => Color.alphaBlend(
          chrome.withValues(alpha: 0.04),
          tokens.editorBackground,
        ),
        SkinToken.onAppBar => chrome,
        _ => tokens.areaColors(area).color(token),
      };
    }
    return tokens.areaColors(area).color(token);
  }

  @override
  Color? customValue(CustomAppSkin skin, {required bool dark}) =>
      skin.areaColorOrNull(area, token, dark: dark);

  @override
  CustomAppSkin write(CustomAppSkin skin, Color? color, {required bool dark}) =>
      skin.withAreaColor(area, token, color, dark: dark);
}

/// A Material color role of the shared palette. Pages without a section of
/// their own (unlock, camera, ...) use these directly.
final class SchemeRoleTarget extends SkinTarget {
  final String role;

  const SchemeRoleTarget(this.role);

  @override
  String get id => 'scheme:$role';

  @override
  String title(BuildContext context) => skinRoleTitle(context, role);

  @override
  String group(BuildContext context) => context.l10n.skinSharedPaletteTitle;

  @override
  Color inherited(ThemeData base) =>
      Color(colorSchemeToMap(base.colorScheme)[role] ?? 0xFF808080);

  @override
  Color? customValue(CustomAppSkin skin, {required bool dark}) {
    final value = (dark ? skin.darkColors : skin.lightColors)[role];
    return value == null ? null : Color(value);
  }

  @override
  CustomAppSkin write(CustomAppSkin skin, Color? color, {required bool dark}) {
    final values = Map<String, int>.from(
      dark ? skin.darkColors : skin.lightColors,
    );
    if (color == null) {
      values.remove(role);
    } else {
      values[role] = color.toARGB32();
    }
    return dark
        ? skin.copyWith(darkColors: values)
        : skin.copyWith(lightColors: values);
  }
}

/// Success / warning / bookmark colors.
final class SemanticRoleTarget extends SkinTarget {
  final String role;

  const SemanticRoleTarget(this.role);

  @override
  String get id => 'semantic:$role';

  @override
  String title(BuildContext context) => skinRoleTitle(context, role);

  @override
  String group(BuildContext context) => context.l10n.skinStatusAndBookmarkColors;

  @override
  Color inherited(ThemeData base) {
    final colors = base.extension<AppSemanticColors>();
    if (colors == null) return const Color(0xFF808080);
    return switch (role) {
      'success' => colors.success,
      'onSuccess' => colors.onSuccess,
      'successContainer' => colors.successContainer,
      'onSuccessContainer' => colors.onSuccessContainer,
      'warning' => colors.warning,
      'onWarning' => colors.onWarning,
      'warningContainer' => colors.warningContainer,
      'onWarningContainer' => colors.onWarningContainer,
      'bookmark' => colors.bookmark,
      _ => const Color(0xFF808080),
    };
  }

  @override
  Color? customValue(CustomAppSkin skin, {required bool dark}) {
    final value = (dark ? skin.darkSemanticColors : skin.lightSemanticColors)[role];
    return value == null ? null : Color(value);
  }

  @override
  CustomAppSkin write(CustomAppSkin skin, Color? color, {required bool dark}) {
    final values = Map<String, int>.from(
      dark ? skin.darkSemanticColors : skin.lightSemanticColors,
    );
    if (color == null) {
      values.remove(role);
    } else {
      values[role] = color.toARGB32();
    }
    return dark
        ? skin.copyWith(darkSemanticColors: values)
        : skin.copyWith(lightSemanticColors: values);
  }
}

/// The shared top bar / round button colors used by pages that do not set
/// their own.
final class ComponentRoleTarget extends SkinTarget {
  final String role;

  const ComponentRoleTarget(this.role);

  @override
  String get id => 'component:$role';

  @override
  String title(BuildContext context) {
    final l10n = context.l10n;
    return switch (role) {
      'appBarBackground' => '${l10n.skinAppBar} · ${l10n.textEditorBackgroundSectionTitle}',
      'appBarForeground' => '${l10n.skinAppBar} · ${l10n.skinTitleAndIcons}',
      'fabBackground' => '${l10n.skinFloatingActionButton} · ${l10n.skinButtonFill}',
      'fabForeground' => '${l10n.skinFloatingActionButton} · ${l10n.skinButtonIcon}',
      _ => skinRoleTitle(context, role),
    };
  }

  @override
  String group(BuildContext context) => context.l10n.skinSharedPaletteTitle;

  @override
  Color inherited(ThemeData base) {
    final tokens = base.extension<AppSkinTokens>();
    final cs = base.colorScheme;
    if (tokens == null) return cs.primary;
    return switch (role) {
      'appBarBackground' => tokens.appBarBackground,
      'appBarForeground' => tokens.appBarForeground,
      'fabBackground' => tokens.fabBackground,
      'fabForeground' => tokens.fabForeground,
      _ => cs.primary,
    };
  }

  @override
  Color? customValue(CustomAppSkin skin, {required bool dark}) {
    final value = (dark ? skin.darkComponentColors : skin.lightComponentColors)[role];
    return value == null ? null : Color(value);
  }

  @override
  CustomAppSkin write(CustomAppSkin skin, Color? color, {required bool dark}) {
    final values = Map<String, int>.from(
      dark ? skin.darkComponentColors : skin.lightComponentColors,
    );
    if (color == null) {
      values.remove(role);
    } else {
      values[role] = color.toARGB32();
    }
    return dark
        ? skin.copyWith(darkComponentColors: values)
        : skin.copyWith(lightComponentColors: values);
  }
}

/// Which part of a file or folder row a [FileItemTarget] colors.
enum FileItemPart { folderIcon, folderName, fileIcon, fileName, details }

/// A color of the file manager's own skin: the icon or name of files and of
/// folders, and the secondary text (date, size). These live in the skin's
/// file-manager section, not in a page's tokens, and are the same in the light
/// and the dark palette.
final class FileItemTarget extends SkinTarget {
  final FileItemPart part;

  const FileItemTarget(this.part);

  bool get isFolder =>
      part == FileItemPart.folderIcon || part == FileItemPart.folderName;

  bool get isIcon =>
      part == FileItemPart.folderIcon || part == FileItemPart.fileIcon;

  @override
  String get id => 'file:${part.name}';

  @override
  String title(BuildContext context) {
    final l10n = context.l10n;
    return switch (part) {
      FileItemPart.folderIcon => l10n.skinIconColorForItem(
        l10n.fileSkinFoldersHeader,
      ),
      FileItemPart.folderName => l10n.skinNameColorForItem(
        l10n.fileSkinFoldersHeader,
      ),
      FileItemPart.fileIcon => l10n.skinIconColorForItem(l10n.filesTabLabel),
      FileItemPart.fileName => l10n.skinNameColorForItem(l10n.filesTabLabel),
      FileItemPart.details => l10n.skinDetailsTextColor,
    };
  }

  @override
  String group(BuildContext context) => context.l10n.skinFileManager;

  @override
  Color inherited(ThemeData base) {
    switch (part) {
      case FileItemPart.folderIcon:
        return base.colorScheme.secondary;
      case FileItemPart.fileIcon:
        return base.colorScheme.primary;
      case FileItemPart.folderName:
      case FileItemPart.fileName:
        return const AreaTokenTarget(
          SkinArea.files,
          SkinToken.text,
        ).inherited(base);
      case FileItemPart.details:
        return const AreaTokenTarget(
          SkinArea.files,
          SkinToken.textSecondary,
        ).inherited(base);
    }
  }

  @override
  Color? customValue(CustomAppSkin skin, {required bool dark}) {
    final manager = skin.fileManagerSkin;
    switch (part) {
      case FileItemPart.folderIcon:
        return manager.folders.iconColorMode == SkinIconColorMode.custom
            ? manager.folders.customIconColor
            : null;
      case FileItemPart.fileIcon:
        return manager.files.iconColorMode == SkinIconColorMode.custom
            ? manager.files.customIconColor
            : null;
      case FileItemPart.folderName:
        return manager.folders.nameColor;
      case FileItemPart.fileName:
        return manager.files.nameColor;
      case FileItemPart.details:
        return manager.detailsColor;
    }
  }

  @override
  CustomAppSkin write(CustomAppSkin skin, Color? color, {required bool dark}) {
    final manager = skin.fileManagerSkin;
    SkinItemStyle icon(SkinItemStyle style) => color == null
        ? style.copyWith(
            iconColorMode: SkinIconColorMode.auto,
            clearCustomIconColor: true,
          )
        : style.copyWith(
            iconColorMode: SkinIconColorMode.custom,
            customIconColor: color,
          );
    SkinItemStyle name(SkinItemStyle style) => color == null
        ? style.copyWith(clearNameColor: true)
        : style.copyWith(nameColor: color);
    final updated = switch (part) {
      FileItemPart.folderIcon => manager.copyWith(
        folders: icon(manager.folders),
      ),
      FileItemPart.fileIcon => manager.copyWith(files: icon(manager.files)),
      FileItemPart.folderName => manager.copyWith(
        folders: name(manager.folders),
      ),
      FileItemPart.fileName => manager.copyWith(files: name(manager.files)),
      FileItemPart.details =>
        color == null
            ? manager.copyWith(clearDetailsColor: true)
            : manager.copyWith(detailsColor: color),
    };
    return skin.copyWith(fileManagerSkin: updated);
  }
}

/// A text-editor color: canvas, gutter, cursor, syntax colors, ...
final class EditorRoleTarget extends SkinTarget {
  final String role;

  const EditorRoleTarget(this.role);

  @override
  String get id => 'editor:$role';

  @override
  String title(BuildContext context) {
    final l10n = context.l10n;
    return switch (role) {
      'foreground' => l10n.skinEditorTextColor,
      'chromeForeground' => l10n.skinEditorInterfaceText,
      'background' => l10n.skinEditorBackground,
      'panel' => l10n.skinEditorPanelBackground,
      'gutter' => l10n.skinEditorLineNumbers,
      'cursor' => l10n.skinEditorCursor,
      'selection' => l10n.skinEditorSelectionHighlight,
      'keyword' => l10n.skinEditorKeywords,
      'type' => l10n.skinEditorTypes,
      'string' => l10n.skinEditorStrings,
      'number' => l10n.skinEditorNumbers,
      'function' => l10n.skinEditorFunctions,
      'comment' => l10n.skinEditorComments,
      _ => skinRoleTitle(context, role),
    };
  }

  @override
  String group(BuildContext context) => context.l10n.skinTextEditor;

  /// Roles with a sensible "follow the theme" value. The rest always carry a
  /// color of their own once the skin exists.
  @override
  bool get canReset =>
      role == 'panel' ||
      role == 'chromeForeground' ||
      editorSyntaxColorRoles.contains(role);

  @override
  Color inherited(ThemeData base) {
    final tokens = base.extension<AppSkinTokens>();
    if (tokens == null) return const Color(0xFF808080);
    return switch (role) {
      'foreground' => tokens.editorForeground,
      'chromeForeground' => tokens.editorChromeForeground,
      'background' => tokens.editorBackground,
      'panel' => tokens.editorPanelBackground,
      'gutter' => tokens.editorGutter,
      'cursor' => tokens.editorCursor,
      'selection' => tokens.editorSelection,
      _ => tokens.editorSyntaxColors[role] ?? tokens.editorForeground,
    };
  }

  @override
  Color? customValue(CustomAppSkin skin, {required bool dark}) =>
      skin.editorColorOrNull(role, dark: dark);

  @override
  CustomAppSkin write(CustomAppSkin skin, Color? color, {required bool dark}) {
    final values = Map<String, int>.from(
      dark ? skin.darkEditorColors : skin.lightEditorColors,
    );
    if (color == null) {
      values.remove(role);
    } else {
      values[role] = color.toARGB32();
    }
    if (dark) return skin.copyWith(darkEditorColors: values);
    final updated = skin.copyWith(lightEditorColors: values);
    if (color == null) return updated;
    // Keep the original flat fields populated so older versions can still
    // read a newly edited custom skin.
    final argb = color.toARGB32();
    return switch (role) {
      'background' => updated.copyWith(editorBackground: argb),
      'foreground' => updated.copyWith(editorForeground: argb),
      'gutter' => updated.copyWith(editorGutter: argb),
      'cursor' => updated.copyWith(editorCursor: argb),
      'selection' => updated.copyWith(editorSelection: argb),
      _ => updated,
    };
  }
}

/// "onSurfaceVariant" -> "On Surface Variant" for roles without their own
/// translated name.
String skinRoleTitle(BuildContext context, String role) =>
    skinColorRoleLabel(context, role);

/// Every color a person can reasonably want to change on [area], in the order
/// the skin editor lists them: the page's own tokens first, then the shared
/// palette basics every page falls back on.
List<SkinTarget> skinTargetsForArea(SkinArea? area) => [
  if (area != null) ...[
    for (final token in area.tokens) AreaTokenTarget(area, token),
    if (area == SkinArea.editor) ...[
      for (final role in editorColorRoles) EditorRoleTarget(role),
    ],
    if (area == SkinArea.files) ...[
      for (final part in FileItemPart.values) FileItemTarget(part),
    ],
  ] else ...[
    for (final role in _sharedBasics) SchemeRoleTarget(role),
    for (final role in appSharedComponentRoles) ComponentRoleTarget(role),
  ],
];

const _sharedBasics = <String>[
  'surface',
  'onSurface',
  'onSurfaceVariant',
  'primary',
  'onPrimary',
  'primaryContainer',
  'onPrimaryContainer',
  'secondary',
  'surfaceContainerHigh',
  'outline',
  'outlineVariant',
  'error',
];

/// Every target the picker can match a painted color against, with the page's
/// own tokens ranked before the shared palette so an ambiguous color reads as
/// the page's token.
List<SkinTarget> skinMatchTargets(SkinArea? area) => [
  if (area != null)
    for (final token in area.tokens) AreaTokenTarget(area, token),
  if (area == SkinArea.editor)
    for (final role in editorColorRoles) EditorRoleTarget(role),
  for (final role in appColorSchemeRoles) SchemeRoleTarget(role),
  for (final role in appSemanticColorRoles) SemanticRoleTarget(role),
  for (final role in appSharedComponentRoles) ComponentRoleTarget(role),
];
