import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/audio_recording_quality.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/browser_tab_edge_swipe.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/data/models/grid_corner_style.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/scrub_preview_style.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_generation_strategy.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/video_playback_mode.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

// Settings -> Export carries how the app *behaves*; App skin -> Export carries
// how it *looks and is laid out*. These tests pin the line between the two:
// every persisted field has to belong to exactly one side, and merging one
// side must never disturb the other.
//
// The fixtures deliberately set EVERY field away from its default, and a test
// checks that. A field added later therefore fails here until it has been
// given a side and a non-default fixture value, instead of silently falling
// out of both exports.

T _other<T extends Enum>(List<T> values, T current) =>
    values.firstWhere((value) => value != current);

Map<String, dynamic> _viaFile(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void _expectNoFieldAtDefault(
  Map<String, dynamic> custom,
  Map<String, dynamic> defaults,
  String group,
) {
  for (final key in defaults.keys) {
    expect(
      custom[key],
      isNot(equals(defaults[key])),
      reason:
          '"$key" is still at its default in the test fixture, so these tests '
          'could not notice it going missing from the $group export. Give it '
          'a non-default value in the fixture.',
    );
  }
}

AppSettings _customSettings() => AppSettings(
  // configuration
  useMasterPassword: true,
  masterUnlockMethod: MasterUnlockMethod.pin,
  defaultDocumentProvider: true,
  videoAutoPlay: false,
  blockScreenshots: false,
  keepVaultsRunningInBackground: true,
  defaultDerivedKeyCacheEnabled: true,
  lockContainersOnScreenLock: false,
  autoLockMins: 5,
  autoLockScreenLockOnly: true,
  lockAppOnScreenLock: false,
  appLockAfterMins: 3,
  appLockScreenLockOnly: true,
  extensionPreferences: {'pdf': 'com.example.reader'},
  autoOpenOnUnlock: true,
  htmlEnableJavaScript: true,
  languageCode: 'de',
  debugLoggingEnabled: true,
  deleteAfterImportMode: DeleteAfterImportMode.delete,
  audioRecordingQuality: AudioRecordingQuality.high,
  videoMuted: true,
  videoPlaybackMode: VideoPlaybackMode.loop,
  autoLockOnShareImport: false,
  quickActionLockMode: QuickActionLockMode.alwaysLock,
  enableAuthenticator: false,
  useBrowserTabs: false,
  useDualPaneBrowsing: true,
  tabEdgeSwipe: BrowserTabEdgeSwipe.loop,
  // interface
  themeMode: ThemeMode.dark,
  useDynamicColor: true,
  defaultLayoutMode: BrowserLayoutMode.masonry,
  defaultFileSortBy: SortBy.size,
  defaultFileSortAscending: false,
  containerSortMode: ContainerSortMode.nameZA,
  showStorageLocationsInDrawer: false,
  playlistScrollMode: PlaylistScrollMode.verticalPage,
  authenticatorShowNumbers: false,
  authenticatorSearchPlacement: AuthenticatorSearchPlacement.top,
  fileManagerSkin: const FileManagerSkin(monospaceNames: true),
  fileManagerFollowsAppSkin: false,
  editorFollowsAppSkin: false,
  editorAppearancePrefs: {'fontSize': 18.0, 'showLineNumbers': false},
  appBarAtBottom: true,
);

MediaViewerToolbarConfig _customViewer() {
  const d = MediaViewerToolbarConfig();
  return d.copyWith(
    // layout
    topBarActions: d.topBarActions.reversed.toList(),
    bottomBarActions: d.bottomBarActions.reversed.toList(),
    moreMenuActions: d.moreMenuActions.reversed.toList(),
    advancedSettingsActions: d.advancedSettingsActions.reversed.toList(),
    hiddenActions: {d.moreMenuActions.first},
    showProgressBar: !d.showProgressBar,
    showCenterTransport: !d.showCenterTransport,
    showPreviousNext: !d.showPreviousNext,
    showCenterScreenPlayButton: !d.showCenterScreenPlayButton,
    showCenterTransportForImages: !d.showCenterTransportForImages,
    showStatusBadge: !d.showStatusBadge,
    scrubPreviewStyle: ScrubPreviewStyle.fullscreen,
    // behavior
    loopPlaylist: !d.loopPlaylist,
    swipeToSeekEnabled: !d.swipeToSeekEnabled,
    thumbnailGenerationStrategy: ThumbnailGenerationStrategy.firstFrame,
    volumeBoostEnabled: !d.volumeBoostEnabled,
    seekSensitivity: 1.5,
  );
}

FileManagerToolbarConfig _customToolbar() {
  final d = FileManagerToolbarConfig.defaults();
  return d.copyWith(
    // layout
    order: d.order.reversed.toList(),
    hidden: {d.order.first},
    showBreadcrumbBar: !d.showBreadcrumbBar,
    showStatsBar: !d.showStatsBar,
    showBookmarkBar: !d.showBookmarkBar,
    showMediaCarousel: !d.showMediaCarousel,
    autoHideAppBar: !d.autoHideAppBar,
    showFileExtensions: !d.showFileExtensions,
    useFabForToolbar: !d.useFabForToolbar,
    bottomSelectionBar: !d.bottomSelectionBar,
    detailColumnsOrder: d.detailColumnsOrder.reversed.toList(),
    hiddenDetailColumns: {d.detailColumnsOrder.first},
    itemActionsOrder: d.itemActionsOrder.reversed.toList(),
    hiddenItemActions: {d.itemActionsOrder.first},
    showGridFileNames: !d.showGridFileNames,
    gridAspectRatio: _other(GridAspectRatio.values, d.gridAspectRatio),
    gridCornerStyle: _other(GridCornerStyle.values, d.gridCornerStyle),
    gridSpacing: d.gridSpacing + 4,
    showListThumbnails: !d.showListThumbnails,
    showItemActionsMenu: !d.showItemActionsMenu,
    longFileNameDisplayMode: _other(
      LongFileNameDisplayMode.values,
      d.longFileNameDisplayMode,
    ),
    listZoomLevel: d.listZoomLevel + 0.5,
    gridColumnsPortrait: d.gridColumnsPortrait + 1,
    gridColumnsLandscape: d.gridColumnsLandscape + 1,
    masonryColumnsPortrait: d.masonryColumnsPortrait + 1,
    masonryColumnsLandscape: d.masonryColumnsLandscape + 1,
    playlistTransitionEffect: _other(
      PlaylistTransitionEffect.values,
      d.playlistTransitionEffect,
    ),
    skin: const FileManagerSkin(monospaceNames: true),
    // behavior
    showHiddenFiles: !d.showHiddenFiles,
    selectByIcon: !d.selectByIcon,
    autoStartPlaylistMode: !d.autoStartPlaylistMode,
    rememberPerFolderLayout: !d.rememberPerFolderLayout,
    resetSizeOnLayoutChange: !d.resetSizeOnLayoutChange,
    defaultThumbnailCacheMode: _other(
      ThumbnailCacheMode.values,
      d.defaultThumbnailCacheMode,
    ),
    defaultThumbnailQuality: const ThumbnailQuality(quality: 60, size: 240),
    localStorageThumbnailCacheMode: _other(
      ThumbnailCacheMode.values,
      d.localStorageThumbnailCacheMode,
    ),
    localStorageThumbnailQuality: const ThumbnailQuality(
      quality: 70,
      size: 300,
    ),
    // per-container (in neither export)
    folderLayoutModes: {'c:/a': 'grid'},
    folderGridAspectRatios: {'c:/a': 'portrait'},
    folderSortModes: {'c:/a': 'size'},
    mediaViewerToolbarConfig: _customViewer(),
  );
}

void main() {
  group('AppSettings', () {
    test('every persisted key belongs to exactly one group', () {
      final settings = AppSettings();
      final groups = [
        settings.configurationToJson().keys,
        settings.interfaceToJson().keys,
        settings.skinsToJson().keys,
      ];
      final total = groups.expand((keys) => keys).length;

      expect(settings.toJson().keys.length, total);
    });

    test('the fixture moves every configuration and interface field', () {
      final custom = _customSettings();
      final defaults = AppSettings();

      _expectNoFieldAtDefault(
        custom.configurationToJson(),
        defaults.configurationToJson(),
        'configuration',
      );
      _expectNoFieldAtDefault(
        custom.interfaceToJson(),
        defaults.interfaceToJson(),
        'interface',
      );
    });

    test('withConfigurationFrom copies the configuration and only that', () {
      final custom = _customSettings();
      final defaults = AppSettings();

      final merged = defaults.withConfigurationFrom(custom);

      expect(merged.configurationToJson(), custom.configurationToJson());
      expect(merged.interfaceToJson(), defaults.interfaceToJson());
      expect(merged.skinsToJson(), defaults.skinsToJson());
    });

    test('withInterfaceFrom copies the interface and only that', () {
      final custom = _customSettings();
      final defaults = AppSettings();

      final merged = defaults.withInterfaceFrom(custom);

      expect(merged.interfaceToJson(), custom.interfaceToJson());
      expect(merged.configurationToJson(), defaults.configurationToJson());
      expect(merged.skinsToJson(), defaults.skinsToJson());
    });

    test('a language cleared in the source is cleared in the result', () {
      final current = AppSettings(languageCode: 'fr');

      final merged = current.withConfigurationFrom(AppSettings());

      expect(merged.languageCode, isNull);
    });

    test('merging never disturbs the stored password hash', () {
      final current = AppSettings().copyWith(masterPasswordHash: 'stored-hash');

      final merged = current
          .withConfigurationFrom(_customSettings())
          .withInterfaceFrom(_customSettings());

      expect(merged.masterPasswordHash, 'stored-hash');
    });

    test('the configuration export contains no interface setting', () {
      final configurationKeys = _customSettings().configurationToJson().keys;
      final interfaceKeys = _customSettings().interfaceToJson().keys;

      expect(configurationKeys.toSet().intersection(interfaceKeys.toSet()),
          isEmpty);
      // Spot-check the ones people most expect to travel with their skin.
      for (final key in [
        'themeMode',
        'useDynamicColor',
        'editorAppearancePrefs',
        'defaultLayoutMode',
        'containerSortMode',
        'showStorageLocationsInDrawer',
        'authenticatorShowNumbers',
        'fileManagerSkin',
        'fileManagerFollowsAppSkin',
      ]) {
        expect(configurationKeys, isNot(contains(key)), reason: key);
        expect(interfaceKeys, contains(key), reason: key);
      }
    });
  });

  group('MediaViewerToolbarConfig', () {
    test('every interface key is a real key', () {
      final keys = const MediaViewerToolbarConfig().toJson().keys.toSet();

      expect(MediaViewerToolbarConfig.interfaceKeys.difference(keys), isEmpty);
    });

    test('the two exports split toJson with no overlap', () {
      final config = _customViewer();
      final interfaceKeys = config.interfaceToJson().keys.toSet();
      final behaviorKeys = config.behaviorToJson().keys.toSet();

      expect(interfaceKeys.intersection(behaviorKeys), isEmpty);
      expect(interfaceKeys.union(behaviorKeys), config.toJson().keys.toSet());
    });

    test('withInterfaceFrom takes the layout and keeps the behavior', () {
      final base = const MediaViewerToolbarConfig().copyWith(
        loopPlaylist: false,
        seekSensitivity: 0.5,
      );

      final merged = base.withInterfaceFrom(_customViewer());

      expect(
        merged.interfaceToJson(),
        _customViewer().interfaceToJson(),
      );
      expect(merged.behaviorToJson(), base.behaviorToJson());
    });

    test('withBehaviorFrom takes the behavior and keeps the layout', () {
      final base = const MediaViewerToolbarConfig().copyWith(
        showProgressBar: false,
      );

      final merged = base.withBehaviorFrom(_customViewer());

      expect(
        merged.behaviorToJson(),
        _customViewer().behaviorToJson(),
      );
      expect(merged.interfaceToJson(), base.interfaceToJson());
    });
  });

  group('FileManagerToolbarConfig', () {
    test('every key of toJson is classified exactly once', () {
      final all = FileManagerToolbarConfig.defaults().toJson().keys.toSet();
      final classified = [
        ...FileManagerToolbarConfig.interfaceKeys,
        ...FileManagerToolbarConfig.behaviorKeys,
        ...FileManagerToolbarConfig.perFolderKeys,
        // Split between the two exports by MediaViewerToolbarConfig.
        'mediaViewerToolbarConfig',
      ];

      expect(classified.toSet(), all);
      expect(classified.length, all.length);
    });

    test('the fixture moves every exported field', () {
      final custom = _customToolbar();
      final defaults = FileManagerToolbarConfig.defaults();

      _expectNoFieldAtDefault(
        custom.interfaceToJson(),
        defaults.interfaceToJson(),
        'interface',
      );
      _expectNoFieldAtDefault(
        custom.behaviorToJson(),
        defaults.behaviorToJson(),
        'configuration',
      );
    });

    test('neither export contains per-folder layout memory', () {
      final custom = _customToolbar();

      for (final export in [custom.interfaceToJson(), custom.behaviorToJson()]) {
        for (final key in FileManagerToolbarConfig.perFolderKeys) {
          expect(export.containsKey(key), isFalse, reason: key);
        }
      }
    });

    test('the layout export holds no behavior option and vice versa', () {
      final custom = _customToolbar();

      expect(
        custom.interfaceToJson().keys.toSet().intersection(
          FileManagerToolbarConfig.behaviorKeys,
        ),
        isEmpty,
      );
      expect(
        custom.behaviorToJson().keys.toSet().intersection(
          FileManagerToolbarConfig.interfaceKeys,
        ),
        isEmpty,
      );
    });

    test('withInterfaceFrom takes the layout, keeps behavior and folders', () {
      final base = FileManagerToolbarConfig.defaults().copyWith(
        showHiddenFiles: true,
        defaultThumbnailQuality: const ThumbnailQuality(quality: 50, size: 120),
        folderLayoutModes: {'d:/x': 'list'},
        mediaViewerToolbarConfig: const MediaViewerToolbarConfig().copyWith(
          loopPlaylist: false,
        ),
      );

      final merged = base.withInterfaceFrom(_customToolbar());

      expect(merged.interfaceToJson(), _customToolbar().interfaceToJson());
      expect(merged.behaviorToJson(), base.behaviorToJson());
      expect(merged.folderLayoutModes, {'d:/x': 'list'});
    });

    test('withBehaviorFrom takes the behavior, keeps layout and folders', () {
      final base = FileManagerToolbarConfig.defaults().copyWith(
        gridSpacing: 2,
        folderSortModes: {'d:/x': 'date'},
        mediaViewerToolbarConfig: const MediaViewerToolbarConfig().copyWith(
          showProgressBar: false,
        ),
      );

      final merged = base.withBehaviorFrom(_customToolbar());

      expect(merged.behaviorToJson(), _customToolbar().behaviorToJson());
      expect(merged.interfaceToJson(), base.interfaceToJson());
      expect(merged.folderSortModes, {'d:/x': 'date'});
    });

    test('each export survives being written to a file and read back', () {
      final custom = _customToolbar();

      final layout = FileManagerToolbarConfig.fromJson(
        _viaFile(custom.interfaceToJson()),
      );
      final behavior = FileManagerToolbarConfig.fromJson(
        _viaFile(custom.behaviorToJson()),
      );

      expect(layout.interfaceToJson(), custom.interfaceToJson());
      expect(behavior.behaviorToJson(), custom.behaviorToJson());
    });

    test('importing both halves reproduces the original', () {
      final custom = _customToolbar();
      final layoutFile = FileManagerToolbarConfig.fromJson(
        _viaFile(custom.interfaceToJson()),
      );
      final behaviorFile = FileManagerToolbarConfig.fromJson(
        _viaFile(custom.behaviorToJson()),
      );

      final restored = FileManagerToolbarConfig.defaults()
          .withInterfaceFrom(layoutFile)
          .withBehaviorFrom(behaviorFile);

      expect(restored.interfaceToJson(), custom.interfaceToJson());
      expect(restored.behaviorToJson(), custom.behaviorToJson());
    });
  });
}
