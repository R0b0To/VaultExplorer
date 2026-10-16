import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/image_preview_exception.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';

class _FakeFileIoApi extends VaultFileIoApi {
  final Uint8List bytes;
  int sizeRequests = 0;
  int readRequests = 0;

  _FakeFileIoApi(this.bytes) : super(const MethodChannel('test'));

  @override
  Future<int> getMediaFileSize(
    MountedContainer container,
    String fileName,
  ) async {
    sizeRequests++;
    return bytes.length;
  }

  @override
  Future<Uint8List?> readMediaFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    int length,
  ) async {
    readRequests++;
    return bytes;
  }
}

/// A 100 MB image whose native preview is always refused for [reason].
class _RefusingFileIoApi extends VaultFileIoApi {
  final ImagePreviewUnavailableReason reason;
  int previewRequests = 0;

  _RefusingFileIoApi(this.reason) : super(const MethodChannel('test'));

  @override
  Future<int> getMediaFileSize(
    MountedContainer container,
    String fileName,
  ) async => 100 * 1024 * 1024;

  @override
  Future<Uint8List?> getImageThumbnailOrThrow(
    MountedContainer container,
    String fileName, {
    int targetSize = 180,
    int quality = 70,
    bool preserveAlpha = false,
  }) async {
    previewRequests++;
    throw ImagePreviewUnavailableException(reason);
  }
}

