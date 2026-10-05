import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

/// In-memory stand-in for a container's file system, with switches to inject
/// the failures the pack cache has to survive. The real pack/index code runs
/// against it end to end.
class _FakeFileIoApi extends VaultFileIoApi {
  _FakeFileIoApi() : super(const MethodChannel('test/thumbnail-cache'));

  /// path -> bytes for everything currently "in the container".
  final Map<String, Uint8List> files = {};

  /// Every writeWholeFile attempt, successful or not.
  final List<String> writtenPaths = [];

  /// Every readFileChunk path.
  final List<String> chunkReadPaths = [];

  /// Global switch: every writeWholeFile fails.
  bool writeWholeFileResult = true;

  /// Fails just the writes whose path matches.
  bool Function(String path)? failWriteWhere;

  /// index.bin exists but can't be read (a transient failure).
  bool failIndexRead = false;

  /// Directory listings throw.
  bool failListing = false;

  /// While set, writeWholeFile blocks until it completes.
  Completer<void>? writeGate;

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
    final gate = writeGate;
    if (gate != null) await gate.future;
    if (!writeWholeFileResult) return false;
    if (failWriteWhere?.call(fileName) ?? false) return false;
    files[fileName] = Uint8List.fromList(bytes);
    return true;
  }

  @override
  Future<Uint8List?> readWholeFile(
    MountedContainer container,
    String fileName,
  ) async {
    if (failIndexRead && fileName.endsWith('index.bin')) return null;
    final bytes = files[fileName];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> readFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    int length,
  ) async {
    chunkReadPaths.add(fileName);
    final bytes = files[fileName];
    if (bytes == null || offset >= bytes.length) return null;
    final end = offset + length > bytes.length ? bytes.length : offset + length;
    return Uint8List.fromList(bytes.sublist(offset, end));
  }

  @override
  Future<bool> deleteFile(MountedContainer container, String fileName) async =>
      files.remove(fileName) != null;

  @override
  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async {
    if (failListing) throw StateError('listing failed');
    final prefix = '$dirPath/';
    final out = <String>[];
    files.forEach((path, bytes) {
      if (!path.startsWith(prefix)) return;
      final name = path.substring(prefix.length);
      if (name.contains('/')) return;
      out.add('F|${bytes.length}|0|$name');
    });
    return out;
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

MountedContainer _container(
  String format,
  String uri, {
  DateTime? mountedAt,
}) => MountedContainer(
  uri: uri,
  displayName: 'test',
  volId: uri.hashCode,
  rootFiles: const [],
  mountedAt: mountedAt ?? DateTime.now(),
  totalSpace: 0,
  freeSpace: 0,
  containerFormat: format,
);

/// Minimal bytes that satisfy ThumbnailCacheService's cheap structural
/// JPEG check (SOI 0xFFD8 .. EOI 0xFFD9) without being a real decodable
/// image -- these tests are about the write/commit path, not decoding.
Uint8List _fakeJpegBytes() =>
    Uint8List.fromList([0xFF, 0xD8, 0x00, 0xFF, 0xD9]);

/// Same structure, but with a distinguishing byte so a test can tell which
/// thumbnail it got back.
Uint8List _thumb(int n) => Uint8List.fromList([0xFF, 0xD8, n, n, 0xFF, 0xD9]);

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
    ThumbnailCacheService.resetInContainerStateForTesting();
    ThumbnailCacheService.inContainerDebounceDuration = const Duration(milliseconds: 20);
    ThumbnailCacheService.configure(
      fileIoApi: fileIoApi,
      cryptoApi: VaultCryptoApi(const MethodChannel('test/thumbnail-cache')),
      hashApi: _FakeHashApi(),
    );
  });

  // ── Shared helpers for the pack-cache tests ─────────────────────────

  /// Lets every pending microtask and zero-delay timer run, so queued puts
  /// have reached the pack queue before the test pokes at it.
  Future<void> settleQueue() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  const indexPath = '.thumbcache/index.bin';
  final packRe = RegExp(r'^\.thumbcache/pack_\d+\.bin$');

  List<String> packNames() =>
      (fileIoApi.files.keys.where(packRe.hasMatch).toList()..sort());

  Future<void> putThumb(
    MountedContainer container,
    String filePath,
    Uint8List data, {
    int? width,
    int? height,
  }) => ThumbnailCacheService.put(
    container: container,
    filePath: filePath,
    data: data,
    mode: ThumbnailCacheMode.inContainer,
    quality: ThumbnailQuality.defaultQuality,
    width: width,
    height: height,
  );

  Future<(Uint8List, int?, int?)?> getThumb(
    MountedContainer container,
    String filePath,
  ) => ThumbnailCacheService.getWithSize(
    container: container,
    filePath: filePath,
    mode: ThumbnailCacheMode.inContainer,
    quality: ThumbnailQuality.defaultQuality,
  );

  Future<Uint8List?> readThumb(MountedContainer c, String filePath) async =>
      (await getThumb(c, filePath))?.$1;

  /// Locks [c] (drops the memory tier and this mount's pack state) and hands
  /// back a fresh mount of the same container, so the next read must come
  /// from disk.
  Future<MountedContainer> remount(MountedContainer c) async {
    await ThumbnailCacheService.clearAppCacheFor(c);
    return _container(
      'gocryptfs',
      c.uri,
      mountedAt: c.mountedAt.add(const Duration(seconds: 5)),
    );
  }

  String keyHexFromFirstIndexEntry(Uint8List index) => index
      .sublist(16, 32)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  Uint8List tpk3Header({required int nextPackId, int count = 0}) {
    final bytes = Uint8List(16);
    final bd = ByteData.sublistView(bytes);
    bytes.setRange(0, 4, 'TPK3'.codeUnits);
    bd.setUint16(4, 3);
    bd.setUint32(8, nextPackId);
    bd.setUint32(12, count);
    return bytes;
  }

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
          packNames(),
          hasLength(1),
          reason: 'the thumbnail lands in a pack for $format containers too',
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

      expect(fileIoApi.writtenPaths, isNotEmpty);
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
        fileIoApi.writtenPaths.where(packRe.hasMatch),
        hasLength(1),
        reason:
            'two concurrent put() calls for the identical target should '
            'only perform one actual pack write',
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

    expect(fileIoApi.writtenPaths, isNotEmpty);
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
    expect(fileIoApi.writtenPaths, isNotEmpty);
  });

  // ── Pack cache behaviour ────────────────────────────────────────────

  test('thumbnails are batched into one pack plus an index, not one file each', () async {
    final c = _container('gocryptfs', 'content://pack-batch');
    await Future.wait([
      for (var i = 0; i < 10; i++) putThumb(c, '/pics/p$i.jpg', _thumb(i)),
    ]);

    expect(packNames(), hasLength(1));
    expect(fileIoApi.files.keys.toSet(), {packNames().single, indexPath});
  });

  test('a stored thumbnail is readable after the vault is re-mounted', () async {
    final first = _container('gocryptfs', 'content://pack-roundtrip');
    await putThumb(first, '/pics/a.jpg', _thumb(1), width: 120, height: 90);

    final second = await remount(first);
    final got = await getThumb(second, '/pics/a.jpg');

    expect(got, isNotNull);
    expect(got!.$1, equals(_thumb(1)));
    expect(got.$2, 120);
    expect(got.$3, 90);
  });

  test('later flushes add packs and keep earlier thumbnails', () async {
    final first = _container('gocryptfs', 'content://pack-two-flushes');
    await putThumb(first, '/pics/a.jpg', _thumb(1));
    await putThumb(first, '/pics/b.jpg', _thumb(2));
    expect(packNames(), hasLength(2));

    final second = await remount(first);
    expect(await readThumb(second, '/pics/a.jpg'), equals(_thumb(1)));
    expect(await readThumb(second, '/pics/b.jpg'), equals(_thumb(2)));
  });

  test('a failed pack write leaves the index and earlier thumbnails untouched', () async {
    final first = _container('gocryptfs', 'content://pack-write-fails');
    await putThumb(first, '/pics/a.jpg', _thumb(1));
    final indexBefore = Uint8List.fromList(fileIoApi.files[indexPath]!);

    fileIoApi.failWriteWhere = packRe.hasMatch;
    await putThumb(first, '/pics/b.jpg', _thumb(2));
    fileIoApi.failWriteWhere = null;

    expect(fileIoApi.files[indexPath], equals(indexBefore));
    expect(packNames(), hasLength(1));

    final second = await remount(first);
    expect(await readThumb(second, '/pics/a.jpg'), equals(_thumb(1)));
    expect(await readThumb(second, '/pics/b.jpg'), isNull);
  });

  test('a failed index write drops its pack and keeps the old index', () async {
    final first = _container('gocryptfs', 'content://index-write-fails');
    await putThumb(first, '/pics/a.jpg', _thumb(1));
    final indexBefore = Uint8List.fromList(fileIoApi.files[indexPath]!);

    fileIoApi.failWriteWhere = (p) => p == indexPath;
    await putThumb(first, '/pics/b.jpg', _thumb(2));
    fileIoApi.failWriteWhere = null;

    expect(fileIoApi.files[indexPath], equals(indexBefore));
    expect(packNames(), hasLength(1), reason: 'the unreferenced pack is removed');

    final second = await remount(first);
    expect(await readThumb(second, '/pics/a.jpg'), equals(_thumb(1)));
    expect(await readThumb(second, '/pics/b.jpg'), isNull);
  });

  test('an unreadable index is never overwritten', () async {
    final first = _container('gocryptfs', 'content://index-unreadable');
    await putThumb(first, '/pics/a.jpg', _thumb(1));
    final indexBefore = Uint8List.fromList(fileIoApi.files[indexPath]!);

    final second = await remount(first);
    fileIoApi.failIndexRead = true;
    final writesBefore = fileIoApi.writtenPaths.length;

    expect(await readThumb(second, '/pics/a.jpg'), isNull);
    await putThumb(second, '/pics/b.jpg', _thumb(2));

    expect(fileIoApi.writtenPaths.skip(writesBefore), isEmpty);
    expect(fileIoApi.files[indexPath], equals(indexBefore));

    fileIoApi.failIndexRead = false;
    final third = await remount(second);
    expect(await readThumb(third, '/pics/a.jpg'), equals(_thumb(1)));
  });

  test('a failed directory listing is not treated as an empty cache', () async {
    final first = _container('gocryptfs', 'content://listing-fails');
    await putThumb(first, '/pics/a.jpg', _thumb(1));
    final indexBefore = Uint8List.fromList(fileIoApi.files[indexPath]!);

    final second = await remount(first);
    fileIoApi.failListing = true;
    await putThumb(second, '/pics/b.jpg', _thumb(2));
    fileIoApi.failListing = false;

    expect(fileIoApi.files[indexPath], equals(indexBefore));
    final third = await remount(second);
    expect(await readThumb(third, '/pics/a.jpg'), equals(_thumb(1)));
  });

  test('packs with no index are skipped over, not overwritten', () async {
    fileIoApi.files['.thumbcache/pack_0007.bin'] = Uint8List(40);
    final c = _container('gocryptfs', 'content://orphan-packs');
    await putThumb(c, '/pics/a.jpg', _thumb(1));

    expect(packNames(), contains('.thumbcache/pack_0008.bin'));
    expect(fileIoApi.files.containsKey('.thumbcache/pack_0007.bin'), isTrue);
  });

  test('a corrupt index is replaced and the packs it described are deleted', () async {
    fileIoApi.files[indexPath] = Uint8List.fromList(List.filled(40, 0x58));
    fileIoApi.files['.thumbcache/pack_0003.bin'] = Uint8List(40);
    final c = _container('gocryptfs', 'content://corrupt-index');
    await putThumb(c, '/pics/a.jpg', _thumb(1));

    expect(fileIoApi.files.containsKey('.thumbcache/pack_0003.bin'), isFalse);
    expect(packNames(), ['.thumbcache/pack_0004.bin']);
    expect(String.fromCharCodes(fileIoApi.files[indexPath]!.sublist(0, 4)), 'TPK3');
  });

  test('an index written by the previous build (16-bit pack ids) still loads', () async {
    final first = _container('gocryptfs', 'content://tpk2-compat');
    await putThumb(first, '/pics/a.jpg', _thumb(1), width: 64, height: 48);
    final v3 = fileIoApi.files[indexPath]!;
    final bd3 = ByteData.sublistView(v3);

    // Re-encode that single entry in the old TPK2 layout.
    final v2 = Uint8List(16 + 32);
    final bd2 = ByteData.sublistView(v2);
    v2.setRange(0, 4, 'TPK2'.codeUnits);
    bd2.setUint16(4, 2);
    bd2.setUint16(6, bd3.getUint32(8));
    bd2.setUint32(12, 1);
    v2.setRange(16, 32, v3.sublist(16, 32));
    bd2.setUint16(32, bd3.getUint32(32));
    bd2.setUint32(34, bd3.getUint32(36));
    bd2.setUint32(38, bd3.getUint32(40));
    bd2.setUint16(42, bd3.getUint16(44));
    bd2.setUint16(44, bd3.getUint16(46));
    fileIoApi.files[indexPath] = v2;

    final second = await remount(first);
    final got = await getThumb(second, '/pics/a.jpg');
    expect(got?.$1, equals(_thumb(1)));
    expect(got?.$2, 64);
    expect(got?.$3, 48);
  });

  test('pack ids beyond 16 bits round-trip through the index', () async {
    fileIoApi.files[indexPath] = tpk3Header(nextPackId: 70000);
    final first = _container('gocryptfs', 'content://big-pack-ids');
    await putThumb(first, '/pics/a.jpg', _thumb(1));

    expect(packNames(), ['.thumbcache/pack_70000.bin']);
    final second = await remount(first);
    expect(await readThumb(second, '/pics/a.jpg'), equals(_thumb(1)));
  });

  test('invalidate() removes a stored thumbnail even before the index was loaded', () async {
    final first = _container('gocryptfs', 'content://invalidate-stored');
    await putThumb(first, '/pics/a.jpg', _thumb(1));
    await putThumb(first, '/pics/b.jpg', _thumb(2));

    // A fresh mount: nothing is loaded yet when the file is edited.
    final second = await remount(first);
    await ThumbnailCacheService.invalidateFile(second, '/pics/a.jpg');

    final third = await remount(second);
    expect(await readThumb(third, '/pics/a.jpg'), isNull);
    expect(await readThumb(third, '/pics/b.jpg'), equals(_thumb(2)));
  });

  test('invalidate() drops a thumbnail that is still queued for a pack', () async {
    ThumbnailCacheService.inContainerDebounceDuration = const Duration(seconds: 30);
    final c = _container('gocryptfs', 'content://invalidate-queued');
    final queuedPut = putThumb(c, '/pics/a.jpg', _thumb(1));
    await settleQueue();

    await ThumbnailCacheService.invalidateFile(c, '/pics/a.jpg');
    await ThumbnailCacheService.flushInContainerCache(c);
    await queuedPut;

    expect(packNames(), isEmpty);
    final second = await remount(c);
    expect(await readThumb(second, '/pics/a.jpg'), isNull);
  });

  test('invalidate() while the index is unreadable is applied once it can be read', () async {
    final first = _container('gocryptfs', 'content://invalidate-deferred');
    await putThumb(first, '/pics/a.jpg', _thumb(1));

    final second = await remount(first);
    fileIoApi.failIndexRead = true;
    await ThumbnailCacheService.invalidateFile(second, '/pics/a.jpg');
    fileIoApi.failIndexRead = false;

    expect(await readThumb(second, '/pics/a.jpg'), isNull);
    final third = await remount(second);
    expect(await readThumb(third, '/pics/a.jpg'), isNull);
  });

  test('a miss does not probe for a loose legacy file when none exist', () async {
    final c = _container('gocryptfs', 'content://no-legacy');
    expect(await readThumb(c, '/pics/none.jpg'), isNull);
    expect(
      fileIoApi.chunkReadPaths.where((p) => !p.contains('/pack_')),
      isEmpty,
    );
  });

  test('a legacy loose thumbnail is served, then moved into a pack', () async {
    final donor = _container('gocryptfs', 'content://legacy-donor');
    await putThumb(donor, '/pics/old.jpg', _thumb(7));
    final keyHex = keyHexFromFirstIndexEntry(fileIoApi.files[indexPath]!);

    fileIoApi.files
      ..clear()
      ..['.thumbcache/$keyHex'] = _thumb(7);

    final c = _container('gocryptfs', 'content://legacy-victim');
    expect(await readThumb(c, '/pics/old.jpg'), equals(_thumb(7)));
    await ThumbnailCacheService.flushInContainerCache(c);

    expect(fileIoApi.files.containsKey('.thumbcache/$keyHex'), isFalse);
    expect(packNames(), hasLength(1));
  });

  test('eviction removes packs oldest-first by number, not by name', () async {
    for (final id in ['9998', '9999', '10000']) {
      fileIoApi.files['.thumbcache/pack_$id.bin'] = Uint8List(40);
    }
    final c = _container('gocryptfs', 'content://evict-order');
    await ThumbnailCacheService.enforceInContainerDiskBudget(c, 100);

    expect(fileIoApi.files.containsKey('.thumbcache/pack_9998.bin'), isFalse);
    expect(fileIoApi.files.containsKey('.thumbcache/pack_9999.bin'), isTrue);
    expect(fileIoApi.files.containsKey('.thumbcache/pack_10000.bin'), isTrue);
  });

  test('eviction clears leftover loose files before it touches any pack', () async {
    final c = _container('gocryptfs', 'content://evict-loose-first');
    await putThumb(c, '/pics/a.jpg', _thumb(1));
    fileIoApi.files['.thumbcache/${'a' * 32}'] = Uint8List(200);
    fileIoApi.files['.thumbcache/${'b' * 32}'] = Uint8List(200);

    await ThumbnailCacheService.enforceInContainerDiskBudget(c, 300);

    expect(fileIoApi.files.containsKey('.thumbcache/${'a' * 32}'), isFalse);
    expect(fileIoApi.files.containsKey('.thumbcache/${'b' * 32}'), isFalse);
    final second = await remount(c);
    expect(await readThumb(second, '/pics/a.jpg'), equals(_thumb(1)));
  });

  test('flushing waits for a flush that is already running', () async {
    final c = _container('gocryptfs', 'content://flush-waits');
    fileIoApi.writeGate = Completer<void>();
    final gate = fileIoApi.writeGate!;

    final putA = putThumb(c, '/pics/a.jpg', _thumb(1));
    await settleQueue();
    final first = ThumbnailCacheService.flushInContainerCache(c);
    await settleQueue();
    final putB = putThumb(c, '/pics/b.jpg', _thumb(2));
    await settleQueue();

    var secondDone = false;
    final second = ThumbnailCacheService.flushInContainerCache(c)
        .then((_) => secondDone = true);
    await settleQueue();
    expect(secondDone, isFalse, reason: 'must not return while a flush is mid-write');

    fileIoApi.writeGate = null;
    gate.complete();
    await Future.wait([first, second, putA, putB]);

    final again = await remount(c);
    expect(await readThumb(again, '/pics/a.jpg'), equals(_thumb(1)));
    expect(await readThumb(again, '/pics/b.jpg'), equals(_thumb(2)));
  });

  test('flushing by URI (used right before a lock) writes without waiting for the debounce', () async {
    ThumbnailCacheService.inContainerDebounceDuration = const Duration(seconds: 30);
    final c = _container('gocryptfs', 'content://flush-by-uri');
    final queuedPut = putThumb(c, '/pics/a.jpg', _thumb(1));
    await settleQueue();
    expect(packNames(), isEmpty);

    await ThumbnailCacheService.flushInContainerCacheForUri(c.uri);
    expect(packNames(), hasLength(1));
    await queuedPut;
  });

  test('repeated write failures pause writing instead of hammering the volume', () async {
    fileIoApi.writeWholeFileResult = false;
    final c = _container('gocryptfs', 'content://repeated-failures');
    for (var i = 0; i < 3; i++) {
      await putThumb(c, '/pics/f$i.jpg', _thumb(i));
    }
    final attempts = fileIoApi.writtenPaths.length;

    await putThumb(c, '/pics/after.jpg', _thumb(9));
    expect(fileIoApi.writtenPaths.length, attempts);
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

    expect(fileIoApi.writtenPaths, isNotEmpty);
  });

  test('put() accepts a WebP payload', () async {
    await ThumbnailCacheService.put(
      container: _container('gocryptfs', 'content://webp-icon'),
      filePath: '/apps/example.apk',
      data: _fakeWebpBytes(),
      mode: ThumbnailCacheMode.inContainer,
      quality: ThumbnailQuality.defaultQuality,
    );

    expect(fileIoApi.writtenPaths, isNotEmpty);
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
