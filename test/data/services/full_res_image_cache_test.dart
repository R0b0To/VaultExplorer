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
}
