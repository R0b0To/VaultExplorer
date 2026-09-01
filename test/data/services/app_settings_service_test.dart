import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

// Tests for the AppSettings model itself -- pure in-memory JSON/copyWith
// logic, no file I/O. AppSettingsService's actual read/write to disk (via
// path_provider + dart:io File) isn't covered here; that would need a
// path_provider mock similar to how VaultItemsServiceTest fakes the
// injected VaultLifecycleApi/VaultFileIoApi, and is a reasonable next
// step but a separate one.
void main() {
  group('AppSettings defaults', () {
    test('a freshly-constructed instance has the documented defaults', () {
      final s = AppSettings();
      expect(s.useMasterPassword, isFalse);
      expect(s.masterPasswordIsFingerprint, isFalse);
      expect(s.videoAutoPlay, isTrue);
      expect(s.blockScreenshots, isFalse);
      expect(s.lockContainersOnScreenLock, isTrue);
      expect(s.defaultDerivedKeyCacheEnabled, isFalse);
      expect(s.autoLockMins, 0);
      expect(s.defaultLayoutMode, BrowserLayoutMode.list);
      // Note this is `disabled`, not `appCache` -- see the
      // 'fromJson({}) vs a fresh AppSettings()' group below for why that
      // distinction matters.
      expect(s.defaultThumbnailCacheMode, ThumbnailCacheMode.disabled);
      expect(s.defaultThumbnailQuality, ThumbnailQuality.defaultQuality);
      expect(s.containerSortMode, ContainerSortMode.manual);
      expect(s.themeMode, ThemeMode.system);
      expect(s.defaultFileSortBy, SortBy.name);
      expect(s.defaultFileSortAscending, isTrue);
      expect(s.playlistScrollMode, PlaylistScrollMode.horizontal);
      expect(s.deleteAfterImportMode, DeleteAfterImportMode.ask);
      expect(s.languageCode, isNull);
      expect(s.extensionPreferences, isEmpty);
      expect(s.masterPasswordHash, isNull);
      expect(s.masterPasswordSalt, isNull);
      expect(s.needsHashUpgrade, isFalse);
    });

    test('playlistScrollDirection is derived from playlistScrollMode', () {
      final s = AppSettings();
      expect(s.playlistScrollDirection, Axis.horizontal);
    });
  });

  group('AppSettings JSON round-trip', () {
    test('every field set to a non-default value survives toJson -> '
        'fromJson', () {
      final original = AppSettings(
        useMasterPassword: true,
        masterPasswordIsFingerprint: true,
        defaultDocumentProvider: true,
        videoAutoPlay: false,
        blockScreenshots: true,
        keepVaultsRunningInBackground: true,
        hasSeenSwipeTutorial: true,
        lockContainersOnScreenLock: false,
        defaultDerivedKeyCacheEnabled: true,
        autoLockMins: 5,
        defaultLayoutMode: BrowserLayoutMode.masonry,
        defaultThumbnailCacheMode: ThumbnailCacheMode.inContainer,
        defaultThumbnailQuality: const ThumbnailQuality(quality: 55, size: 240),
        containerSortMode: ContainerSortMode.newest,
        swapCardActions: true,
        themeMode: ThemeMode.dark,
        useDynamicColor: true,
        autoOpenOnUnlock: true,
        defaultFileSortBy: SortBy.date,
        defaultFileSortAscending: false,
        htmlEnableJavaScript: true,
        playlistScrollMode: PlaylistScrollMode.verticalContinuous,
        languageCode: 'de',
        debugLoggingEnabled: true,
        deleteAfterImportMode: DeleteAfterImportMode.delete,
        extensionPreferences: {'txt': 'com.example.editor'},
      );

      final roundTripped = AppSettings.fromJson(original.toJson());

      expect(roundTripped.useMasterPassword, original.useMasterPassword);
      expect(roundTripped.masterPasswordIsFingerprint, original.masterPasswordIsFingerprint);
      expect(roundTripped.defaultDocumentProvider, original.defaultDocumentProvider);
      expect(roundTripped.videoAutoPlay, original.videoAutoPlay);
      expect(roundTripped.blockScreenshots, original.blockScreenshots);
      expect(roundTripped.keepVaultsRunningInBackground, original.keepVaultsRunningInBackground);
      expect(roundTripped.hasSeenSwipeTutorial, original.hasSeenSwipeTutorial);
      expect(roundTripped.lockContainersOnScreenLock, original.lockContainersOnScreenLock);
      expect(roundTripped.defaultDerivedKeyCacheEnabled, original.defaultDerivedKeyCacheEnabled);
      expect(roundTripped.autoLockMins, original.autoLockMins);
      expect(roundTripped.defaultLayoutMode, original.defaultLayoutMode);
      expect(roundTripped.defaultThumbnailCacheMode, original.defaultThumbnailCacheMode);
      expect(roundTripped.defaultThumbnailQuality, original.defaultThumbnailQuality);
      expect(roundTripped.containerSortMode, original.containerSortMode);
      expect(roundTripped.swapCardActions, original.swapCardActions);
      expect(roundTripped.themeMode, original.themeMode);
      expect(roundTripped.useDynamicColor, original.useDynamicColor);
      expect(roundTripped.autoOpenOnUnlock, original.autoOpenOnUnlock);
      expect(roundTripped.defaultFileSortBy, original.defaultFileSortBy);
      expect(roundTripped.defaultFileSortAscending, original.defaultFileSortAscending);
      expect(roundTripped.htmlEnableJavaScript, original.htmlEnableJavaScript);
      expect(roundTripped.playlistScrollMode, original.playlistScrollMode);
      expect(roundTripped.languageCode, original.languageCode);
      expect(roundTripped.debugLoggingEnabled, original.debugLoggingEnabled);
      expect(roundTripped.deleteAfterImportMode, original.deleteAfterImportMode);
      expect(roundTripped.extensionPreferences, original.extensionPreferences);
    });

    test('toJson never includes the master password hash or salt -- those '
        'are only ever persisted via secure storage, never the plain '
        'settings file', () {
      final s = AppSettings(
        masterPasswordHash: 'somehash',
        masterPasswordSalt: 'somesalt',
      );
      final json = s.toJson();
      expect(json.containsKey('masterPasswordHash'), isFalse);
      expect(json.containsKey('masterPasswordSalt'), isFalse);
      expect(json.containsKey('_masterPasswordHash'), isFalse);
      expect(json.containsKey('_masterPasswordSalt'), isFalse);
    });

    test('fromJson ignores masterPasswordHash/masterPasswordSalt even if '
        'somehow present in the input -- confirms the only way to end up '
        'with hash material on an AppSettings is via the constructor '
        '(i.e. AppSettingsService loading it from secure storage '
        'separately), never from the settings JSON itself', () {
      final s = AppSettings.fromJson({
        'masterPasswordHash': 'shouldbeignored',
        'masterPasswordSalt': 'shouldalsobeignored',
      });
      expect(s.masterPasswordHash, isNull);
      expect(s.masterPasswordSalt, isNull);
    });

    test('fromJson({}) does not throw and produces sensible fallbacks', () {
      final s = AppSettings.fromJson({});
      expect(s.useMasterPassword, isFalse);
      expect(s.videoAutoPlay, isTrue);
      expect(s.autoLockMins, 0);
      expect(s.defaultLayoutMode, BrowserLayoutMode.list);
      expect(s.containerSortMode, ContainerSortMode.manual);
      expect(s.themeMode, ThemeMode.system);
      expect(s.defaultFileSortBy, SortBy.name);
      expect(s.playlistScrollMode, PlaylistScrollMode.horizontal);
      expect(s.deleteAfterImportMode, DeleteAfterImportMode.ask);
      expect(s.extensionPreferences, isEmpty);
    });

    test('an empty JSON object and a freshly-constructed AppSettings() '
        'disagree on defaultThumbnailCacheMode -- fromJson({}) falls back '
        'to appCache, but AppSettings() defaults to disabled. Worth '
        'confirming with whoever maintains this whether that\'s '
        'intentional (e.g. "assume caching was on until proven otherwise, '
        'for anything that looks like an existing install") or a copy-paste '
        'slip between the two default values.', () {
      expect(
        AppSettings().defaultThumbnailCacheMode,
        ThumbnailCacheMode.disabled,
      );
      expect(
        AppSettings.fromJson({}).defaultThumbnailCacheMode,
        ThumbnailCacheMode.appCache,
      );
    });

    test('a non-string value inside extensionPreferences throws rather '
        'than being silently dropped or coerced -- pinning current '
        'behavior; if a hand-edited or foreign settings file could '
        'plausibly contain one, this is worth hardening', () {
      expect(
        () => AppSettings.fromJson({
          'extensionPreferences': {'txt': 123},
        }),
        throwsA(isA<TypeError>()),
      );
    });

    group('playlistScrollMode / legacy playlistScrollDirection fallback', () {
      test('reads the legacy playlistScrollDirection key when '
          'playlistScrollMode is absent', () {
        expect(
          AppSettings.fromJson({'playlistScrollDirection': 'vertical'})
              .playlistScrollMode,
          PlaylistScrollMode.verticalPage,
        );
      });

      test('playlistScrollMode takes priority when both keys are present',
          () {
        expect(
          AppSettings.fromJson({
            'playlistScrollMode': 'verticalContinuous',
            'playlistScrollDirection': 'horizontal',
          }).playlistScrollMode,
          PlaylistScrollMode.verticalContinuous,
        );
      });

      test('both absent defaults to horizontal', () {
        expect(AppSettings.fromJson({}).playlistScrollMode, PlaylistScrollMode.horizontal);
      });
    });
  });

  group('AppSettings.needsHashUpgrade', () {
    test('no hash at all -> false', () {
      expect(AppSettings().needsHashUpgrade, isFalse);
    });

    test('an 8-character hash with no salt -> true (the legacy marker)', () {
      final s = AppSettings(masterPasswordHash: '12345678');
      expect(s.needsHashUpgrade, isTrue);
    });

    test('an 8-character hash with an empty-string salt -> true', () {
      final s = AppSettings(masterPasswordHash: '12345678', masterPasswordSalt: '');
      expect(s.needsHashUpgrade, isTrue);
    });

    test('an 8-character hash WITH a real salt -> false, already upgraded',
        () {
      final s = AppSettings(masterPasswordHash: '12345678', masterPasswordSalt: 'abc');
      expect(s.needsHashUpgrade, isFalse);
    });

    test('a hash of any other length -> false, regardless of salt', () {
      final s = AppSettings(masterPasswordHash: 'a-much-longer-modern-hash-value');
      expect(s.needsHashUpgrade, isFalse);
    });
  });

  group('AppSettings.copyWith', () {
    test('with no arguments, every field is unchanged', () {
      final original = AppSettings(
        useMasterPassword: true,
        autoLockMins: 7,
        themeMode: ThemeMode.dark,
        masterPasswordHash: 'h',
        masterPasswordSalt: 's',
      );
      final copy = original.copyWith();

      expect(copy.useMasterPassword, original.useMasterPassword);
      expect(copy.autoLockMins, original.autoLockMins);
      expect(copy.themeMode, original.themeMode);
      expect(copy.masterPasswordHash, original.masterPasswordHash);
      expect(copy.masterPasswordSalt, original.masterPasswordSalt);
    });

    test('changing one field leaves the others alone', () {
      final original = AppSettings(autoLockMins: 1, useMasterPassword: true);
      final copy = original.copyWith(autoLockMins: 10);

      expect(copy.autoLockMins, 10);
      expect(copy.useMasterPassword, isTrue); // unchanged
    });

    test('omitting masterPasswordSalt in copyWith preserves the existing '
        'salt rather than clearing it', () {
      final original = AppSettings(masterPasswordHash: 'h1', masterPasswordSalt: 's1');
      final copy = original.copyWith(masterPasswordHash: 'h2');

      expect(copy.masterPasswordHash, 'h2');
      expect(copy.masterPasswordSalt, 's1');
    });

    test('the playlistScrollDirection convenience parameter can silently '
        'downgrade an existing verticalContinuous setting to verticalPage '
        '-- Axis only has two values, so passing '
        'Axis.vertical can\'t distinguish "paged" from "continuous". '
        'Passing playlistScrollMode explicitly avoids this; this test '
        'documents the trade-off rather than asserting it\'s a bug.', () {
      final original = AppSettings(playlistScrollMode: PlaylistScrollMode.verticalContinuous);
      final copy = original.copyWith(playlistScrollDirection: Axis.vertical);
      expect(copy.playlistScrollMode, PlaylistScrollMode.verticalPage);
    });

    test('passing playlistScrollMode explicitly overrides '
        'playlistScrollDirection', () {
      final original = AppSettings(playlistScrollMode: PlaylistScrollMode.horizontal);
      final copy = original.copyWith(
        playlistScrollMode: PlaylistScrollMode.verticalContinuous,
        playlistScrollDirection: Axis.horizontal,
      );
      expect(copy.playlistScrollMode, PlaylistScrollMode.verticalContinuous);
    });

    test('omitting both playlistScrollMode and playlistScrollDirection '
        'keeps the current mode untouched', () {
      final original = AppSettings(playlistScrollMode: PlaylistScrollMode.verticalContinuous);
      final copy = original.copyWith(autoLockMins: 3);
      expect(copy.playlistScrollMode, PlaylistScrollMode.verticalContinuous);
    });
  });
}
