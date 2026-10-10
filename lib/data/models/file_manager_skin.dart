import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Which glyph set a skin draws file and folder icons from.
enum SkinIconFamily {
  /// The app's own mix: rounded folders, outlined file-type glyphs. Exactly
  /// what the file manager looked like before skins existed.
  classic,
  filled,
  rounded,
  outlined,
  sharp;

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        SkinIconFamily.classic => l10n.fileSkinIconFamilyDefault,
        SkinIconFamily.filled => l10n.fileSkinIconFamilyFilled,
        SkinIconFamily.rounded => l10n.fileSkinIconFamilyRounded,
        SkinIconFamily.outlined => l10n.fileSkinIconFamilyOutlined,
        SkinIconFamily.sharp => l10n.fileSkinIconFamilySharp,
      };

  String toJson() => name;

  static SkinIconFamily fromJson(Object? value) {
    for (final v in SkinIconFamily.values) {
      if (v.name == value) return v;
    }
    return SkinIconFamily.classic;
  }
}

/// How the tile behind an entry's icon is drawn: the tinted rounded square in
/// list rows, and the card in grid and masonry views.
enum SkinContainerStyle {
  /// Tinted fill (the classic look).
  filled,

  /// Transparent with a thin outline.
  outlined,

  /// No box at all -- just the icon.
  none;

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        SkinContainerStyle.filled => l10n.fileSkinContainerFilled,
        SkinContainerStyle.outlined => l10n.fileSkinContainerOutlined,
        SkinContainerStyle.none => l10n.fileSkinContainerNone,
      };

  String toJson() => name;

  static SkinContainerStyle fromJson(Object? value) {
    for (final v in SkinContainerStyle.values) {
      if (v.name == value) return v;
    }
    return SkinContainerStyle.filled;
  }
}

/// Where an entry's icon color comes from.
enum SkinIconColorMode {
  /// Files are tinted by type (PDF red, video purple, ...); folders use the
  /// theme's secondary color. The classic look.
  auto,

  /// The theme's primary/accent color.
  primary,

  /// A muted neutral -- the theme's `onSurfaceVariant`.
  neutral,

  /// A color the person picked ([SkinItemStyle.customIconColor]).
  custom;

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        SkinIconColorMode.auto => l10n.fileSkinColorAuto,
        SkinIconColorMode.primary => l10n.fileSkinColorAccent,
        SkinIconColorMode.neutral => l10n.fileSkinColorNeutral,
        SkinIconColorMode.custom => l10n.fileSkinColorCustom,
      };

  String toJson() => name;

  static SkinIconColorMode fromJson(Object? value) {
    for (final v in SkinIconColorMode.values) {
      if (v.name == value) return v;
    }
    return SkinIconColorMode.auto;
  }
}

Color? _colorFromJson(Object? value) =>
    value is num ? Color(value.toInt()) : null;

/// The look of one kind of entry -- either every file or every folder.
///
/// Files and folders are styled independently so a skin can, for example,
/// keep files as bare outlines while folders keep a tinted tile.
@immutable
class SkinItemStyle {
  final SkinIconFamily iconFamily;
  final SkinContainerStyle container;
  final SkinIconColorMode iconColorMode;

  /// Only consulted when [iconColorMode] is [SkinIconColorMode.custom].
  final Color? customIconColor;

  /// Color of the entry's name. Null follows the theme.
  final Color? nameColor;

  const SkinItemStyle({
    this.iconFamily = SkinIconFamily.classic,
    this.container = SkinContainerStyle.filled,
    this.iconColorMode = SkinIconColorMode.auto,
    this.customIconColor,
    this.nameColor,
  });

  SkinItemStyle copyWith({
    SkinIconFamily? iconFamily,
    SkinContainerStyle? container,
    SkinIconColorMode? iconColorMode,
    Color? customIconColor,
    bool clearCustomIconColor = false,
    Color? nameColor,
    bool clearNameColor = false,
  }) =>
      SkinItemStyle(
        iconFamily: iconFamily ?? this.iconFamily,
        container: container ?? this.container,
        iconColorMode: iconColorMode ?? this.iconColorMode,
        customIconColor: clearCustomIconColor
            ? null
            : (customIconColor ?? this.customIconColor),
        nameColor: clearNameColor ? null : (nameColor ?? this.nameColor),
      );

  Map<String, dynamic> toJson() => {
        'iconFamily': iconFamily.toJson(),
        'container': container.toJson(),
        'iconColorMode': iconColorMode.toJson(),
        'customIconColor': customIconColor?.toARGB32(),
        'nameColor': nameColor?.toARGB32(),
      };

