// Persisted appearance choices for TextEditorScreen -- background,
// syntax theme (Phase 3, item 1), and relative line numbers (Phase 3,
// item 2). One shared set of choices across every file opened in the text
// editor, not per-file.
//
// Stored in the AppSettingsService settings blob so editor templates travel
// with settings export/import. The old standalone JSON file is read once and
// migrated automatically for existing installs.
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_theme.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

class TextEditorAppearancePrefs {
  final EditorBackgroundOption background;
  final EditorSyntaxThemeOption syntaxTheme;
  final bool relativeLineNumbers;
  final bool autoSave;
  final bool showLineNumbers;
  final bool showStatusBar;
   final bool showTabBar;
  final bool autoHideTabBar;
  final bool autoHideAppBar;
  final bool showAccessoryBar;
  final bool showAccessorySymbols;
  final bool showAccessoryActions;
  final bool showAccessoryScrubber;
  final double fontSize;
  final List<String> accessorySymbols;
  final List<String> accessoryActions;
  final Map<String, int> customColors;

  static const List<String> defaultSymbols = [
    'Tab',
    '{',
    '}',
    '[',
    ']',
    '(',
    ')',
    '=',
    '"',
    "'",
    ':',
    ';',
    '/',
    '\\',
    '<',
    '>',
    '_',
    '-',
    '&',
    '|',
    '!',
  ];

  static const List<String> defaultActions = [
    'undo',
    'redo',
    'cursorLeft',
    'cursorRight',
    'selectWord',
    'selectAll',
    'copy',
    'cut',
    'paste',
    'find',
    'wordWrap',
    'goToLine',
  ];

  static const List<String> allAvailableActions = [
    'undo',
    'redo',
    'cursorLeft',
    'cursorRight',
    'selectWord',
    'selectAll',
    'copy',
    'cut',
    'paste',
    'find',
    'wordWrap',
    'goToLine',
    'goToStart',
    'goToEnd',
    'indent',
    'outdent',
    'format',
    'readOnly',
  ];

  const TextEditorAppearancePrefs({
    this.background = EditorBackgroundOption.matchSyntaxTheme,
    this.syntaxTheme = EditorSyntaxThemeOption.auto,
    this.relativeLineNumbers = false,
    this.autoSave = false,
    this.showLineNumbers = true,
    this.showStatusBar = true,
    this.showTabBar = true,
    this.autoHideTabBar = true,
    this.autoHideAppBar = false,
    this.showAccessoryBar = true,
    this.showAccessorySymbols = true,
    this.showAccessoryActions = true,
    this.showAccessoryScrubber = false,
    this.fontSize = 14.0,
    this.accessorySymbols = defaultSymbols,
    this.accessoryActions = defaultActions,
    this.customColors = const {},
  });

  Color? customColor(String role) {
    final val = customColors[role];
    return val != null ? Color(val) : null;
  }

  TextEditorAppearancePrefs copyWith({
    EditorBackgroundOption? background,
    EditorSyntaxThemeOption? syntaxTheme,
    bool? relativeLineNumbers,
    bool? autoSave,
    bool? showLineNumbers,
    bool? showStatusBar,
  bool? showTabBar,
    bool? autoHideTabBar,
    bool? autoHideAppBar,
    bool? showAccessoryBar,
    bool? showAccessorySymbols,
    bool? showAccessoryActions,
    bool? showAccessoryScrubber,
    double? fontSize,
    List<String>? accessorySymbols,
    List<String>? accessoryActions,
    Map<String, int>? customColors,
  }) => TextEditorAppearancePrefs(
    background: background ?? this.background,
    syntaxTheme: syntaxTheme ?? this.syntaxTheme,
    relativeLineNumbers: relativeLineNumbers ?? this.relativeLineNumbers,
    autoSave: autoSave ?? this.autoSave,
    showLineNumbers: showLineNumbers ?? this.showLineNumbers,
    showStatusBar: showStatusBar ?? this.showStatusBar,
    showTabBar: showTabBar ?? this.showTabBar,
    autoHideTabBar: autoHideTabBar ?? this.autoHideTabBar,
    autoHideAppBar: autoHideAppBar ?? this.autoHideAppBar,
    showAccessoryBar: showAccessoryBar ?? this.showAccessoryBar,
    showAccessorySymbols: showAccessorySymbols ?? this.showAccessorySymbols,
    showAccessoryActions: showAccessoryActions ?? this.showAccessoryActions,
    showAccessoryScrubber: showAccessoryScrubber ?? this.showAccessoryScrubber,
    fontSize: fontSize ?? this.fontSize,
    accessorySymbols: accessorySymbols ?? this.accessorySymbols,
    accessoryActions: accessoryActions ?? this.accessoryActions,
    customColors: customColors ?? this.customColors,
  );

