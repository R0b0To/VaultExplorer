import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Fake proving the pattern documented in vault_explorer_api_test.dart:
/// extend the concrete class, override only what a test needs.
///
/// Also fakes [deleteFile]/[renameFile] now: put()'s in-container branch
/// writes via the inherited [VaultExplorerApi.writeWholeFile] (stage to a
/// `.tmp` path, commit, delete the old file, rename into place) rather
/// than calling writeFileChunk/finishWrite directly on the final path, so
/// every step of that chain needs a fake, not just the two calls this
/// test used to touch.
class _FakeVaultExplorerApi extends VaultExplorerApi {
  final List<String> finishWriteCalls = [];
  final List<String> deletedPaths = [];
  final List<(String, String)> renames = [];
  bool writeFileChunkResult = true;
  bool finishWriteResult = true;
  bool renameFileResult = true;

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

  @override
  Future<bool> deleteFile(MountedContainer container, String fileName) async {
    deletedPaths.add(fileName);
    return true;
  }

  @override
  Future<bool> renameFile(
    MountedContainer container,
    String oldPath,
    String newPath,
  ) async {
    renames.add((oldPath, newPath));
    return renameFileResult;
  }

  // ThumbnailCacheService._encodeKey now hashes natively (see
  // HashVerifierHandlers.kt); this test only cares that put() reaches
  // finishWrite, not the actual cache-key value, so a cheap deterministic
  // stand-in is enough -- no real MessageDigest needed here.
  @override
  Future<String> hashBytesMd5(Uint8List bytes) async {
    var acc = bytes.length;
    for (final b in bytes) {
      acc = (acc * 31 + b) & 0x7fffffff;
    }
    return acc.toRadixString(16).padLeft(32, '0');
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

/// Minimal bytes that satisfy ThumbnailCacheService's cheap structural
/// JPEG check (SOI 0xFFD8 .. EOI 0xFFD9) without being a real decodable
/// image -- these tests are about the write/commit path, not decoding.
Uint8List _fakeJpegBytes() => Uint8List.fromList([0xFF, 0xD8, 0x00, 0xFF, 0xD9]);

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
          data: _fakeJpegBytes(),
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

  test('put() writes through the atomic stage-then-rename path, not straight to the final path', () async {
    final fake = _FakeVaultExplorerApi();
    vaultExplorerApi = fake;

    await ThumbnailCacheService.put(
      container: _container('gocryptfs', 'content://atomic-write'),
      filePath: '/pictures/photo.jpg',
      data: _fakeJpegBytes(),
      mode: ThumbnailCacheMode.inContainer,
      quality: ThumbnailQuality.defaultQuality,
    );

    // writeWholeFile's contract: stage to "<final>.tmp", commit it, then
    // delete+rename into the real path -- never a direct write to the
    // final cache path, which is what let a torn/interrupted write leave
    // corrupt bytes sitting at a path nothing ever re-validated.
    expect(fake.renames, hasLength(1));
    final (from, to) = fake.renames.single;
    expect(from, equals('$to.tmp'));
  });

  test('put() rejects data that is not a well-formed JPEG and never touches the vault API', () async {
    final fake = _FakeVaultExplorerApi();
    vaultExplorerApi = fake;

    await ThumbnailCacheService.put(
      container: _container('gocryptfs', 'content://malformed'),
      filePath: '/pictures/photo.jpg',
      data: Uint8List.fromList([1, 2, 3]), // no SOI/EOI markers
      mode: ThumbnailCacheMode.inContainer,
      quality: ThumbnailQuality.defaultQuality,
    );

    expect(fake.finishWriteCalls, isEmpty);
    expect(fake.renames, isEmpty);
  });

  test('two concurrent put() calls for the same target coalesce into a single write', () async {
    final fake = _FakeVaultExplorerApi();
    vaultExplorerApi = fake;

    final container = _container('gocryptfs', 'content://coalesce');
    final args = (
      filePath: '/pictures/photo.jpg',
      data: _fakeJpegBytes(),
      mode: ThumbnailCacheMode.inContainer,
      quality: ThumbnailQuality.defaultQuality,
    );

    // Fired without awaiting between them, exactly like the surrounding-
    // item prefetch loop and the playlist carousel's independent fetch
    // can both do for the same upcoming file.
    final a = ThumbnailCacheService.put(
      container: container,
      filePath: args.filePath,
      data: args.data,
      mode: args.mode,
      quality: args.quality,
    );
    final b = ThumbnailCacheService.put(
      container: container,
      filePath: args.filePath,
      data: args.data,
      mode: args.mode,
      quality: args.quality,
    );

    await Future.wait([a, b]);

    expect(
      fake.renames,
      hasLength(1),
      reason: 'two concurrent put() calls for the identical target should '
          'only perform one actual write',
    );
  });

  test('put() does not attempt a commit when writeFileChunk itself fails', () async {
    final fake = _FakeVaultExplorerApi()..writeFileChunkResult = false;
    vaultExplorerApi = fake;

    await ThumbnailCacheService.put(
      container: _container('gocryptfs', 'content://write-fails'),
      filePath: '/pictures/photo.jpg',
      data: _fakeJpegBytes(),
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
        data: _fakeJpegBytes(),
        mode: ThumbnailCacheMode.inContainer,
        quality: ThumbnailQuality.defaultQuality,
      ),
      completes,
    );
    expect(fake.finishWriteCalls, contains('cryfs'));
  });
}