  /// Tolerant of missing or malformed data: anything unreadable falls back to
  /// the classic value for that field, so a bad blob can never break the
  /// file manager.
  factory SkinItemStyle.fromJson(Object? raw) {
    if (raw is! Map) return const SkinItemStyle();
    return SkinItemStyle(
      iconFamily: SkinIconFamily.fromJson(raw['iconFamily']),
      container: SkinContainerStyle.fromJson(raw['container']),
      iconColorMode: SkinIconColorMode.fromJson(raw['iconColorMode']),
      customIconColor: _colorFromJson(raw['customIconColor']),
      nameColor: _colorFromJson(raw['nameColor']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkinItemStyle &&
          iconFamily == other.iconFamily &&
          container == other.container &&
          iconColorMode == other.iconColorMode &&
          customIconColor == other.customIconColor &&
          nameColor == other.nameColor;

  @override
  int get hashCode => Object.hash(
        iconFamily,
        container,
        iconColorMode,
        customIconColor,
        nameColor,
      );
}

/// A complete file-manager skin: how icons, their backgrounds and text look.
///
/// The default instance, [classic], reproduces the file manager exactly as it
/// looked before skins existed, so an install that never opens the skin
/// screen sees no change.
@immutable
class FileManagerSkin {
  final SkinItemStyle files;
  final SkinItemStyle folders;

  /// Color of the secondary text (date, size, type). Null follows the theme.
  final Color? detailsColor;

  /// Draw file and folder names in the bundled monospace font.
  final bool monospaceNames;

  const FileManagerSkin({
    this.files = const SkinItemStyle(),
    this.folders = const SkinItemStyle(),
    this.detailsColor,
    this.monospaceNames = false,
  });

  static const FileManagerSkin classic = FileManagerSkin();

  FileManagerSkin copyWith({
    SkinItemStyle? files,
    SkinItemStyle? folders,
    Color? detailsColor,
    bool clearDetailsColor = false,
    bool? monospaceNames,
  }) =>
      FileManagerSkin(
        files: files ?? this.files,
        folders: folders ?? this.folders,
        detailsColor:
            clearDetailsColor ? null : (detailsColor ?? this.detailsColor),
        monospaceNames: monospaceNames ?? this.monospaceNames,
      );

  /// The built-in preset this skin is identical to, or null when the person
  /// has tweaked individual options ("Custom").
  SkinPreset? get matchingPreset {
    for (final preset in SkinPreset.values) {
      if (preset.skin == this) return preset;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'files': files.toJson(),
        'folders': folders.toJson(),
        'detailsColor': detailsColor?.toARGB32(),
        'monospaceNames': monospaceNames,
      };

  factory FileManagerSkin.fromJson(Object? raw) {
    if (raw is! Map) return FileManagerSkin.classic;
    final mono = raw['monospaceNames'];
    return FileManagerSkin(
      files: SkinItemStyle.fromJson(raw['files']),
      folders: SkinItemStyle.fromJson(raw['folders']),
      detailsColor: _colorFromJson(raw['detailsColor']),
      monospaceNames: mono is bool ? mono : false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileManagerSkin &&
          files == other.files &&
          folders == other.folders &&
          detailsColor == other.detailsColor &&
          monospaceNames == other.monospaceNames;

  @override
  int get hashCode => Object.hash(files, folders, detailsColor, monospaceNames);
}

/// The built-in skins offered on the skin screen.
enum SkinPreset {
  classic,
  minimalOutline,
  frames,
  vivid,
  terminal;

  FileManagerSkin get skin => switch (this) {
        SkinPreset.classic => FileManagerSkin.classic,

        // Bare outlined icons in a quiet neutral, no boxes anywhere.
        SkinPreset.minimalOutline => const FileManagerSkin(
            files: SkinItemStyle(
              iconFamily: SkinIconFamily.outlined,
              container: SkinContainerStyle.none,
              iconColorMode: SkinIconColorMode.neutral,
            ),
            folders: SkinItemStyle(
              iconFamily: SkinIconFamily.outlined,
              container: SkinContainerStyle.none,
              iconColorMode: SkinIconColorMode.neutral,
            ),
          ),

        // Outlined icons inside thin outlined frames, in the accent color.
        SkinPreset.frames => const FileManagerSkin(
            files: SkinItemStyle(
              iconFamily: SkinIconFamily.outlined,
              container: SkinContainerStyle.outlined,
              iconColorMode: SkinIconColorMode.primary,
            ),
            folders: SkinItemStyle(
              iconFamily: SkinIconFamily.outlined,
              container: SkinContainerStyle.outlined,
              iconColorMode: SkinIconColorMode.primary,
            ),
          ),

        // Solid glyphs with no boxes: type-colored files, golden folders.
        SkinPreset.vivid => const FileManagerSkin(
            files: SkinItemStyle(
              iconFamily: SkinIconFamily.filled,
              container: SkinContainerStyle.none,
            ),
            folders: SkinItemStyle(
              iconFamily: SkinIconFamily.filled,
              container: SkinContainerStyle.none,
              iconColorMode: SkinIconColorMode.custom,
              customIconColor: Color(0xFFFFB300),
            ),
          ),

        // Sharp-cornered glyphs and monospaced names.
        SkinPreset.terminal => const FileManagerSkin(
            files: SkinItemStyle(
              iconFamily: SkinIconFamily.sharp,
              container: SkinContainerStyle.none,
              iconColorMode: SkinIconColorMode.primary,
            ),
            folders: SkinItemStyle(
              iconFamily: SkinIconFamily.sharp,
              container: SkinContainerStyle.none,
              iconColorMode: SkinIconColorMode.primary,
            ),
            monospaceNames: true,
          ),
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        SkinPreset.classic => l10n.fileSkinPresetClassic,
        SkinPreset.minimalOutline => l10n.fileSkinPresetMinimalOutline,
        SkinPreset.frames => l10n.fileSkinPresetFrames,
        SkinPreset.vivid => l10n.fileSkinPresetVivid,
        SkinPreset.terminal => l10n.fileSkinPresetTerminal,
      };
}