/// Minimal PNG prefix (signature + IHDR) declaring [width] x [height]; the
/// file itself is tiny, which is exactly the shape of the crash: a few dozen
/// bytes on disk, gigabytes once a codec expands it.
Uint8List _pngHeader(int width, int height) {
  final b = BytesBuilder();
  b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  b.add([0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  b.add([
    (width >> 24) & 0xFF, (width >> 16) & 0xFF, (width >> 8) & 0xFF, width & 0xFF,
    (height >> 24) & 0xFF, (height >> 16) & 0xFF, (height >> 8) & 0xFF, height & 0xFF,
  ]);
  b.add([8, 6, 0, 0, 0, 0, 0, 0, 0]);
  return b.toBytes();
}

/// A file far below the 8 MB inline limit whose header declares [bytes]'s
/// pixel size. Records whether the raw bytes were ever handed out (i.e. would
/// have been decoded by Flutter) versus the guarded native preview.
class _SmallFileApi extends VaultFileIoApi {
  final Uint8List bytes;
  final ImagePreviewUnavailableReason? refuseWith;
  int rawReads = 0;
  int previewRequests = 0;

  _SmallFileApi(this.bytes, {this.refuseWith})
    : super(const MethodChannel('test'));

  @override
  Future<int> getMediaFileSize(MountedContainer container, String fileName) async =>
      bytes.length;

  @override
  Future<Uint8List?> readMediaFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    int length,
  ) async {
    rawReads++;
    return bytes;
  }

  @override
  Future<Uint8List?> getImageThumbnailOrThrow(
    MountedContainer container,
    String fileName, {
    int targetSize = 180,
    int quality = 70,
    bool preserveAlpha = false,
  }) async {
    previewRequests++;
    if (refuseWith != null) throw ImagePreviewUnavailableException(refuseWith!);
    return Uint8List.fromList([9, 9, 9]);
  }
}

/// Holds the first getMediaFileSize call until [firstSizeGate] completes, so a
/// test can change the world while the first fetch is mid-flight.
class _GatedSizeApi extends _FakeFileIoApi {
  final Completer<void> firstSizeGate = Completer<void>();

  _GatedSizeApi(super.bytes);

  @override
  Future<int> getMediaFileSize(
    MountedContainer container,
    String fileName,
  ) async {
    final first = sizeRequests == 0;
    sizeRequests++;
    if (first) await firstSizeGate.future;
    return bytes.length;
  }
}

final _container = MountedContainer(
  uri: 'test-vault',
  displayName: 'Test vault',
  volId: 1,
  rootFiles: [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000,
  freeSpace: 500,
);

void main() {
  setUp(FullResImageCache.clear);
  tearDown(FullResImageCache.clear);

  test(
    'fetches through the injected file I/O API and caches the result',
    () async {
      final fileIoApi = _FakeFileIoApi(Uint8List.fromList([1, 2, 3]));

      final first = await FullResImageCache.fetch(
        fileIoApi: fileIoApi,
        container: _container,
        filePath: 'photo.jpg',
        completer: Completer<void>(),
        isStillWanted: () => true,
      );
      final second = await FullResImageCache.fetch(
        fileIoApi: fileIoApi,
        container: _container,
        filePath: 'photo.jpg',
        completer: Completer<void>(),
        isStillWanted: () => true,
      );

      expect(first, Uint8List.fromList([1, 2, 3]));
      expect(second, Uint8List.fromList([1, 2, 3]));
      expect(fileIoApi.sizeRequests, 1);
      expect(fileIoApi.readRequests, 1);
    },
  );

  test(
    'a too-large image is refused once, not retried, and remembered',
    () async {
      final fileIoApi = _RefusingFileIoApi(
        ImagePreviewUnavailableReason.tooLarge,
      );
      Future<Uint8List?> fetch() => FullResImageCache.fetch(
        fileIoApi: fileIoApi,
        container: _container,
        filePath: 'huge.jpg',
        completer: Completer<void>(),
        isStillWanted: () => true,
      );

      await expectLater(
        fetch(),
        throwsA(isA<ImagePreviewUnavailableException>()),
      );
      expect(fileIoApi.previewRequests, 1);
      expect(FullResImageCache.isKnownTooLarge(_container, 'huge.jpg'), isTrue);

      // Fails fast: no second native decode attempt.
      await expectLater(
        fetch(),
        throwsA(isA<ImagePreviewUnavailableException>()),
      );
      expect(fileIoApi.previewRequests, 1);

      FullResImageCache.clear();
      expect(FullResImageCache.isKnownTooLarge(_container, 'huge.jpg'), isFalse);
    },
  );

  test('an out-of-memory refusal is not remembered, so it can be retried', () async {
    final fileIoApi = _RefusingFileIoApi(
      ImagePreviewUnavailableReason.outOfMemory,
    );
    Future<Uint8List?> fetch() => FullResImageCache.fetch(
      fileIoApi: fileIoApi,
      container: _container,
      filePath: 'huge.jpg',
      completer: Completer<void>(),
      isStillWanted: () => true,
    );

    await expectLater(fetch(), throwsA(isA<ImagePreviewUnavailableException>()));
    expect(FullResImageCache.isKnownTooLarge(_container, 'huge.jpg'), isFalse);

    await expectLater(fetch(), throwsA(isA<ImagePreviewUnavailableException>()));
    // One native attempt per fetch -- never the 3x backoff retry.
    expect(fileIoApi.previewRequests, 2);
  });

  test(
    'a tiny file declaring 857 MP is never decoded inline: refused natively, remembered',
    () async {
      // 47770 x 17949 is the image from the LMK crash report.
      final api = _SmallFileApi(
        _pngHeader(47770, 17949),
        refuseWith: ImagePreviewUnavailableReason.tooLarge,
      );
      Future<Uint8List?> fetch() => FullResImageCache.fetch(
        fileIoApi: api,
        container: _container,
        filePath: 'bomb.png',
        completer: Completer<void>(),
        isStillWanted: () => true,
      );

      await expectLater(fetch(), throwsA(isA<ImagePreviewUnavailableException>()));
      expect(api.previewRequests, 1);
      expect(FullResImageCache.isKnownTooLarge(_container, 'bomb.png'), isTrue);
      // The raw bytes must never be cached, or the widget would hand them
      // to Flutter's codec on the next build.
      expect(FullResImageCache.get(_container, 'bomb.png'), isNull);
    },
  );

  test(
    'a small file declaring many megapixels gets the bounded native preview, not raw bytes',
    () async {
      // 10000 x 8000 = 80 MP: below the native 512 MP refusal, above the
      // inline budget.
      final api = _SmallFileApi(_pngHeader(10000, 8000));
      final out = await FullResImageCache.fetch(
        fileIoApi: api,
        container: _container,
        filePath: 'big.png',
        completer: Completer<void>(),
        isStillWanted: () => true,
      );

      expect(out, Uint8List.fromList([9, 9, 9]));
      expect(api.previewRequests, 1);
      expect(FullResImageCache.isLargeImagePreview(_container, 'big.png'), isTrue);
      // Preview bytes live in the separate preview cache, never as "original".
      expect(FullResImageCache.get(_container, 'big.png'), isNull);
    },
  );

  test('an ordinary small image is still served inline from its raw bytes', () async {
    final bytes = _pngHeader(1920, 1080); // ~2 MP
    final api = _SmallFileApi(bytes);
    final out = await FullResImageCache.fetch(
      fileIoApi: api,
      container: _container,
      filePath: 'normal.png',
      completer: Completer<void>(),
      isStillWanted: () => true,
    );

    expect(out, bytes);
    expect(api.previewRequests, 0);
    expect(FullResImageCache.get(_container, 'normal.png'), bytes);
  });

  test(
    'a request that joined an in-flight fetch still gets the image when the '
    "fetch's original caller goes stale",
    () async {
      final bytes = Uint8List.fromList(List<int>.filled(32, 7));
      final api = _GatedSizeApi(bytes);
      var ownerWanted = true;

      final owner = FullResImageCache.fetch(
        fileIoApi: api,
        container: _container,
        filePath: 'joined.png',
        completer: Completer<void>(),
        isStillWanted: () => ownerWanted,
      );
      await Future<void>.delayed(Duration.zero); // owner is now mid-flight
      final joiner = FullResImageCache.fetch(
        fileIoApi: api,
        container: _container,
        filePath: 'joined.png',
        completer: Completer<void>(),
        isStillWanted: () => true,
      );

      // The owner's widget is disposed / scrolled away while the file size
      // is still being read.
      ownerWanted = false;
      api.firstSizeGate.complete();

      expect(await owner, isNull);
      expect(
        await joiner,
        bytes,
        reason:
            'before the fix the joiner inherited the stale owner\'s null and '
            'the viewer showed "Failed to load encrypted image"',
      );
    },
  );

  test(
    'a fetch cancelled while queued does not fail a request that joined it',
    () async {
      final bytes = Uint8List.fromList(List<int>.filled(32, 9));
      final api = _FakeFileIoApi(bytes);
      final hold1 = Completer<void>();
      final hold2 = Completer<void>();
      var hold1Released = false;
      // Occupy both turns so the owner has to wait in the queue.
      await FullResImageCache.limiter.acquire(hold1);
      await FullResImageCache.limiter.acquire(hold2);
      try {
        final ownerTicket = Completer<void>();
        final owner = FullResImageCache.fetch(
          fileIoApi: api,
          container: _container,
          filePath: 'queued.png',
          completer: ownerTicket,
          isStillWanted: () => true,
        );
        final joiner = FullResImageCache.fetch(
          fileIoApi: api,
          container: _container,
          filePath: 'queued.png',
          completer: Completer<void>(),
          isStillWanted: () => true,
        );

        // The owner's widget is disposed while it still waits for a turn.
        FullResImageCache.limiter.cancel(ownerTicket);
        expect(await owner, isNull);

        FullResImageCache.limiter.release(hold1);
        hold1Released = true;
        expect(await joiner, bytes);
      } finally {
        if (!hold1Released) FullResImageCache.limiter.release(hold1);
        FullResImageCache.limiter.release(hold2);
      }
    },
  );
}
