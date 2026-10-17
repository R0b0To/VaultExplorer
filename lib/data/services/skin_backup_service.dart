import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/text_editor_appearance_service.dart';

final skinBackupServiceProvider = Provider<SkinBackupService>(
  (ref) => SkinBackupService(
    appSettingsService: ref.watch(appSettingsServiceProvider),
    toolbarService: ref.watch(fileManagerToolbarServiceProvider),
    fileIoApi: ref.watch(vaultFileIoApiProvider),
  ),
);

/// The interface section of a skin file, parsed but not yet applied.
///
/// [appSettings] and [toolbarConfig] are *partial*: only their interface
/// fields (see [AppSettings.interfaceToJson] and
/// [FileManagerToolbarConfig.interfaceToJson]) carry values from the file, and
/// [SkinBackupService.applyInterface] never copies anything else.
class ImportedInterface {
  final AppSettings appSettings;
  final FileManagerToolbarConfig toolbarConfig;

  /// Which skin was active when the file was written. [activeSkinId] is only
  /// set for [AppSkinPreset.custom].
  final AppSkinPreset? activePreset;
  final String? activeSkinId;

  const ImportedInterface({
    required this.appSettings,
    required this.toolbarConfig,
    this.activePreset,
    this.activeSkinId,
  });
}

/// A picked skin file. [interfaceSettings] is null for a file that only
/// carries skins (every file written before interface settings moved here,
/// and any single-skin export).
class ParsedSkinFile {
  final List<CustomAppSkin> skins;
  final ImportedInterface? interfaceSettings;

  const ParsedSkinFile({required this.skins, this.interfaceSettings});
}

/// What is persisted after [SkinBackupService.applyInterface], so callers can
/// push the real values into live state.
class AppliedInterface {
  final AppSettings settings;
  final FileManagerToolbarConfig toolbarConfig;

  const AppliedInterface({required this.settings, required this.toolbarConfig});
}

/// App skin -> Export/Import: skins plus, optionally, everything else that
/// decides how the app looks and is laid out.
///
/// The file is plain JSON:
///
/// ```
/// {
///   "format": "vault-explorer-skins",
///   "schemaVersion": 2,
///   "skins": [ ...custom skins... ],
///   "interface": {                       // only when exported with interface
///     "activeSkin": { "preset": "custom", "skinId": "skin-..." },
///     "app":         { ...AppSettings.interfaceToJson()... },
///     "fileManager": { ...FileManagerToolbarConfig.interfaceToJson()... }
///   }
/// }
/// ```
///
/// `app` holds theme mode and Material You, the follow-the-app-skin switches,
/// the file-manager icon style, the editor's appearance, default view mode and
/// sort, dashboard layout and authenticator display. `fileManager` holds the
/// toolbar order and visibility, list/grid/masonry sizing and style, detail
/// columns and the media viewer's button layout.
///
/// How the app *behaves* (locks, defaults, playback, language, ...) is not in
/// here; that is Settings -> Export ([SettingsBackupService]). A skin that is
/// exported on its own, or one of several, never carries an `interface`
/// section, so it stays safe to share.
///
/// Importing is additive for skins (see
/// [AppSkinSettingsNotifier.addImportedSkins]) and a replace for the interface
/// section, which the caller confirms with the person first.
class SkinBackupService {
  static const fileFormat = 'vault-explorer-skins';

  /// 2 adds the optional `interface` section. Version 1 files (skins only)
  /// are still read.
  static const schemaVersion = 2;

  SkinBackupService({
    required AppSettingsService appSettingsService,
    required FileManagerToolbarService toolbarService,
    required VaultFileIoApi fileIoApi,
  }) : _appSettingsService = appSettingsService,
       _toolbarService = toolbarService,
       _fileIoApi = fileIoApi;

  final AppSettingsService _appSettingsService;
  final FileManagerToolbarService _toolbarService;
  final VaultFileIoApi _fileIoApi;