  Map<String, dynamic> toJson() => {
    'background': background.name,
    'syntaxTheme': syntaxTheme.name,
    'relativeLineNumbers': relativeLineNumbers,
    'autoSave': autoSave,
    'showLineNumbers': showLineNumbers,
    'showStatusBar': showStatusBar,
  'showTabBar': showTabBar,
    'autoHideTabBar': autoHideTabBar,
    'autoHideAppBar': autoHideAppBar,
    'showAccessoryBar': showAccessoryBar,
    'showAccessorySymbols': showAccessorySymbols,
    'showAccessoryActions': showAccessoryActions,
    'showAccessoryScrubber': showAccessoryScrubber,
    'fontSize': fontSize,
    'accessorySymbols': accessorySymbols,
    'accessoryActions': accessoryActions,
    'customColors': customColors,
  };

  factory TextEditorAppearancePrefs.fromJson(Map<String, dynamic> json) {
    return TextEditorAppearancePrefs(
      background: EditorBackgroundOption.values.firstWhere(
        (o) => o.name == json['background'],
        orElse: () => EditorBackgroundOption.matchSyntaxTheme,
      ),
      syntaxTheme: EditorSyntaxThemeOption.values.firstWhere(
        (o) => o.name == json['syntaxTheme'],
        orElse: () => EditorSyntaxThemeOption.auto,
      ),
      relativeLineNumbers: json['relativeLineNumbers'] == true,
      autoSave: json['autoSave'] == true,
      showLineNumbers: json['showLineNumbers'] ?? true,
      showStatusBar: json['showStatusBar'] ?? true,
      showTabBar: json['showTabBar'] ?? true,
      autoHideTabBar: json['autoHideTabBar'] ?? true,
      autoHideAppBar: json['autoHideAppBar'] == true,
      showAccessoryBar: json['showAccessoryBar'] ?? true,
      showAccessorySymbols: json['showAccessorySymbols'] ?? true,
      showAccessoryActions: json['showAccessoryActions'] ?? true,
      showAccessoryScrubber: json['showAccessoryScrubber'] ?? false,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      accessorySymbols:
          (json['accessorySymbols'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          defaultSymbols,
      accessoryActions:
          (json['accessoryActions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          defaultActions,
      customColors: (json['customColors'] is Map)
          ? (json['customColors'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            )
          : const {},
    );
  }
}

class TextEditorAppearanceService {
  const TextEditorAppearanceService();

  static Future<File> get _prefsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/text_editor_appearance.json');
  }

  Future<TextEditorAppearancePrefs> load() async {
    try {
      final settingsService = const AppSettingsService();
      final settings = await settingsService.loadSettings();
      if (settings.editorAppearancePrefs.isNotEmpty) {
        return TextEditorAppearancePrefs.fromJson(
          settings.editorAppearancePrefs,
        );
      }

      // One-time migration from the editor's previous standalone JSON file.
      // The app settings blob is now the source of truth and is included in
      // settings export/import.
      final file = await _prefsFile;
      if (await file.exists()) {
        final raw =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final prefs = TextEditorAppearancePrefs.fromJson(raw);
        await settingsService.updateSettings(
          (current) => current.copyWith(editorAppearancePrefs: prefs.toJson()),
        );
        try {
          await file.delete();
        } catch (_) {
          // The migrated app settings are already authoritative.
        }
        return prefs;
      }
    } catch (_) {
      // Fall through to defaults -- same reasoning as AppSettingsService:
      // a corrupt or unreadable prefs file just means starting from
      // defaults, not a functional failure.
    }
    return const TextEditorAppearancePrefs();
  }

  Future<void> save(TextEditorAppearancePrefs prefs) async {
    try {
      final settingsService = const AppSettingsService();
      await settingsService.updateSettings(
        (settings) => settings.copyWith(editorAppearancePrefs: prefs.toJson()),
      );
    } catch (_) {
      // The provider's in-memory state already reflects the change for
      // this session; a failed write only risks it not surviving a
      // restart, same as AppSettingsService.saveSettings.
    }
  }
}
