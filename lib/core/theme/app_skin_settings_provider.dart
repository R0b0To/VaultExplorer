import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/skin_backup_service.dart';

class AppSkinSettings {
  final AppSkinPreset preset;
  final CustomAppSkin customAppSkin;
  final List<CustomAppSkin> customAppSkins;
  final FileManagerSkin fileManagerSkin;
  final bool fileManagerFollowsAppSkin;
  final bool editorFollowsAppSkin;

  const AppSkinSettings({
    this.preset = AppSkinPreset.defaultSkin,
    this.customAppSkin = const CustomAppSkin(),
    this.customAppSkins = const [],
    this.fileManagerSkin = FileManagerSkin.classic,
    this.fileManagerFollowsAppSkin = true,
    this.editorFollowsAppSkin = true,
  });

  AppSkinSettings copyWith({
    AppSkinPreset? preset,
    CustomAppSkin? customAppSkin,
    List<CustomAppSkin>? customAppSkins,
    FileManagerSkin? fileManagerSkin,
    bool? fileManagerFollowsAppSkin,
    bool? editorFollowsAppSkin,
  }) => AppSkinSettings(
    preset: preset ?? this.preset,
    customAppSkin: customAppSkin ?? this.customAppSkin,
    customAppSkins: customAppSkins ?? this.customAppSkins,
    fileManagerSkin: fileManagerSkin ?? this.fileManagerSkin,
    fileManagerFollowsAppSkin:
        fileManagerFollowsAppSkin ?? this.fileManagerFollowsAppSkin,
    editorFollowsAppSkin: editorFollowsAppSkin ?? this.editorFollowsAppSkin,
  );

  factory AppSkinSettings.fromAppSettings(AppSettings settings) =>
      AppSkinSettings(
        preset: _normalizeOledPreset(settings).appSkinPreset,
        customAppSkin: settings.customAppSkin,
        customAppSkins: settings.customAppSkins,
        fileManagerSkin: settings.fileManagerSkin,
        fileManagerFollowsAppSkin: settings.fileManagerFollowsAppSkin,
        editorFollowsAppSkin: settings.editorFollowsAppSkin,
      );
}

final appSkinSettingsProvider =
    NotifierProvider<AppSkinSettingsNotifier, AppSkinSettings>(
      AppSkinSettingsNotifier.new,
    );

class AppSkinSettingsNotifier extends Notifier<AppSkinSettings> {
  bool _hasLoadedSettings = false;

  @override
  AppSkinSettings build() {
    Future.microtask(_load);
    return const AppSkinSettings();
  }

  Future<void> _load() async {
    final settingsService = ref.read(appSettingsServiceProvider);
    var settings = await settingsService.loadSettings();
    if (!ref.mounted || _hasLoadedSettings) return;

    final normalizedOled = _normalizeOledPreset(settings);
    if (!identical(normalizedOled, settings)) {
      settings = normalizedOled;
      await settingsService.replaceSettings(settings);
      if (!ref.mounted || _hasLoadedSettings) return;
    }

    // Older installs kept custom file-manager skins in the toolbar blob.
    // Preserve that exact look when migrating them into the app-skin model.
    if (settings.appSkinSchemaVersion < 1) {
      final toolbar = await ref.read(fileManagerToolbarServiceProvider).load();
      final migrated = settings.copyWith(
        fileManagerSkin: toolbar.skin,
        fileManagerFollowsAppSkin: false,
        editorFollowsAppSkin: false,
        appSkinSchemaVersion: 1,
      );
      await settingsService.replaceSettings(migrated);
      if (!ref.mounted || _hasLoadedSettings) return;
      _applySettings(migrated);
      return;
    }

    _applySettings(settings);
  }

  void _applySettings(AppSettings settings) {
    _hasLoadedSettings = true;
    state = AppSkinSettings.fromAppSettings(settings);
  }

  Future<void> applyImportedSettings(AppSettings settings) async {
    var imported = _normalizeOledPreset(settings);
    if (imported.appSkinSchemaVersion < 1) {
      final toolbar = await ref.read(fileManagerToolbarServiceProvider).load();
      final service = ref.read(appSettingsServiceProvider);
      final current = await service.loadSettings();
      imported = imported.copyWith(
        fileManagerSkin: toolbar.skin,
        fileManagerFollowsAppSkin: false,
        editorFollowsAppSkin: false,
        editorAppearancePrefs: imported.editorAppearancePrefs.isNotEmpty
            ? imported.editorAppearancePrefs
            : current.editorAppearancePrefs,
        appSkinSchemaVersion: 1,
      );
      await service.replaceSettings(imported);
    } else if (!identical(imported, settings)) {
      await ref.read(appSettingsServiceProvider).replaceSettings(imported);
    }
    _applySettings(imported);
  }

  Future<void> setPreset(AppSkinPreset preset) => _update(
    state.copyWith(preset: preset),
    (settings) => settings.copyWith(
      appSkinPreset: preset,
      useOledBlackTheme: preset == AppSkinPreset.oledPureBlack,
    ),
  );

