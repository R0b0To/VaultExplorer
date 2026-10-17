import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/api/vault_panic_api.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/settings_backup_service.dart';
import 'package:vaultexplorer/data/services/skin_backup_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

// Settings -> Export is "how the app behaves"; App skin -> Export is "how it
// looks and is laid out". These run the real services over an in-memory
// stand-in for secure storage and check what each file contains, and what each
// import does and does not touch.

class _FakeFileIoApi extends VaultFileIoApi {
  _FakeFileIoApi() : super(const MethodChannel('test/file-io-api'));

  String? exportedContents;
  String? exportedName;
  String? toImport;

  @override
  Future<bool> exportAppSettingsFile(String contents, String fileName) async {
    exportedContents = contents;
    exportedName = fileName;
    return true;
  }

  @override
  Future<String?> importAppSettingsFile() async => toImport;
}

class _FakePanicApi implements VaultPanicApi {
  @override
  Future<PanicSettingsSnapshot> getPanicSettings() async =>
      (configuredTier: PanicTier.credentialPurge, quickTileEnabled: true);

  @override
  Future<PanicKitStatus> getPanicKitStatus() async => (
    responderEnabled: true,
    pairingEnforcementEnabled: false,
    trustedPackage: null,
    hasTrustedCert: false,
  );

  @override
  Future<bool> setPanicTier(PanicTier tier) async => true;

  @override
  Future<bool> setQuickTileEnabled(bool enabled) async => true;

  @override
  Future<bool> setPanicKitEnabled(bool enabled) async => true;