  Future<String> buildJson(
    List<CustomAppSkin> skins, {
    required bool includeInterface,
  }) async {
    final payload = <String, dynamic>{
      'format': fileFormat,
      'schemaVersion': schemaVersion,
      'skins': skins.map((skin) => skin.toJson()).toList(),
    };

    if (includeInterface) {
      // Loading through the editor service first migrates preferences that
      // still sit in the editor's old standalone file, and yields the
      // defaults when the person never changed anything.
      final editor = await const TextEditorAppearanceService().load();
      final settings = await _appSettingsService.loadSettings();
      final toolbar = await _toolbarService.load();
      // The toolbar config owns the file-manager skin override; the copy in
      // AppSettings mirrors it (see FileManagerToolbarSettings.setSkin).
      final interfaceSettings = settings.copyWith(
        fileManagerSkin: toolbar.skin,
        editorAppearancePrefs: editor.toJson(),
      );
      payload['interface'] = {
        'activeSkin': {
          'preset': settings.appSkinPreset.id,
          if (settings.appSkinPreset == AppSkinPreset.custom)
            'skinId': settings.customAppSkin.id,
        },
        'app': interfaceSettings.interfaceToJson(),
        'fileManager': toolbar.interfaceToJson(),
      };
    }
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Opens the system "save as" picker. Returns false if the person cancelled,
  /// the write failed, or there was nothing to export.
  Future<bool> exportToFile(
    List<CustomAppSkin> skins, {
    bool includeInterface = false,
  }) async {
    if (skins.isEmpty && !includeInterface) return false;
    final json = await buildJson(skins, includeInterface: includeInterface);
    return _fileIoApi.exportAppSettingsFile(
      json,
      _fileName(skins, includeInterface),
    );
  }

  /// Opens the system file picker and parses the picked file without
  /// persisting anything. Returns null if the person cancelled. Throws a
  /// [FormatException] if the file is not a skin file.
  Future<ParsedSkinFile?> pickAndParseFile() async {
    final raw = await _fileIoApi.importAppSettingsFile();
    if (raw == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('This file is not a valid skin export.');
    }

    final payloads = <Object?>[];
    ImportedInterface? interfaceSettings;
    if (decoded is Map && decoded['skins'] is List) {
      payloads.addAll(decoded['skins'] as List);
      if (decoded.containsKey('interface')) {
        interfaceSettings = _parseInterface(decoded['interface']);
      }
    } else if (decoded is Map && decoded['skin'] is Map) {
      payloads.add(decoded['skin']);
    } else {
      payloads.add(decoded);
    }
    if ((payloads.isEmpty && interfaceSettings == null) ||
        payloads.any((value) => !_isSkinPayload(value))) {
      throw const FormatException('This file does not contain an app skin.');
    }
    return ParsedSkinFile(
      skins: payloads.map(CustomAppSkin.fromJson).toList(),
      interfaceSettings: interfaceSettings,
    );
  }

  /// Persists the interface section of a skin file, replacing this device's
  /// interface settings. Configuration, per-folder layout memory and the skin
  /// library are left alone, so import the file's skins *first* if the active
  /// skin should resolve to one of them.
  Future<AppliedInterface> applyInterface(ImportedInterface imported) async {
    final currentToolbar = await _toolbarService.load();
    final toolbar = currentToolbar.withInterfaceFrom(imported.toolbarConfig);
    await _toolbarService.save(toolbar);

    final settings = await _appSettingsService.updateSettings((current) {
      final source = imported.appSettings;
      var next = current.withInterfaceFrom(
        source.copyWith(
          // The toolbar config is authoritative for the file-manager skin.
          fileManagerSkin: toolbar.skin,
          // A file without editor preferences leaves this device's alone.
          editorAppearancePrefs: source.editorAppearancePrefs.isNotEmpty
              ? source.editorAppearancePrefs
              : current.editorAppearancePrefs,
        ),
      );
      next = _withActiveSkin(next, imported);
      return next.copyWith(appSkinSchemaVersion: 1);
    });
    return AppliedInterface(settings: settings, toolbarConfig: toolbar);
  }

  /// Re-selects the skin that was active in the file, when this device has it.
  /// A custom skin that is not in the library (for example because the file
  /// was imported with its skins left out) keeps the current selection.
  AppSettings _withActiveSkin(AppSettings settings, ImportedInterface file) {
    final preset = file.activePreset;
    if (preset == null) return settings;
    if (preset != AppSkinPreset.custom) {
      return settings.copyWith(
        appSkinPreset: preset,
        useOledBlackTheme: preset == AppSkinPreset.oledPureBlack,
      );
    }
    final id = file.activeSkinId;
    for (final skin in settings.customAppSkins) {
      if (skin.id == id) {
        return settings.copyWith(
          appSkinPreset: AppSkinPreset.custom,
          customAppSkin: skin,
          useOledBlackTheme: false,
        );
      }
    }
    return settings;
  }
}

ImportedInterface _parseInterface(Object? raw) {
  const invalid = FormatException(
    'This file does not contain valid interface settings.',
  );
  if (raw is! Map) throw invalid;
  final app = raw['app'];
  final fileManager = raw['fileManager'];
  if (app is! Map || fileManager is! Map) throw invalid;

  final active = raw['activeSkin'];
  AppSkinPreset? preset;
  String? skinId;
  if (active is Map) {
    if (active['preset'] is String) {
      preset = AppSkinPreset.fromJson(active['preset']);
    }
    if (active['skinId'] is String) skinId = active['skinId'] as String;
  }
  return ImportedInterface(
    appSettings: AppSettings.fromJson(Map<String, dynamic>.from(app)),
    toolbarConfig: FileManagerToolbarConfig.fromJson(
      Map<String, dynamic>.from(fileManager),
    ),
    activePreset: preset,
    activeSkinId: skinId,
  );
}

bool _isSkinPayload(Object? value) =>
    value is Map &&
    value['name'] is String &&
    (value['lightColors'] is Map || value['darkColors'] is Map);

String _fileName(List<CustomAppSkin> skins, bool includeInterface) {
  if (includeInterface) return 'vaultexplorer_appearance.json';
  if (skins.length == 1) {
    return '${_safeSkinFileName(skins.single.name)}.vaultskin.json';
  }
  return 'vaultexplorer_skins.json';
}

String _safeSkinFileName(String name) {
  final cleaned = name
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return cleaned.isEmpty ? 'app_skin' : cleaned;
}
