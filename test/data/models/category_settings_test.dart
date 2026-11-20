import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';

void main() {
  group('category shortcut settings', () {
    test('default to everything shown, in the default order', () {
      final settings = AppSettings();
      expect(settings.categoryShortcutsEnabled, isTrue);
      expect(settings.categoryShortcutOrder, FileCategory.defaultOrderKeys);
      expect(settings.hiddenCategoryShortcuts, isEmpty);
      expect(settings.categorySources, isEmpty);
      expect(settings.categoryLayouts, isEmpty);
      expect(settings.categoryFolderStructure, isEmpty);
    });

    test('survive a round trip through JSON', () {
      final settings = AppSettings().copyWith(
        categoryShortcutsEnabled: false,
        categoryShortcutOrder: ['audio', 'images', 'videos', 'documents'],
        hiddenCategoryShortcuts: ['videos'],
        categorySources: {'images': 'vault:3', 'audio': 'device'},
        categoryLayouts: {'gallery': 'masonry', 'images': 'grid'},
        categoryFolderStructure: ['documents'],
      );

      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.categoryShortcutsEnabled, isFalse);
      expect(restored.categoryShortcutOrder, settings.categoryShortcutOrder);
      expect(restored.hiddenCategoryShortcuts, ['videos']);
      expect(restored.categorySources, settings.categorySources);
      expect(restored.categoryLayouts, {'gallery': 'masonry', 'images': 'grid'});
      expect(restored.categoryFolderStructure, ['documents']);
    });

    test('a remembered layout that no longer exists is dropped, not crashed on', () {
      final restored = AppSettings.fromJson(<String, dynamic>{
        'categoryLayouts': {
          'gallery': 'masonry',
          'images': 'hologram',
          'videos': 7,
          3: 'grid',
        },
      });

      expect(restored.categoryLayouts, {'gallery': 'masonry'});
    });

    test('an old settings file without them gets the defaults', () {
      final restored = AppSettings.fromJson(<String, dynamic>{});
      expect(restored.categoryShortcutsEnabled, isTrue);
      expect(restored.categoryShortcutOrder, FileCategory.defaultOrderKeys);
    });

    test('belong to the interface export, not the configuration one', () {
      final settings = AppSettings();
      expect(
        settings.interfaceToJson().keys,
        contains('categoryShortcutOrder'),
      );
      expect(
        settings.configurationToJson().keys,
        isNot(contains('categoryShortcutOrder')),
      );
    });

    test('the in-vault category index is on by default and survives JSON', () {
      expect(AppSettings().categoryIndexInVaults, isTrue);
      final off = AppSettings().copyWith(categoryIndexInVaults: false);
      expect(AppSettings.fromJson(off.toJson()).categoryIndexInVaults, isFalse);
      expect(
        AppSettings.fromJson(<String, dynamic>{}).categoryIndexInVaults,
        isTrue,
      );
    });

    test('the in-vault category index is configuration, not interface', () {
      final settings = AppSettings();
      expect(
        settings.configurationToJson().keys,
        contains('categoryIndexInVaults'),
      );
      expect(
        settings.interfaceToJson().keys,
        isNot(contains('categoryIndexInVaults')),
      );
      final merged = AppSettings().withConfigurationFrom(
        AppSettings().copyWith(categoryIndexInVaults: false),
      );
      expect(merged.categoryIndexInVaults, isFalse);
    });

    test('an interface merge carries them over', () {
      final source = AppSettings().copyWith(
        hiddenCategoryShortcuts: ['audio'],
        categoryFolderStructure: ['images'],
      );
      final merged = AppSettings().withInterfaceFrom(source);
      expect(merged.hiddenCategoryShortcuts, ['audio']);
      expect(merged.categoryFolderStructure, ['images']);
    });
  });
}