  @override
  Future<bool> setPanicKitPairingEnforcement(bool enabled) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLifecycleApi implements VaultLifecycleApi {
  @override
  Future<bool> isShareTargetEnabled() async => true;

  @override
  Future<void> setShareTargetEnabled(bool enabled) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CustomAppSkin _skin() => const CustomAppSkin(
  id: 'skin-a',
  name: 'Dusk',
  lightColors: {'primary': 0xFF112233},
  darkColors: {'primary': 0xFF445566},
);

// Device A: the device a file is written on.
AppSettings _settingsA() => AppSettings(
  // configuration
  autoLockMins: 5,
  blockScreenshots: false,
  languageCode: 'de',
  videoMuted: true,
  // interface
  themeMode: ThemeMode.dark,
  defaultLayoutMode: BrowserLayoutMode.masonry,
  showStorageLocationsInDrawer: false,
  editorAppearancePrefs: {'fontSize': 18.0, 'showLineNumbers': false},
  // skins
  appSkinPreset: AppSkinPreset.custom,
  customAppSkin: _skin(),
  customAppSkins: [_skin()],
);

FileManagerToolbarConfig _toolbarA() {
  final d = FileManagerToolbarConfig.defaults();
  return d.copyWith(
    // layout
    order: d.order.reversed.toList(),
    gridSpacing: 14,
    showStatsBar: false,
    // behavior
    showHiddenFiles: true,
    // per-container
    folderLayoutModes: {'a:/': 'grid'},
    mediaViewerToolbarConfig: const MediaViewerToolbarConfig().copyWith(
      showProgressBar: false, // layout
      loopPlaylist: false, // behavior
    ),
  );
}

// Device B: the device a file is read on, with a different look and behavior.
AppSettings _settingsB() => AppSettings(
  autoLockMins: 1,
  languageCode: 'fr',
  themeMode: ThemeMode.light,
  defaultLayoutMode: BrowserLayoutMode.grid,
  editorAppearancePrefs: {'fontSize': 12.0},
);

FileManagerToolbarConfig _toolbarB() => FileManagerToolbarConfig.defaults()
    .copyWith(
      gridSpacing: 4,
      useFabForToolbar: true,
      folderLayoutModes: {'b:/': 'list'},
      folderSortModes: {'b:/': 'date'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late Map<String, String> store;
  late AppSettingsService settingsService;
  late FileManagerToolbarService toolbarService;
  late _FakeFileIoApi fileIo;
  late SettingsBackupService settingsBackup;
  late SkinBackupService skinBackup;

  setUp(() {
    store = {};
    AppSettingsService.invalidateCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map?;
          switch (call.method) {
            case ChannelMethods.readSecure:
              return store[args!['key'] as String];
            case ChannelMethods.writeSecure:
              store[args!['key'] as String] = args['value'] as String;
              return true;
            case ChannelMethods.deleteSecure:
              store.remove(args!['key'] as String);
              return true;
          }
          return null;
        });

    settingsService = const AppSettingsService();
    toolbarService = FileManagerToolbarService();
    fileIo = _FakeFileIoApi();
    settingsBackup = SettingsBackupService(
      appSettingsService: settingsService,
      toolbarService: toolbarService,
      fileIoApi: fileIo,
      panicApi: _FakePanicApi(),
      lifecycleApi: _FakeLifecycleApi(),
    );
    skinBackup = SkinBackupService(
      appSettingsService: settingsService,
      toolbarService: toolbarService,
      fileIoApi: fileIo,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    AppSettingsService.invalidateCache();
  });

  Future<void> deviceA() async {
    await settingsService.saveSettings(_settingsA());
    await toolbarService.save(_toolbarA());
  }

  Future<void> deviceB() async {
    await settingsService.saveSettings(_settingsB());
    await toolbarService.save(_toolbarB());
  }

  Map<String, dynamic> exported() =>
      jsonDecode(fileIo.exportedContents!) as Map<String, dynamic>;

  group('Settings export (configuration)', () {
    test('contains configuration only, no interface setting', () async {
      await deviceA();

      expect(await settingsBackup.exportToFile(), isTrue);
      final bundle = exported();

      expect(bundle['schemaVersion'], 4);
      expect(
        (bundle['appSettings'] as Map).keys.toSet(),
        AppSettings().configurationToJson().keys.toSet(),
      );
      // Nothing visual, and no skin library, in the configuration file.
      for (final key in [
        ...AppSettings().interfaceToJson().keys,
        ...AppSettings().skinsToJson().keys,
      ]) {
        expect(bundle['appSettings'], isNot(contains(key)), reason: key);
      }
    });

    test('keeps only behavior options of the file manager', () async {
      await deviceA();

      await settingsBackup.exportToFile();
      final bundle = exported();

      expect(bundle.containsKey('fileManagerToolbar'), isFalse);
      final behavior = bundle['fileManagerBehavior'] as Map<String, dynamic>;
      expect(
        behavior.keys.toSet(),
        {...FileManagerToolbarConfig.behaviorKeys, 'mediaViewerToolbarConfig'},
      );
      // The media viewer's layout stays out; only its behavior is exported.
      final viewer = behavior['mediaViewerToolbarConfig'] as Map;
      for (final key in MediaViewerToolbarConfig.interfaceKeys) {
        expect(viewer, isNot(contains(key)), reason: key);
      }
      expect(viewer, contains('loopPlaylist'));
    });

    test('importing it changes only the configuration', () async {
      await deviceA();
      final a = await settingsService.loadSettings();
      await settingsBackup.exportToFile();
      final file = fileIo.exportedContents!;

      await deviceB();
      final b = await settingsService.loadSettings();
      fileIo.toImport = file;
      final bundle = (await settingsBackup.pickAndParseFile())!;
      expect(bundle.includesInterface, isFalse);
      final applied = await settingsBackup.applyImportedBundle(bundle);

      // Behavior comes from the file...
      expect(applied.settings.configurationToJson(), a.configurationToJson());
      expect(
        applied.toolbarConfig.behaviorToJson(),
        _toolbarA().behaviorToJson(),
      );
      // ...while this device keeps its own look, skins and folder memory.
      expect(applied.settings.interfaceToJson(), b.interfaceToJson());
      expect(applied.settings.skinsToJson(), b.skinsToJson());
      expect(
        applied.toolbarConfig.interfaceToJson(),
        _toolbarB().interfaceToJson(),
      );
      expect(applied.toolbarConfig.folderLayoutModes, {'b:/': 'list'});
      expect(applied.toolbarConfig.folderSortModes, {'b:/': 'date'});

      // And that is what was persisted.
      AppSettingsService.invalidateCache();
      expect(
        (await settingsService.loadSettings()).toJson(),
        applied.settings.toJson(),
      );
    });

    test('a file from before the split still restores everything', () async {
      final skinned = _settingsA();
      final legacyFile = jsonEncode({
        'schemaVersion': 3,
        'appSettings': skinned.toJson(),
        'fileManagerToolbar': _toolbarA().toJson(),
        'shareTargetEnabled': true,
      });
      await deviceB();
      fileIo.toImport = legacyFile;

      final bundle = (await settingsBackup.pickAndParseFile())!;
      expect(bundle.includesInterface, isTrue);
      final applied = await settingsBackup.applyImportedBundle(bundle);

      expect(
        applied.settings.configurationToJson(),
        skinned.configurationToJson(),
      );
      expect(applied.settings.interfaceToJson(), skinned.interfaceToJson());
      expect(applied.settings.appSkinPreset, AppSkinPreset.custom);
      expect(applied.settings.customAppSkins.single.id, 'skin-a');
      expect(
        applied.toolbarConfig.interfaceToJson(),
        _toolbarA().interfaceToJson(),
      );
      expect(
        applied.toolbarConfig.behaviorToJson(),
        _toolbarA().behaviorToJson(),
      );
      // Folder memory is per device; the old file never carried it either.
      expect(applied.toolbarConfig.folderLayoutModes, {'b:/': 'list'});
    });

    test('rejects a file that is not a settings export', () async {
      fileIo.toImport = jsonEncode({'hello': 'world'});

      expect(
        settingsBackup.pickAndParseFile(),
        throwsA(isA<InvalidSettingsBackupException>()),
      );
    });
  });

  group('App skin export (skins and interface)', () {
    test('skins only: no interface section, safe to share', () async {
      await deviceA();

      expect(await skinBackup.exportToFile([_skin()]), isTrue);
      final file = exported();

      expect((file['skins'] as List), hasLength(1));
      expect(file.containsKey('interface'), isFalse);
      expect(fileIo.exportedName, 'Dusk.vaultskin.json');
    });

    test('with interface: carries all layout and no configuration', () async {
      await deviceA();

      expect(
        await skinBackup.exportToFile([_skin()], includeInterface: true),
        isTrue,
      );
      final file = exported();
      final interfaceSection = file['interface'] as Map<String, dynamic>;

      expect(file['schemaVersion'], 2);
      expect(fileIo.exportedName, 'vaultexplorer_appearance.json');
      expect(interfaceSection['activeSkin'], {
        'preset': AppSkinPreset.custom.id,
        'skinId': 'skin-a',
      });

      final app = interfaceSection['app'] as Map<String, dynamic>;
      expect(app.keys.toSet(), AppSettings().interfaceToJson().keys.toSet());
      for (final key in AppSettings().configurationToJson().keys) {
        expect(app, isNot(contains(key)), reason: key);
      }
      expect(app['showStorageLocationsInDrawer'], isFalse);
      expect((app['editorAppearancePrefs'] as Map)['showLineNumbers'], isFalse);

      final fileManager = interfaceSection['fileManager'] as Map;
      expect(fileManager.keys.toSet(), {
        ...FileManagerToolbarConfig.interfaceKeys,
        'mediaViewerToolbarConfig',
      });
      expect(
        (fileManager['mediaViewerToolbarConfig'] as Map).keys.toSet(),
        MediaViewerToolbarConfig.interfaceKeys,
      );
      expect(fileManager, isNot(contains('showHiddenFiles')));
    });

    test('interface can be exported with no custom skins at all', () async {
      await deviceB();

      expect(await skinBackup.exportToFile([], includeInterface: true), isTrue);
      expect(exported()['skins'], isEmpty);
      expect(exported(), contains('interface'));
    });

    test('exporting nothing writes nothing', () async {
      await deviceA();

      expect(await skinBackup.exportToFile([]), isFalse);
      expect(fileIo.exportedContents, isNull);
    });

    test('importing restores layout and look, not configuration', () async {
      await deviceA();
      await skinBackup.exportToFile([_skin()], includeInterface: true);
      final file = fileIo.exportedContents!;
      final a = await settingsService.loadSettings();

      await deviceB();
      final b = await settingsService.loadSettings();
      fileIo.toImport = file;
      final parsed = (await skinBackup.pickAndParseFile())!;
      expect(parsed.skins.single.id, 'skin-a');
      expect(parsed.interfaceSettings, isNotNull);

      // The screen adds the file's skins first, then applies the interface.
      await settingsService.updateSettings(
        (current) => current.copyWith(customAppSkins: parsed.skins),
      );
      final applied = await skinBackup.applyInterface(
        parsed.interfaceSettings!,
      );

      // Look and layout come from the file.
      expect(applied.settings.themeMode, ThemeMode.dark);
      expect(applied.settings.defaultLayoutMode, BrowserLayoutMode.masonry);
      expect(applied.settings.showStorageLocationsInDrawer, isFalse);
      expect(applied.settings.editorAppearancePrefs['showLineNumbers'], isFalse);
      expect(applied.settings.appSkinPreset, AppSkinPreset.custom);
      expect(applied.settings.customAppSkin.id, 'skin-a');
      expect(
        applied.toolbarConfig.interfaceToJson(),
        _toolbarA().interfaceToJson(),
      );
      // Behavior and per-device folder memory are this device's own.
      expect(applied.settings.configurationToJson(), b.configurationToJson());
      expect(applied.settings.configurationToJson(),
          isNot(a.configurationToJson()));
      expect(
        applied.toolbarConfig.behaviorToJson(),
        _toolbarB().behaviorToJson(),
      );
      expect(applied.toolbarConfig.folderLayoutModes, {'b:/': 'list'});

      // And it was persisted.
      AppSettingsService.invalidateCache();
      final stored = await settingsService.loadSettings();
      expect(stored.themeMode, ThemeMode.dark);
      expect(stored.customAppSkin.id, 'skin-a');
      expect(stored.customAppSkins.single.id, 'skin-a');
    });

    test('a custom skin missing from the library keeps the current look',
        () async {
      await deviceA();
      await skinBackup.exportToFile([_skin()], includeInterface: true);
      final file = fileIo.exportedContents!;

      await deviceB();
      fileIo.toImport = file;
      final parsed = (await skinBackup.pickAndParseFile())!;
      // Skins deliberately NOT added to this device.
      final applied = await skinBackup.applyInterface(
        parsed.interfaceSettings!,
      );

      expect(applied.settings.appSkinPreset, AppSkinPreset.defaultSkin);
      expect(applied.settings.themeMode, ThemeMode.dark);
    });

    test('a skins-only file parses without interface settings', () async {
      await deviceA();
      await skinBackup.exportToFile([_skin()]);
      fileIo.toImport = fileIo.exportedContents;

      final parsed = (await skinBackup.pickAndParseFile())!;

      expect(parsed.skins, hasLength(1));
      expect(parsed.interfaceSettings, isNull);
    });

    test('an older (version 1) skins file still imports', () async {
      fileIo.toImport = jsonEncode({
        'format': 'vault-explorer-skins',
        'schemaVersion': 1,
        'skins': [_skin().toJson()],
      });

      final parsed = (await skinBackup.pickAndParseFile())!;

      expect(parsed.skins.single.name, 'Dusk');
      expect(parsed.interfaceSettings, isNull);
    });

    test('a malformed interface section is rejected', () async {
      fileIo.toImport = jsonEncode({
        'skins': [_skin().toJson()],
        'interface': {'app': 'nope'},
      });

      expect(
        skinBackup.pickAndParseFile(),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
