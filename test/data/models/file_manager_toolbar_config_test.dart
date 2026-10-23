import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/file_item_action.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/grid_corner_style.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/thumbnail_settings.dart';

void main() {
  group('FileManagerToolbarConfig autoStartPlaylistMode', () {
    test('defaults to false in defaults() factory', () {
      final config = FileManagerToolbarConfig.defaults();
      expect(config.autoStartPlaylistMode, isTrue);
    });

    test('defaults to false when unassigned in constructor', () {
      final config = const FileManagerToolbarConfig(
        order: [],
        hidden: {},
      );
      expect(config.autoStartPlaylistMode, isTrue);
    });

    test('copyWith updates autoStartPlaylistMode', () {
      final config = FileManagerToolbarConfig.defaults();
      final updated = config.copyWith(autoStartPlaylistMode: true);
      expect(updated.autoStartPlaylistMode, isTrue);

      final reset = updated.copyWith(autoStartPlaylistMode: false);
      expect(reset.autoStartPlaylistMode, isFalse);
    });

    test('serializes and deserializes autoStartPlaylistMode correctly in JSON', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        autoStartPlaylistMode: true,
      );
      final json = config.toJson();
      expect(json['autoStartPlaylistMode'], isTrue);

      final restored = FileManagerToolbarConfig.fromJson(json);
      expect(restored.autoStartPlaylistMode, isTrue);
    });

    test('fromJson falls back to false when key is missing', () {
      final json = <String, dynamic>{
        'showBreadcrumbBar': true,
      };
      final config = FileManagerToolbarConfig.fromJson(json);
      expect(config.autoStartPlaylistMode, isTrue);
    });
  });

  group('FileManagerToolbarConfig item actions', () {
    test('defaults list every action in order, none hidden', () {
      final config = FileManagerToolbarConfig.defaults();

      expect(config.itemActionsOrder, FileItemAction.values);
      expect(config.hiddenItemActions, isEmpty);
      expect(config.visibleItemActions, FileItemAction.values);
      expect(config.quickItemActions, FileItemAction.defaultQuickActions);

      const unassigned = FileManagerToolbarConfig(order: [], hidden: {});
      expect(unassigned.itemActionsOrder, FileItemAction.values);
      expect(unassigned.hiddenItemActions, isEmpty);
    });

    test('visibleItemActions drops hidden actions and keeps the order', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        itemActionsOrder: FileItemAction.values.reversed.toList(),
        hiddenItemActions: {FileItemAction.delete, FileItemAction.pin},
      );

      expect(
        config.visibleItemActions,
        FileItemAction.values.reversed
            .where(
              (a) => a != FileItemAction.delete && a != FileItemAction.pin,
            )
            .toList(),
      );
    });

    test('round-trips order and hidden actions through JSON', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        itemActionsOrder: FileItemAction.values.reversed.toList(),
        hiddenItemActions: {FileItemAction.share, FileItemAction.encrypt},
      );

      final restored = FileManagerToolbarConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
      );

      expect(restored.itemActionsOrder, config.itemActionsOrder);
      expect(restored.hiddenItemActions, config.hiddenItemActions);
    });

    test('round-trips a custom quick row through JSON', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        quickItemActions: {
          FileItemAction.rename,
          FileItemAction.pin,
          FileItemAction.encrypt,
        },
      );

      final restored = FileManagerToolbarConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
      );

      expect(restored.quickItemActions, config.quickItemActions);
    });

    test('an absent quick row gets the original four; empty stays empty', () {
      final absent = FileManagerToolbarConfig.fromJson(<String, dynamic>{});
      final empty = FileManagerToolbarConfig.fromJson(<String, dynamic>{
        'quickItemActions': <String>[],
      });

      expect(absent.quickItemActions, FileItemAction.defaultQuickActions);
      expect(empty.quickItemActions, isEmpty);
    });

    test('a stored quick row drops unknown names and is cut to the max', () {
      final config = FileManagerToolbarConfig.fromJson(<String, dynamic>{
        'quickItemActions': [
          'noSuchAction',
          ...FileItemAction.values.map((a) => a.toJson()),
        ],
      });

      expect(
        config.quickItemActions,
        FileItemAction.values.take(FileItemAction.maxQuickActions).toSet(),
      );
    });

    test('a config saved before the setting existed gets the defaults', () {
      final config = FileManagerToolbarConfig.fromJson(<String, dynamic>{
        'showBreadcrumbBar': true,
      });

      expect(config.itemActionsOrder, FileItemAction.values);
      expect(config.hiddenItemActions, isEmpty);
    });

    test('fromJson drops unknown names and duplicates, appends missing', () {
      final config = FileManagerToolbarConfig.fromJson(<String, dynamic>{
        'itemActionsOrder': ['delete', 'noSuchAction', 'share', 'delete'],
        'hiddenItemActions': ['noSuchAction', 'copy'],
      });

      expect(config.itemActionsOrder.take(2), [
        FileItemAction.delete,
        FileItemAction.share,
      ]);
      expect(config.itemActionsOrder.toSet(), FileItemAction.values.toSet());
      expect(
        config.itemActionsOrder.length,
        FileItemAction.values.length,
      );
      expect(config.hiddenItemActions, {FileItemAction.copy});
    });
  });

  group('FileManagerToolbarConfig thumbnail settings', () {
    test('defaults in defaults() factory and constructor', () {
      final def = FileManagerToolbarConfig.defaults();
      expect(def.defaultThumbnailCacheMode, ThumbnailCacheMode.disabled);
      expect(def.defaultThumbnailQuality, ThumbnailQuality.defaultQuality);

      const unassigned = FileManagerToolbarConfig(order: [], hidden: {});
      expect(unassigned.defaultThumbnailCacheMode, ThumbnailCacheMode.disabled);
      expect(unassigned.defaultThumbnailQuality, ThumbnailQuality.defaultQuality);
    });

    test('copyWith updates thumbnail settings', () {
      final config = FileManagerToolbarConfig.defaults();
      final updated = config.copyWith(
        defaultThumbnailCacheMode: ThumbnailCacheMode.inContainer,
        defaultThumbnailQuality: const ThumbnailQuality(quality: 85, size: 240),
      );
      expect(updated.defaultThumbnailCacheMode, ThumbnailCacheMode.inContainer);
      expect(updated.defaultThumbnailQuality.quality, 85);
      expect(updated.defaultThumbnailQuality.size, 240);
    });

    test('serializes and deserializes correctly in JSON', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        defaultThumbnailCacheMode: ThumbnailCacheMode.appCache,
        defaultThumbnailQuality: const ThumbnailQuality(quality: 70, size: 300),
      );
      final json = config.toJson();
      expect(json['defaultThumbnailCacheMode'], 'appCache');
      expect(json['defaultThumbnailQuality'], {'quality': 70, 'size': 300});

      final restored = FileManagerToolbarConfig.fromJson(json);
      expect(restored.defaultThumbnailCacheMode, ThumbnailCacheMode.appCache);
      expect(restored.defaultThumbnailQuality.quality, 70);
      expect(restored.defaultThumbnailQuality.size, 300);
    });

    test('fromJson falls back to defaults when keys are missing', () {
      final config = FileManagerToolbarConfig.fromJson({});
      expect(config.defaultThumbnailCacheMode, ThumbnailCacheMode.disabled);
      expect(config.defaultThumbnailQuality, ThumbnailQuality.defaultQuality);
    });
  });

  group('FileManagerToolbarConfig Local Storage thumbnail slot', () {
    test('defaults match the vault default', () {
      final def = FileManagerToolbarConfig.defaults();
      expect(def.localStorageThumbnailCacheMode, ThumbnailCacheMode.disabled);
      expect(def.localStorageThumbnailQuality, ThumbnailQuality.defaultQuality);

      const unassigned = FileManagerToolbarConfig(order: [], hidden: {});
      expect(unassigned.localStorageThumbnails, ThumbnailSettings.defaults);
    });

    test('is independent of the vault default', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        defaultThumbnailCacheMode: ThumbnailCacheMode.appCache,
      );
      expect(config.defaultThumbnailCacheMode, ThumbnailCacheMode.appCache);
      expect(config.localStorageThumbnailCacheMode, ThumbnailCacheMode.disabled);

      final local = config.copyWith(
        localStorageThumbnailCacheMode: ThumbnailCacheMode.inContainer,
        localStorageThumbnailQuality: const ThumbnailQuality(quality: 95, size: 320),
      );
      expect(local.defaultThumbnailCacheMode, ThumbnailCacheMode.appCache);
      expect(local.localStorageThumbnails.cacheMode, ThumbnailCacheMode.inContainer);
      expect(local.localStorageThumbnails.quality.size, 320);
    });

    test('round-trips through JSON', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        localStorageThumbnailCacheMode: ThumbnailCacheMode.inContainer,
        localStorageThumbnailQuality: const ThumbnailQuality(quality: 95, size: 320),
      );
      final json = config.toJson();
      expect(json['localStorageThumbnailCacheMode'], 'inContainer');

      final restored = FileManagerToolbarConfig.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(restored.localStorageThumbnailCacheMode, ThumbnailCacheMode.inContainer);
      expect(restored.localStorageThumbnailQuality.quality, 95);
      expect(restored.localStorageThumbnailQuality.size, 320);
    });

    test('a config saved before the slot existed seeds it from the default, '
        'so Local Storage looks exactly as it did', () {
      final legacy = {
        'defaultThumbnailCacheMode': 'inContainer',
        'defaultThumbnailQuality': {'quality': 70, 'size': 300},
      };
      final config = FileManagerToolbarConfig.fromJson(legacy);
      expect(config.localStorageThumbnailCacheMode, ThumbnailCacheMode.inContainer);
      expect(config.localStorageThumbnailQuality.quality, 70);
      expect(config.localStorageThumbnailQuality.size, 300);

      // From then on the two are independent.
      final moved = config.copyWith(defaultThumbnailCacheMode: ThumbnailCacheMode.disabled);
      expect(moved.localStorageThumbnailCacheMode, ThumbnailCacheMode.inContainer);
    });

    test('a stored slot is not overwritten by the default', () {
      final config = FileManagerToolbarConfig.fromJson({
        'defaultThumbnailCacheMode': 'appCache',
        'localStorageThumbnailCacheMode': 'disabled',
      });
      expect(config.defaultThumbnailCacheMode, ThumbnailCacheMode.appCache);
      expect(config.localStorageThumbnailCacheMode, ThumbnailCacheMode.disabled);
    });

    test('an unreadable stored mode falls back to the default value', () {
      final config = FileManagerToolbarConfig.fromJson({
        'defaultThumbnailCacheMode': 'appCache',
        'localStorageThumbnailCacheMode': 'nonsense',
      });
      expect(config.localStorageThumbnailCacheMode, ThumbnailCacheMode.appCache);
    });
  });

  group('FileManagerToolbarConfig grid appearance', () {
    test('defaults to the original look: rounded corners, 8px gaps', () {
      final def = FileManagerToolbarConfig.defaults();
      expect(def.gridCornerStyle, GridCornerStyle.rounded);
      expect(def.gridSpacing, 8);

      const unassigned = FileManagerToolbarConfig(order: [], hidden: {});
      expect(unassigned.gridCornerStyle, GridCornerStyle.rounded);
      expect(unassigned.gridSpacing, 8);
    });

    test('copyWith updates the options and clamps spacing to 0..24', () {
      final config = FileManagerToolbarConfig.defaults();
      final updated = config.copyWith(
        gridCornerStyle: GridCornerStyle.square,
        gridSpacing: 0,
      );
      expect(updated.gridCornerStyle, GridCornerStyle.square);
      expect(updated.gridSpacing, 0);
      expect(config.copyWith(gridSpacing: 99).gridSpacing, 24);
      expect(config.copyWith(gridSpacing: -5).gridSpacing, 0);
    });

    test('round-trips through JSON', () {
      final config = FileManagerToolbarConfig.defaults().copyWith(
        gridCornerStyle: GridCornerStyle.square,
        gridSpacing: 14,
      );
      final json = config.toJson();
      expect(json['gridCornerStyle'], 'square');
      expect(json['gridSpacing'], 14);

      final restored = FileManagerToolbarConfig.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(restored.gridCornerStyle, GridCornerStyle.square);
      expect(restored.gridSpacing, 14);
    });

    test('configs saved before these options existed keep the old look', () {
      final legacy = FileManagerToolbarConfig.defaults().toJson()
        ..remove('gridCornerStyle')
        ..remove('gridSpacing');
      final restored = FileManagerToolbarConfig.fromJson(legacy);
      expect(restored.gridCornerStyle, GridCornerStyle.rounded);
      expect(restored.gridSpacing, 8);
    });

    test('an out-of-range stored spacing is clamped on load', () {
      final json = FileManagerToolbarConfig.defaults().toJson()
        ..['gridSpacing'] = 500;
      expect(FileManagerToolbarConfig.fromJson(json).gridSpacing, 24);
    });
  });

  group('FileManagerToolbarConfig skin', () {
    test('defaults to the classic skin', () {
      expect(FileManagerToolbarConfig.defaults().skin, FileManagerSkin.classic);
      expect(
        const FileManagerToolbarConfig(order: [], hidden: {}).skin,
        FileManagerSkin.classic,
      );
    });

    test('copyWith replaces only the skin', () {
      final base = FileManagerToolbarConfig.defaults().copyWith(
        showHiddenFiles: true,
      );
      final updated = base.copyWith(skin: SkinPreset.terminal.skin);

      expect(updated.skin, SkinPreset.terminal.skin);
      expect(updated.showHiddenFiles, isTrue);
      // Omitting skin keeps whatever was there.
      expect(updated.copyWith(showHiddenFiles: false).skin,
          SkinPreset.terminal.skin);
    });

    test('a skin survives the JSON round trip storage performs', () {
      const skin = FileManagerSkin(
        files: SkinItemStyle(
          iconFamily: SkinIconFamily.outlined,
          container: SkinContainerStyle.none,
          nameColor: Color(0xFF123456),
        ),
        monospaceNames: true,
      );
      final config = FileManagerToolbarConfig.defaults().copyWith(skin: skin);

      final restored = FileManagerToolbarConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
      );
      expect(restored.skin, skin);
    });

    test('configs saved before skins existed load with the classic skin', () {
      final legacy = FileManagerToolbarConfig.defaults().toJson()
        ..remove('skin');
      expect(legacy.containsKey('skin'), isFalse);

      final restored = FileManagerToolbarConfig.fromJson(legacy);
      expect(restored.skin, FileManagerSkin.classic);
      expect(FileManagerToolbarConfig.fromJson({}).skin,
          FileManagerSkin.classic);
    });

    test('a corrupted skin falls back to classic without losing the rest', () {
      final json = FileManagerToolbarConfig.defaults()
          .copyWith(showHiddenFiles: true)
          .toJson();
      json['skin'] = 'garbage';

      final restored = FileManagerToolbarConfig.fromJson(json);
      expect(restored.skin, FileManagerSkin.classic);
      expect(restored.showHiddenFiles, isTrue);
    });
  });

  group('FileManagerToolbarConfig resetSizeOnLayoutChange', () {
    test('is enabled by default in defaults() and the constructor', () {
      expect(FileManagerToolbarConfig.defaults().resetSizeOnLayoutChange,
          isTrue);
      expect(
        const FileManagerToolbarConfig(order: [], hidden: {})
            .resetSizeOnLayoutChange,
        isTrue,
      );
    });

    test('copyWith toggles it', () {
      final off = FileManagerToolbarConfig.defaults()
          .copyWith(resetSizeOnLayoutChange: false);
      expect(off.resetSizeOnLayoutChange, isFalse);
      expect(off.copyWith(resetSizeOnLayoutChange: true)
          .resetSizeOnLayoutChange, isTrue);
    });

    test('round-trips through JSON', () {
      final json = FileManagerToolbarConfig.defaults()
          .copyWith(resetSizeOnLayoutChange: false)
          .toJson();
      expect(json['resetSizeOnLayoutChange'], isFalse);
      expect(FileManagerToolbarConfig.fromJson(json).resetSizeOnLayoutChange,
          isFalse);
    });

    test('fromJson defaults to enabled when the key is missing', () {
      final config = FileManagerToolbarConfig.fromJson(
        <String, dynamic>{'showBreadcrumbBar': true},
      );
      expect(config.resetSizeOnLayoutChange, isTrue);
    });

    test('withDefaultSizes resets every size and nothing else', () {
      final custom = FileManagerToolbarConfig.defaults().copyWith(
        listZoomLevel: 1.8,
        gridColumnsPortrait: 1,
        gridColumnsLandscape: 7,
        masonryColumnsPortrait: 3,
        masonryColumnsLandscape: 6,
        showHiddenFiles: true,
        resetSizeOnLayoutChange: false,
        folderLayoutModes: const {'c:/a': 'grid'},
      );
      final reset = custom.withDefaultSizes();
      final defaults = FileManagerToolbarConfig.defaults();

      expect(reset.listZoomLevel, defaults.listZoomLevel);
      expect(reset.gridColumnsPortrait, defaults.gridColumnsPortrait);
      expect(reset.gridColumnsLandscape, defaults.gridColumnsLandscape);
      expect(reset.masonryColumnsPortrait, defaults.masonryColumnsPortrait);
      expect(reset.masonryColumnsLandscape, defaults.masonryColumnsLandscape);

      expect(reset.showHiddenFiles, isTrue);
      expect(reset.resetSizeOnLayoutChange, isFalse);
      expect(reset.folderLayoutModes, {'c:/a': 'grid'});
    });
  });
}
