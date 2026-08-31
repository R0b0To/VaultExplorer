import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

class _FakeFileIoApi extends VaultFileIoApi {
  _FakeFileIoApi() : super(const MethodChannel('test/thumbnail-cache'));

  final List<String> writtenPaths = [];
  bool writeWholeFileResult = true;

  @override
  Future<bool> createDirectory(
    MountedContainer container,
    String dirPath,
  ) async => true;

  @override
  Future<bool> writeWholeFile(
    MountedContainer container,
    String fileName,
    Uint8List bytes,
  ) async {
    writtenPaths.add(fileName);
    return writeWholeFileResult;
  }
}

class _FakeHashApi extends VaultHashApi {
  _FakeHashApi() : super(const MethodChannel('test/thumbnail-cache'));

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
Uint8List _fakeJpegBytes() =>
    Uint8List.fromList([0xFF, 0xD8, 0x00, 0xFF, 0xD9]);

void main() {
  late _FakeFileIoApi fileIoApi;

  setUp(() {
    fileIoApi = _FakeFileIoApi();
    ThumbnailCacheService.configure(
      fileIoApi: fileIoApi,
      cryptoApi: VaultCryptoApi(const MethodChannel('test/thumbnail-cache')),
      hashApi: _FakeHashApi(),
    );
  });

  for (final format in ['cryptomator', 'gocryptfs', 'cryfs']) {
    test(
      'put() commits the in-container write for $format containers',
      () async {
        await ThumbnailCacheService.put(
          container: _container(format, 'content://$format-vault'),
          filePath: '/pictures/photo.jpg',
          data: _fakeJpegBytes(),
          mode: ThumbnailCacheMode.inContainer,
          quality: ThumbnailQuality.defaultQuality,
        );

        expect(
          fileIoApi.writtenPaths,
          hasLength(1),
          reason:
              'the typed file I/O API should receive every in-container '
              'thumbnail write, including $format',
        );
      },
    );
  }

  test(
    'put() delegates in-container writes to the typed whole-file API',
    () async {
      await ThumbnailCacheService.put(
        container: _container('gocryptfs', 'content://atomic-write'),
        filePath: '/pictures/photo.jpg',
        data: _fakeJpegBytes(),
        mode: ThumbnailCacheMode.inContainer,
        quality: ThumbnailQuality.defaultQuality,
      );

      expect(fileIoApi.writtenPaths, hasLength(1));
    },
  );

  test(
    'put() rejects data that is not a well-formed JPEG and never touches the vault API',
    () async {
      await ThumbnailCacheService.put(
        container: _container('gocryptfs', 'content://malformed'),
        filePath: '/pictures/photo.jpg',
        data: Uint8List.fromList([1, 2, 3]), // no SOI/EOI markers
        mode: ThumbnailCacheMode.inContainer,
        quality: ThumbnailQuality.defaultQuality,
      );

      expect(fileIoApi.writtenPaths, isEmpty);
    },
  );

  test(
    'two concurrent put() calls for the same target coalesce into a single write',
    () async {
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
        fileIoApi.writtenPaths,
        hasLength(1),
        reason:
            'two concurrent put() calls for the identical target should '
            'only perform one actual write',
      );
    },
  );

  test('put() swallows a typed whole-file write failure', () async {
    fileIoApi.writeWholeFileResult = false;

    await ThumbnailCacheService.put(
      container: _container('gocryptfs', 'content://write-fails'),
      filePath: '/pictures/photo.jpg',
      data: _fakeJpegBytes(),
      mode: ThumbnailCacheMode.inContainer,
      quality: ThumbnailQuality.defaultQuality,
    );

    expect(fileIoApi.writtenPaths, hasLength(1));
  });

  test('put() completes without throwing when the typed write fails', () async {
    fileIoApi.writeWholeFileResult = false;

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
    expect(fileIoApi.writtenPaths, hasLength(1));
  });
}
