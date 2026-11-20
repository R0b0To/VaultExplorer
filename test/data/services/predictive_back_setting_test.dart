import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

// The "Predictive back animations" preference: on by default, saved across
// launches, and carried with the interface half of a settings export. What it
// does to back gestures is covered in
// test/core/theme/predictive_back_preference_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'predictiveBackAnimations';

  group('AppSettings.predictiveBackAnimations', () {
    test('is on by default', () {
      expect(AppSettings().predictiveBackAnimations, isTrue);
    });

    test('settings saved before the option existed keep it on', () {
      // An install upgrading from an older version has no such key stored.
      final stored = AppSettings().toJson()..remove(key);

      expect(stored, isNot(contains(key)));
      expect(AppSettings.fromJson(stored).predictiveBackAnimations, isTrue);
      expect(AppSettings.fromJson({}).predictiveBackAnimations, isTrue);
    });

    test('is kept through toJson and fromJson, whichever way it is set', () {
      for (final value in [true, false]) {
        final restored = AppSettings.fromJson(
          AppSettings(predictiveBackAnimations: value).toJson(),
        );
        expect(restored.predictiveBackAnimations, value);
      }
    });

    test('copyWith changes only this option', () {
      final base = AppSettings(appBarAtBottom: true, autoLockMins: 3);

      final off = base.copyWith(predictiveBackAnimations: false);
      expect(off.predictiveBackAnimations, isFalse);
      expect(off.appBarAtBottom, isTrue);
      expect(off.autoLockMins, 3);

      // Changing something else must not switch it back on or off.
      expect(off.copyWith(autoLockMins: 9).predictiveBackAnimations, isFalse);
      final backOn = off.copyWith(predictiveBackAnimations: true);
      expect(backOn.predictiveBackAnimations, isTrue);
    });

    test('travels with the interface export, not configuration or skins', () {
      final settings = AppSettings(predictiveBackAnimations: false);

      expect(settings.interfaceToJson()[key], isFalse);
      expect(settings.configurationToJson(), isNot(contains(key)));
      expect(settings.skinsToJson(), isNot(contains(key)));
      expect(settings.toJson()[key], isFalse);
    });

    test(
      'an interface import applies it and a configuration import does not',
      () {
        final source = AppSettings(predictiveBackAnimations: false);
        final target = AppSettings();

        expect(
          target.withInterfaceFrom(source).predictiveBackAnimations,
          isFalse,
        );
        expect(
          target.withConfigurationFrom(source).predictiveBackAnimations,
          isTrue,
        );
      },
    );
  });

  group('persistence across launches', () {
    const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
    const blobKey = 'app_settings_blob_v1';
    late Map<String, String> store;

    // A launch starts with nothing cached in memory; only what was written to
    // secure storage survives.
    void restartApp() => AppSettingsService.invalidateCache();

    setUp(() {
      // What an older version left behind: a settings blob with no such key.
      store = {blobKey: jsonEncode(AppSettings().toJson()..remove(key))};
      AppSettingsService.invalidateCache();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map?;
            switch (call.method) {
              case 'readSecure':
                return store[args!['key']];
              case 'writeSecure':
                store[args!['key'] as String] = args['value'] as String;
                return true;
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      AppSettingsService.invalidateCache();
    });

    test('is on after an upgrade, then follows what the user chose', () async {
      const service = AppSettingsService();
      expect((await service.loadSettings()).predictiveBackAnimations, isTrue);

      await service.updateSettings(
        (s) => s.copyWith(predictiveBackAnimations: false),
      );
      restartApp();
      expect((await service.loadSettings()).predictiveBackAnimations, isFalse);

      await service.updateSettings(
        (s) => s.copyWith(predictiveBackAnimations: true),
      );
      restartApp();
      expect((await service.loadSettings()).predictiveBackAnimations, isTrue);
    });

    test('turning it off leaves every other stored setting alone', () async {
      const service = AppSettingsService();
      await service.updateSettings(
        (s) => s.copyWith(appBarAtBottom: true, autoLockMins: 11),
      );

      await service.updateSettings(
        (s) => s.copyWith(predictiveBackAnimations: false),
      );
      restartApp();
      final loaded = await service.loadSettings();

      expect(loaded.predictiveBackAnimations, isFalse);
      expect(loaded.appBarAtBottom, isTrue);
      expect(loaded.autoLockMins, 11);
    });
  });
}