  Future<void> setCustomAppSkin(CustomAppSkin skin) {
    final skins = [...state.customAppSkins];
    final index = skins.indexWhere((saved) => saved.id == skin.id);
    if (index >= 0) skins[index] = skin;
    return _update(
      state.copyWith(customAppSkin: skin, customAppSkins: skins),
      (settings) =>
          settings.copyWith(customAppSkin: skin, customAppSkins: skins),
    );
  }

  Future<void> saveCustomSkin(CustomAppSkin skin) {
    final skins = [...state.customAppSkins];
    final index = skins.indexWhere((saved) => saved.id == skin.id);
    if (index < 0) {
      skins.add(skin);
    } else {
      skins[index] = skin;
    }
    return _update(
      state.copyWith(
        preset: AppSkinPreset.custom,
        customAppSkin: skin,
        customAppSkins: skins,
      ),
      (settings) => settings.copyWith(
        appSkinPreset: AppSkinPreset.custom,
        customAppSkin: skin,
        customAppSkins: skins,
        useOledBlackTheme: false,
      ),
    );
  }

  Future<void> activateCustomSkin(CustomAppSkin skin) => _update(
    state.copyWith(preset: AppSkinPreset.custom, customAppSkin: skin),
    (settings) => settings.copyWith(
      appSkinPreset: AppSkinPreset.custom,
      customAppSkin: skin,
      useOledBlackTheme: false,
    ),
  );

  Future<List<CustomAppSkin>> addImportedSkins(List<CustomAppSkin> imported) {
    final skins = [...state.customAppSkins];
    final ids = skins.map((skin) => skin.id).toSet();
    final added = <CustomAppSkin>[];
    for (final skin in imported) {
      var id = skin.id;
      while (ids.contains(id)) {
        id = createCustomAppSkinId();
      }
      final stored = skin.copyWith(id: id);
      ids.add(id);
      skins.add(stored);
      added.add(stored);
    }
    return _update(
      state.copyWith(customAppSkins: skins),
      (settings) => settings.copyWith(customAppSkins: skins),
    ).then((_) => added);
  }

  Future<void> removeCustomSkin(String id) {
    final skins = state.customAppSkins.where((skin) => skin.id != id).toList();
    final removesActiveSkin =
        state.preset == AppSkinPreset.custom && state.customAppSkin.id == id;
    final nextPreset = removesActiveSkin
        ? AppSkinPreset.defaultSkin
        : state.preset;
    return _update(
      state.copyWith(preset: nextPreset, customAppSkins: skins),
      (settings) => settings.copyWith(
        appSkinPreset: nextPreset,
        customAppSkins: skins,
        useOledBlackTheme: nextPreset == AppSkinPreset.oledPureBlack,
      ),
    );
  }

  /// Opens the file picker and parses a skin file: its skins and, when it was
  /// exported with them, the interface settings. Nothing is applied yet.
  Future<ParsedSkinFile?> pickAndParseSkinFile() =>
      ref.read(skinBackupServiceProvider).pickAndParseFile();

  /// Exports [skins]. With [includeInterface] the file also carries theme
  /// mode, toolbar/grid layout, editor appearance and the other interface
  /// settings (see [SkinBackupService]); without it the file only holds the
  /// skins and is safe to share.
  Future<bool> exportSkins(
    List<CustomAppSkin> skins, {
    bool includeInterface = false,
  }) => ref
      .read(skinBackupServiceProvider)
      .exportToFile(skins, includeInterface: includeInterface);

  Future<void> setFileManagerFollowsAppSkin(bool follows) => _update(
    state.copyWith(fileManagerFollowsAppSkin: follows),
    (settings) => settings.copyWith(fileManagerFollowsAppSkin: follows),
  );

  Future<void> setEditorFollowsAppSkin(bool follows) => _update(
    state.copyWith(editorFollowsAppSkin: follows),
    (settings) => settings.copyWith(editorFollowsAppSkin: follows),
  );

  Future<void> setFileManagerSkin(FileManagerSkin skin) => _update(
    state.copyWith(fileManagerSkin: skin),
    (settings) => settings.copyWith(fileManagerSkin: skin),
  );

  Future<void> _update(
    AppSkinSettings next,
    AppSettings Function(AppSettings) updateSettings,
  ) async {
    state = next;
    _hasLoadedSettings = true;
    final service = ref.read(appSettingsServiceProvider);
    await service.updateSettings(
      (settings) => updateSettings(settings).copyWith(appSkinSchemaVersion: 1),
    );
  }
}

AppSettings _normalizeOledPreset(AppSettings settings) {
  final preset =
      settings.appSkinPreset == AppSkinPreset.defaultSkin &&
          settings.useOledBlackTheme
      ? AppSkinPreset.oledPureBlack
      : settings.appSkinPreset;
  final legacyValue = preset == AppSkinPreset.oledPureBlack;
  if (preset == settings.appSkinPreset &&
      legacyValue == settings.useOledBlackTheme) {
    return settings;
  }
  return settings.copyWith(
    appSkinPreset: preset,
    useOledBlackTheme: legacyValue,
  );
}
