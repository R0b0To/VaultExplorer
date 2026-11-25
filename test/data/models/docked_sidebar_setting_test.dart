import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

void main() {
  group('AppSettings.dockedSidebarCollapsed', () {
    test('shows the sidebar by default', () {
      expect(AppSettings().dockedSidebarCollapsed, isFalse);
    });

    test('survives a save and load', () {
      final saved = jsonDecode(
        jsonEncode(AppSettings(dockedSidebarCollapsed: true).toJson()),
      ) as Map<String, dynamic>;

      expect(AppSettings.fromJson(saved).dockedSidebarCollapsed, isTrue);
    });

    test('settings saved before the option existed keep the sidebar shown', () {
      final saved = AppSettings().toJson()..remove('dockedSidebarCollapsed');

      expect(AppSettings.fromJson(saved).dockedSidebarCollapsed, isFalse);
    });

    test('copyWith changes only that flag', () {
      final base = AppSettings();
      final hidden = base.copyWith(dockedSidebarCollapsed: true);

      expect(hidden.dockedSidebarCollapsed, isTrue);
      expect(hidden.copyWith().dockedSidebarCollapsed, isTrue);
      expect(hidden.appBarAtBottom, base.appBarAtBottom);
    });

    test('is an interface setting, not part of the configuration', () {
      final settings = AppSettings(dockedSidebarCollapsed: true);

      expect(settings.interfaceToJson()['dockedSidebarCollapsed'], isTrue);
      expect(
        settings.configurationToJson().containsKey('dockedSidebarCollapsed'),
        isFalse,
      );
    });
  });
}
