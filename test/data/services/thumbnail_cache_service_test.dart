import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Fake proving the pattern documented in vault_explorer_api_test.dart:
/// extend the concrete class, override only what a test needs.
class _FakeVaultExplorerApi extends VaultExplorerApi {
  final List<String> finishWriteCalls = [];
  bool writeFileChunkResult = true;
  bool finishWriteResult = true;

  @override
  Future<bool> createDirectory(MountedContainer container, String dirPath) async =>
      true;

  @override
  Future<bool> writeFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    Uint8List data,
  ) async =>
      writeFileChunkResult;

  @override
  Future<bool> finishWrite(
    MountedContainer container,
    String fileName,
  ) async {
    finishWriteCalls.add(container.containerFormat);
    return finishWriteResult;
  }
}

MountedContainer _container(String format, String uri) => MountedContainer(
      uri: uri,
      displayName: 'test',
      volId: uri.hashCode,
      rootFiles: const [],
      mountedAt: DateTime.now(),
      totalSpace: 0,
      freeSpace: 0,
      containerFormat: format,
    );

void main() {
  // vaultExplorerApi is a single top-level variable shared process-wide
  // (see vault_explorer_api_test.dart), so every test that swaps it must
  // put the real implementation back.
  tearDown(() => vaultExplorerApi = const VaultExplorerApi());

  for (final format in ['cryptomator', 'gocryptfs', 'cryfs']) {
    test(
      'put() commits the in-container write for $format containers',
      () async {
        final fake = _FakeVaultExplorerApi();
        vaultExplorerApi = fake;

        await ThumbnailCacheService.put(
          container: _container(format, 'content://$format-vault'),
          filePath: '/pictures/photo.jpg',
          data: Uint8List.fromList([1, 2, 3]),
          mode: ThumbnailCacheMode.inContainer,
          quality: ThumbnailQuality.defaultQuality,
        );

        // Before the fix, this only fired for containerFormat == 'cryptomator',
        // so gocryptfs/cryfs thumbnails were written via writeFileChunk() but
        // never committed (left in an open write handle / uncommitted CryFS
        // staging file) and effectively lost.
        expect(
          fake.finishWriteCalls,
          contains(format),
          reason: 'finishWrite should commit the buffered writeFileChunk() '
              'for $format, not just Cryptomator',
        );
      },
    );
  }

  test('put() does not attempt a commit when writeFileChunk itself fails', () async {
    final fake = _FakeVaultExplorerApi()..writeFileChunkResult = false;
    vaultExplorerApi = fake;

    await ThumbnailCacheService.put(
      container: _container('gocryptfs', 'content://write-fails'),
      filePath: '/pictures/photo.jpg',
      data: Uint8List.fromList([1, 2, 3]),
      mode: ThumbnailCacheMode.inContainer,
      quality: ThumbnailQuality.defaultQuality,
    );

    expect(fake.finishWriteCalls, isEmpty);
  });

  test('put() completes without throwing when the commit step fails', () async {
    final fake = _FakeVaultExplorerApi()..finishWriteResult = false;
    vaultExplorerApi = fake;

    // A failed commit is now logged (see ThumbnailCacheService.put's
    // debugPrint) rather than silently swallowed by an empty catch, but it
    // must still not propagate — put() is a best-effort cache write and
    // must not crash callers that generate/display a thumbnail.
    await expectLater(
      ThumbnailCacheService.put(
        container: _container('cryfs', 'content://commit-fails'),
        filePath: '/pictures/photo.jpg',
        data: Uint8List.fromList([1, 2, 3]),
        mode: ThumbnailCacheMode.inContainer,
        quality: ThumbnailQuality.defaultQuality,
      ),
      completes,
    );
    expect(fake.finishWriteCalls, contains('cryfs'));
  });
}