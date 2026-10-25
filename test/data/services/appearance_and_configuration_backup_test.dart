import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/quick_capture_api.dart';
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

// Settings -> Export holds everything that was configured (app, file manager,
// media player and text editor settings, with custom skins on request);
// App skin -> Export shares looks on their own, with or without the layout.
// These run the real services over an in-memory stand-in for secure storage
// and check what each file contains, and what each import does and does not
// touch.

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
  bool shareTarget = true;
  bool usbPrompt = false;

  @override
  Future<bool> isShareTargetEnabled() async => shareTarget;

  @override
  Future<void> setShareTargetEnabled(bool enabled) async {
    shareTarget = enabled;
  }

  @override
  Future<bool> isUsbAttachPromptEnabled() async => usbPrompt;

  @override
  Future<void> setUsbAttachPromptEnabled(bool enabled) async {
    usbPrompt = enabled;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeQuickCaptureApi implements QuickCaptureApi {
  bool tileEnabled = true;

  @override
  Future<QuickCaptureSettingsSnapshot> getQuickCaptureSettings() async =>
      (tileEnabled: tileEnabled);

  @override
  Future<bool> setQuickCaptureTileEnabled(bool enabled) async {
    tileEnabled = enabled;
    return true;
  }

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

FileManagerToolbarConfig _toolbarB() =>
    FileManagerToolbarConfig.defaults().copyWith(
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
  late _FakeLifecycleApi lifecycle;
  late _FakeQuickCaptureApi quickCapture;

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
    lifecycle = _FakeLifecycleApi();
    quickCapture = _FakeQuickCaptureApi();
    skinBackup = SkinBackupService(
      appSettingsService: settingsService,
      toolbarService: toolbarService,
      fileIoApi: fileIo,
    );
    settingsBackup = SettingsBackupService(
      appSettingsService: settingsService,
      toolbarService: toolbarService,
      skinBackupService: skinBackup,
      fileIoApi: fileIo,
      panicApi: _FakePanicApi(),
      lifecycleApi: lifecycle,
      quickCaptureApi: quickCapture,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    AppSettingsService.invalidateCache();
  });

  Future<void> deviceA() async {
    await settingsService.replaceSettings(_settingsA());
    await toolbarService.save(_toolbarA());
  }

  Future<void> deviceB() async {
    await settingsService.replaceSettings(_settingsB());
    await toolbarService.save(_toolbarB());
  }

  Map<String, dynamic> exported() =>
      jsonDecode(fileIo.exportedContents!) as Map<String, dynamic>;

  group('Settings export (everything configured)', () {
    test(
      'holds configuration, look and layout, and the native toggles',
      () async {
        await deviceA();
        lifecycle.usbPrompt = true;
        quickCapture.tileEnabled = false;

        expect(await settingsBackup.exportToFile(), isTrue);
        final bundle = exported();

        expect(bundle['schemaVersion'], 5);
        expect(bundle.containsKey('fileManagerToolbar'), isFalse);

        // App settings: behavior in `appSettings`, nothing visual duplicated.
        expect(
          (bundle['appSettings'] as Map).keys.toSet(),
          AppSettings().configurationToJson().keys.toSet(),
        );
        for (final key in [
          ...AppSettings().interfaceToJson().keys,
          ...AppSettings().skinsToJson().keys,
        ]) {
          expect(bundle['appSettings'], isNot(contains(key)), reason: key);
        }

        // File manager and media player behavior.
        final behavior = bundle['fileManagerBehavior'] as Map<String, dynamic>;
        expect(behavior.keys.toSet(), {
          ...FileManagerToolbarConfig.behaviorKeys,
          'mediaViewerToolbarConfig',
        });
        final viewerBehavior = behavior['mediaViewerToolbarConfig'] as Map;
        for (final key in MediaViewerToolbarConfig.interfaceKeys) {
          expect(viewerBehavior, isNot(contains(key)), reason: key);
        }
        expect(viewerBehavior, contains('loopPlaylist'));

        // Look and layout: app, file manager, media player, text editor.
        final section = bundle['interface'] as Map<String, dynamic>;
        final app = section['app'] as Map<String, dynamic>;
        expect(app.keys.toSet(), AppSettings().interfaceToJson().keys.toSet());
        expect(app['themeMode'], isNotNull);
        expect((app['editorAppearancePrefs'] as Map)['fontSize'], 18.0);
        final fileManager = section['fileManager'] as Map<String, dynamic>;
        expect(
          fileManager.keys.toSet(),
          FileManagerToolbarConfig.defaults().interfaceToJson().keys.toSet(),
        );
        final viewerLayout = fileManager['mediaViewerToolbarConfig'] as Map;
        expect(viewerLayout['showProgressBar'], isFalse);

        // The two toggles that live on the native side.
        expect(bundle['usbAttachPromptEnabled'], isTrue);
        expect(bundle['quickCaptureTileEnabled'], isFalse);

        // Per-folder memory and credentials are never part of it.
        expect(fileManager.keys, isNot(contains('folderLayoutModes')));
        expect(fileIo.exportedContents, isNot(contains('folderLayoutModes')));
      },
    );

    test(
      'leaves the skins out unless asked, but records the active one',
      () async {
        await deviceA();

        await settingsBackup.exportToFile();
        final bundle = exported();

        expect(bundle.containsKey('skins'), isFalse);
        final active =
            (bundle['interface'] as Map)['activeSkin'] as Map<String, dynamic>;
        expect(active['preset'], AppSkinPreset.custom.id);
        expect(active['skinId'], 'skin-a');
      },
    );

    test('carries the custom skins when asked to', () async {
      await deviceA();

      await settingsBackup.exportToFile(includeThemes: true);
      final bundle = exported();

      final skins = bundle['skins'] as List;
      expect(skins, hasLength(1));
      expect((skins.single as Map)['id'], 'skin-a');
    });

    test('importing restores configuration, look and layout', () async {
      await deviceA();
      final a = await settingsService.loadSettings();
      lifecycle.usbPrompt = true;
      quickCapture.tileEnabled = false;
      await settingsBackup.exportToFile();
      final file = fileIo.exportedContents!;

      await deviceB();
      lifecycle.usbPrompt = false;
      quickCapture.tileEnabled = true;
      fileIo.toImport = file;
      final bundle = (await settingsBackup.pickAndParseFile())!;
      expect(bundle.includesInterface, isFalse);
      expect(bundle.restoresInterface, isTrue);
      expect(bundle.hasThemes, isFalse);
      final applied = await settingsBackup.applyImportedBundle(bundle);

      // App settings, both halves.
      expect(applied.settings.configurationToJson(), a.configurationToJson());
      expect(applied.settings.themeMode, ThemeMode.dark);
      expect(applied.settings.defaultLayoutMode, BrowserLayoutMode.masonry);
      expect(applied.settings.showStorageLocationsInDrawer, isFalse);
      // Text editor.
      expect(applied.settings.editorAppearancePrefs['fontSize'], 18.0);
      expect(applied.settings.editorAppearancePrefs['showLineNumbers'], false);
      // File manager and media player: behavior and layout.
      expect(
        applied.toolbarConfig.behaviorToJson(),
        _toolbarA().behaviorToJson(),
      );
      expect(
        applied.toolbarConfig.interfaceToJson(),
        _toolbarA().interfaceToJson(),
      );
      expect(
        applied.toolbarConfig.mediaViewerToolbarConfig.showProgressBar,
        isFalse,
      );
      // Native toggles.
      expect(lifecycle.usbPrompt, isTrue);
      expect(quickCapture.tileEnabled, isFalse);
      // Folder memory belongs to the device and is kept.
      expect(applied.toolbarConfig.folderLayoutModes, {'b:/': 'list'});
      expect(applied.toolbarConfig.folderSortModes, {'b:/': 'date'});
      // A skin this device does not have cannot be selected, so the current
      // selection stays.
      expect(applied.settings.appSkinPreset, _settingsB().appSkinPreset);
      expect(applied.settings.customAppSkins, isEmpty);

      // And that is what was persisted.
      AppSettingsService.invalidateCache();
      expect(
        (await settingsService.loadSettings()).toJson(),
        applied.settings.toJson(),
      );
    });

    test('importing with skins adds them and selects the active one', () async {
      await deviceA();
      await settingsBackup.exportToFile(includeThemes: true);
      final file = fileIo.exportedContents!;

      await deviceB();
      fileIo.toImport = file;
      final bundle = (await settingsBackup.pickAndParseFile())!;
      expect(bundle.hasThemes, isTrue);
      final applied = await settingsBackup.applyImportedBundle(bundle);

      expect(applied.settings.customAppSkins.single.id, 'skin-a');
      expect(applied.settings.appSkinPreset, AppSkinPreset.custom);
      expect(applied.settings.customAppSkin.id, 'skin-a');
    });

    test('importing the same file twice does not duplicate skins', () async {
      await deviceA();
      await settingsBackup.exportToFile(includeThemes: true);
      fileIo.toImport = fileIo.exportedContents;

      await deviceB();
      final first = await settingsBackup.applyImportedBundle(
        (await settingsBackup.pickAndParseFile())!,
      );
      final second = await settingsBackup.applyImportedBundle(
        (await settingsBackup.pickAndParseFile())!,
      );

      expect(first.settings.customAppSkins, hasLength(1));
      expect(second.settings.customAppSkins, hasLength(1));
    });

    test('a skin with the same id is replaced, others are kept', () async {
      await deviceA();
      await settingsBackup.exportToFile(includeThemes: true);
      fileIo.toImport = fileIo.exportedContents;

      const stale = CustomAppSkin(
        id: 'skin-a',
        name: 'Old name',
        lightColors: {'primary': 0xFF000000},
        darkColors: {'primary': 0xFF000000},
      );
      const unrelated = CustomAppSkin(id: 'skin-z', name: 'Unrelated');
      await settingsService.replaceSettings(
        _settingsB().copyWith(
          customAppSkin: stale,
          customAppSkins: [stale, unrelated],
        ),
      );
      await toolbarService.save(_toolbarB());

      final applied = await settingsBackup.applyImportedBundle(
        (await settingsBackup.pickAndParseFile())!,
      );

      final byId = {
        for (final skin in applied.settings.customAppSkins) skin.id: skin,
      };
      expect(byId.keys.toSet(), {'skin-a', 'skin-z'});
      expect(byId['skin-a']!.name, 'Dusk');
      expect(applied.settings.customAppSkin.name, 'Dusk');
    });

    test(
      'a file that only has configuration leaves look and skins alone',
      () async {
        // What schema 4 wrote: no interface section, no skins, no new toggles.
        await deviceA();
        final a = await settingsService.loadSettings();
        await settingsBackup.exportToFile(includeThemes: true);
        final v4 = exported()
          ..['schemaVersion'] = 4
          ..remove('interface')
          ..remove('skins')
          ..remove('usbAttachPromptEnabled')
          ..remove('quickCaptureTileEnabled');

        await deviceB();
        final b = await settingsService.loadSettings();
        lifecycle.usbPrompt = false;
        quickCapture.tileEnabled = true;
        fileIo.toImport = jsonEncode(v4);
        final bundle = (await settingsBackup.pickAndParseFile())!;
        expect(bundle.restoresInterface, isFalse);
        expect(bundle.hasThemes, isFalse);
        final applied = await settingsBackup.applyImportedBundle(bundle);

        expect(applied.settings.configurationToJson(), a.configurationToJson());
        expect(
          applied.toolbarConfig.behaviorToJson(),
          _toolbarA().behaviorToJson(),
        );
        expect(applied.settings.interfaceToJson(), b.interfaceToJson());
        expect(applied.settings.skinsToJson(), b.skinsToJson());
        expect(
          applied.toolbarConfig.interfaceToJson(),
          _toolbarB().interfaceToJson(),
        );
        expect(applied.toolbarConfig.folderLayoutModes, {'b:/': 'list'});
        // Toggles the file does not mention are untouched.
        expect(lifecycle.usbPrompt, isFalse);
        expect(quickCapture.tileEnabled, isTrue);
      },
    );

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
      expect(bundle.restoresInterface, isTrue);
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

    test(
      'rejects a file whose interface or skins section is malformed',
      () async {
        await deviceA();
        await settingsBackup.exportToFile();
        final good = exported();

        fileIo.toImport = jsonEncode({...good, 'interface': 'nope'});
        await expectLater(
          settingsBackup.pickAndParseFile(),
          throwsA(isA<InvalidSettingsBackupException>()),
        );

        fileIo.toImport = jsonEncode({...good, 'skins': 'nope'});
        await expectLater(
          settingsBackup.pickAndParseFile(),
          throwsA(isA<InvalidSettingsBackupException>()),
        );
      },
    );
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
      expect(
        applied.settings.editorAppearancePrefs['showLineNumbers'],
        isFalse,
      );
      expect(applied.settings.appSkinPreset, AppSkinPreset.custom);
      expect(applied.settings.customAppSkin.id, 'skin-a');
      expect(
        applied.toolbarConfig.interfaceToJson(),
        _toolbarA().interfaceToJson(),
      );
      // Behavior and per-device folder memory are this device's own.
      expect(applied.settings.configurationToJson(), b.configurationToJson());
      expect(
        applied.settings.configurationToJson(),
        isNot(a.configurationToJson()),
      );
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

    test(
      'a custom skin missing from the library keeps the current look',
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
      },
    );

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

      expect(skinBackup.pickAndParseFile(), throwsA(isA<FormatException>()));
    });
  });
}
