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

/// Same idea for PNG: the 8-byte signature, a plausible IHDR declaring
/// 96x96, and a closing IEND chunk. This is the format APK launcher
/// icons actually arrive in (`handleGetApkIcon` PNG-compresses the
/// rasterised drawable), so it has to survive the same write path a
/// generated JPEG thumbnail does.
Uint8List _fakePngBytes() => Uint8List.fromList([
  137, 80, 78, 71, 13, 10, 26, 10, // signature
  0, 0, 0, 13, 73, 72, 68, 82, // IHDR length + type
  0, 0, 0, 96, // width  = 96
  0, 0, 0, 96, // height = 96
  8, 6, 0, 0, 0, // bit depth, colour type, compression, filter, interlace
  0, 0, 0, 0, // (stand-in for the IHDR CRC)
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130, // IEND
]);

/// A lossless-WebP header (`VP8L`) declaring 96x96, with a RIFF payload
/// length that matches the bytes present. The manual resource-table
/// fallback in apk_icon_support.dart can hand back an icon in this
/// format straight out of the APK.
Uint8List _fakeWebpBytes() {
  final bytes = <int>[
    0x52, 0x49, 0x46, 0x46, // "RIFF"
    0, 0, 0, 0, // payload length, patched below
    0x57, 0x45, 0x42, 0x50, // "WEBP"
    0x56, 0x50, 0x38, 0x4C, // "VP8L"
    0, 0, 0, 10, // chunk length
    0x2F, // lossless signature byte
    // 14 bits of (width - 1) then 14 bits of (height - 1), little-endian:
    // 95 | (95 << 14) == 0x17C05F for a 96x96 icon.
    0x5F, 0xC0, 0x17, 0x00,
    0, 0, 0, 0, 0,
  ];
  final payloadLength = bytes.length - 8;
  bytes[4] = payloadLength & 0xFF;
  bytes[5] = (payloadLength >> 8) & 0xFF;
  bytes[6] = (payloadLength >> 16) & 0xFF;
  bytes[7] = (payloadLength >> 24) & 0xFF;
  return Uint8List.fromList(bytes);
}

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
    'put() rejects data that is not a well-formed image and never touches the vault API',
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

  // ── Non-JPEG payloads (APK launcher icons) ──────────────────────────
  //
  // These used to be dropped by every tier: the structural check was
  // JPEG-only, so an APK icon was never written to disk, never held in
  // memory, and re-extracted from the APK on every single visit to the
  // folder.

  test('put() accepts a PNG payload and writes it like any thumbnail', () async {
    await ThumbnailCacheService.put(
      container: _container('gocryptfs', 'content://png-icon'),
      filePath: '/apps/example.apk',
      data: _fakePngBytes(),
      mode: ThumbnailCacheMode.inContainer,
      quality: ThumbnailQuality.defaultQuality,
    );

    expect(fileIoApi.writtenPaths, hasLength(1));
  });

  test('put() accepts a WebP payload', () async {
    await ThumbnailCacheService.put(
      container: _container('gocryptfs', 'content://webp-icon'),
      filePath: '/apps/example.apk',
      data: _fakeWebpBytes(),
      mode: ThumbnailCacheMode.inContainer,
      quality: ThumbnailQuality.defaultQuality,
    );

    expect(fileIoApi.writtenPaths, hasLength(1));
  });

  test('put() rejects a PNG truncated before its IEND chunk', () async {
    final truncated = Uint8List.fromList(
      _fakePngBytes().sublist(0, _fakePngBytes().length - 6),
    );

    await ThumbnailCacheService.put(
      container: _container('gocryptfs', 'content://png-truncated'),
      filePath: '/apps/example.apk',
      data: truncated,
      mode: ThumbnailCacheMode.inContainer,
      quality: ThumbnailQuality.defaultQuality,
    );

    expect(
      fileIoApi.writtenPaths,
      isEmpty,
      reason: 'a torn PNG should be caught the same way a torn JPEG is',
    );
  });

  test('a PNG icon survives a memory-tier round trip', () {
    final container = _container('gocryptfs', 'content://png-memory');
    final bytes = _fakePngBytes();

    ThumbnailCacheService.putInMemory(
      container,
      '/apps/example.apk',
      bytes,
      ThumbnailQuality.defaultQuality,
    );

    expect(
      ThumbnailCacheService.getFromMemory(
        container,
        '/apps/example.apk',
        ThumbnailQuality.defaultQuality,
      ),
      equals(bytes),
      reason:
          'without this the sync peek always misses and every tile '
          're-extracts its icon from the APK on each rebuild',
    );
  });

  test('a malformed payload is still kept out of the memory tier', () {
    final container = _container('gocryptfs', 'content://garbage-memory');

    ThumbnailCacheService.putInMemory(
      container,
      '/apps/example.apk',
      Uint8List.fromList([1, 2, 3, 4]),
      ThumbnailQuality.defaultQuality,
    );

    expect(
      ThumbnailCacheService.getFromMemory(
        container,
        '/apps/example.apk',
        ThumbnailQuality.defaultQuality,
      ),
      isNull,
    );
  });
}
