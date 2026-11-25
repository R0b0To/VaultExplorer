import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/new_tab_behavior.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

void main() {
  group('NewTabBehavior', () {
    test('round-trips through JSON', () {
      for (final mode in NewTabBehavior.values) {
        expect(NewTabBehavior.fromJson(mode.toJson()), mode);
      }
    });

    test('an unknown or missing value means duplicate', () {
      expect(NewTabBehavior.fromJson(null), NewTabBehavior.duplicate);
      expect(NewTabBehavior.fromJson('???'), NewTabBehavior.duplicate);
    });

    test('the Vaults page and this device have distinct ids', () {
      expect(kNewTabVaultsPageId, isNot(kNewTabLocalStorageId));
    });

    test('duplicate is the default of a fresh install', () {
      final settings = AppSettings();
      expect(settings.newTabBehavior, NewTabBehavior.duplicate);
      expect(settings.newTabStorageId, kNewTabLocalStorageId);
    });
  });

  group('AppSettings new tab settings', () {
    test('are stored and restored', () {
      final settings = AppSettings()
        ..newTabBehavior = NewTabBehavior.specificStorage
        ..newTabStorageId = 'sysvol_1234';
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.newTabBehavior, NewTabBehavior.specificStorage);
      expect(restored.newTabStorageId, 'sysvol_1234');
    });

    test('settings saved before the feature get the defaults', () {
      final legacy = AppSettings().toJson()
        ..remove('newTabBehavior')
        ..remove('newTabStorageId');
      final restored = AppSettings.fromJson(legacy);
      expect(restored.newTabBehavior, NewTabBehavior.duplicate);
      expect(restored.newTabStorageId, kNewTabLocalStorageId);
    });

    test('an empty storage id falls back to this device', () {
      final json = AppSettings().toJson()..['newTabStorageId'] = '';
      expect(AppSettings.fromJson(json).newTabStorageId, kNewTabLocalStorageId);
    });

    test('copyWith changes only what is given', () {
      final base = AppSettings()
        ..newTabBehavior = NewTabBehavior.prompt
        ..newTabStorageId = 'abc';
      final changed = base.copyWith(newTabBehavior: NewTabBehavior.duplicate);
      expect(changed.newTabBehavior, NewTabBehavior.duplicate);
      expect(changed.newTabStorageId, 'abc');
    });
  });
}
