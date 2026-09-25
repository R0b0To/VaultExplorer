import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/browser/viewer/media_prefetch_controller.dart';

/// These only exercise `preloadAspectRatios`' guard clauses -- the paths
/// that return/continue *before* ever touching `ThumbnailCacheService`'s
/// disk/channel tiers -- since that service is a static singleton that
/// needs `ThumbnailCacheService.configure(...)` (a real VaultFileIoApi,
/// VaultCryptoApi, VaultHashApi) to do a real fetch. That's deliberate:
/// every case below should return without ever reaching `fetchWithSize`,
/// so leaving the service unconfigured is itself part of the check -- if
/// one of these guards were accidentally removed, the test would fail
/// with the service's "must be configured" StateError instead of a
/// mismatched expectation, which is arguably even clearer.
void main() {
  const fileIoApi = VaultFileIoApi(MethodChannel('test/file-io'));
  const thumbnailCache = ThumbnailCacheService();

  final container = MountedContainer(
    volId: 1,
    uri: 'file:///vault.hc',
    displayName: 'Vault',
    rootFiles: const [],
    mountedAt: DateTime(2026, 1, 1),
    totalSpace: 1000000,
    freeSpace: 500000,
    containerFormat: 'veracrypt',
  );

  MediaPrefetchController buildController(ThumbnailCacheMode mode) =>
      MediaPrefetchController(
        container: container,
        fileIoApi: fileIoApi,
        thumbnailCache: thumbnailCache,
        thumbnailQuality: ThumbnailQuality.defaultQuality,
        thumbnailCacheMode: mode,
      );

  tearDown(() {
    MediaAspectRatioCache.clearForUri(container.uri);
  });

  group('preloadAspectRatios', () {
    test('does nothing when the thumbnail cache is disabled', () async {
      final controller = buildController(ThumbnailCacheMode.disabled);
      var learned = 0;

      await controller.preloadAspectRatios(
        ['a.jpg', 'b.png'],
        isStillWanted: () => true,
        onRatioLearned: () => learned++,
      );

      expect(learned, 0);
    });

    test('stops immediately when isStillWanted is already false', () async {
      final controller = buildController(ThumbnailCacheMode.appCache);
      var learned = 0;

      await controller.preloadAspectRatios(
        ['a.jpg', 'b.jpg'],
        isStillWanted: () => false,
        onRatioLearned: () => learned++,
      );

      expect(learned, 0);
    });

    test('skips files that are neither images nor videos', () async {
      final controller = buildController(ThumbnailCacheMode.appCache);
      var learned = 0;

      // None of these are MediaViewerConstants.isImage/isVideo, so the
      // loop should `continue` past all of them without ever reaching
      // ThumbnailCacheService -- if it did, this test would fail with a
      // "must be configured" StateError rather than the plain assertion
      // below, since the static engine APIs were never wired up here.
      await controller.preloadAspectRatios(
        ['track.mp3', 'notes.txt', 'archive.zip'],
        isStillWanted: () => true,
        onRatioLearned: () => learned++,
      );

      expect(learned, 0);
    });

    test('skips files whose aspect ratio is already cached', () async {
      MediaAspectRatioCache.put(container, 'already-known.jpg', 16, 9);
      final controller = buildController(ThumbnailCacheMode.appCache);
      var learned = 0;

      await controller.preloadAspectRatios(
        ['already-known.jpg'],
        isStillWanted: () => true,
        onRatioLearned: () => learned++,
      );

      expect(learned, 0);
    });

    test('re-checks isStillWanted between items, not just once up front',
        () async {
      // Pre-cache every filename so each iteration `continue`s at the
      // cache-hit check without ever reaching ThumbnailCacheService --
      // isolates this test to the isStillWanted-per-item behavior itself.
      MediaAspectRatioCache.put(container, 'a.jpg', 16, 9);
      final controller = buildController(ThumbnailCacheMode.appCache);
      var checks = 0;

      await controller.preloadAspectRatios(
        ['a.jpg', 'b.jpg', 'c.jpg'],
        // Wants the first item, bails before the second -- if the
        // controller only checked once before the loop, all three
        // filenames would be (attempted to be) processed.
        isStillWanted: () => (checks++) == 0,
        onRatioLearned: () {},
      );

      expect(checks, 2);
    });
  });
}
