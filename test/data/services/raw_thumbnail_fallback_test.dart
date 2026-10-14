import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/image_preview_exception.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/raw_thumbnail_fallback.dart';

/// Minimal PNG prefix (signature + IHDR) declaring [width] x [height].
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

class _FakeFileIoApi extends VaultFileIoApi {
  final int reportedSize;
  final Uint8List bytes;
  int reads = 0;

  _FakeFileIoApi({required this.reportedSize, required this.bytes})
    : super(const MethodChannel('test'));

  @override
  Future<int> getFileSize(MountedContainer container, String fileName) async =>
      reportedSize;

  @override
  Future<Uint8List?> readFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    int length,
  ) async {
    reads++;
    return bytes;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('readRawThumbnailFallback', () {
    test('returns the raw bytes of an ordinary small image', () async {
      final bytes = _pngHeader(1920, 1080);
      final api = _FakeFileIoApi(reportedSize: bytes.length, bytes: bytes);

      final out = await readRawThumbnailFallback(api, _container, 'a.png');

      expect(out, bytes);
    });

    test('refuses a tiny file that declares 857 MP (the LMK-crash image)', () async {
      final bytes = _pngHeader(47770, 17949);
      final api = _FakeFileIoApi(reportedSize: bytes.length, bytes: bytes);

      await expectLater(
        readRawThumbnailFallback(api, _container, 'bomb.png'),
        throwsA(
          isA<ImagePreviewUnavailableException>().having(
            (e) => e.reason,
            'reason',
            ImagePreviewUnavailableReason.tooLarge,
          ),
        ),
      );
    });

    test('a large file is never read into memory at all', () async {
      final api = _FakeFileIoApi(
        reportedSize: 200 * 1024 * 1024,
        bytes: Uint8List(0),
      );

      await expectLater(
        readRawThumbnailFallback(api, _container, 'huge.png'),
        throwsA(isA<ImagePreviewUnavailableException>()),
      );
      expect(api.reads, 0);
    });
  });

  group('getImageThumbnailWithSizeOrThrow', () {
    const channel = MethodChannel('raw_thumbnail_fallback_test');
    final api = const VaultFileIoApi(channel);
    late Object Function() respond;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => respond());
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('maps IMAGE_TOO_LARGE and OUT_OF_MEMORY to typed exceptions', () async {
      respond = () => throw PlatformException(code: 'IMAGE_TOO_LARGE');
      await expectLater(
        api.getImageThumbnailWithSizeOrThrow(_container, 'x.png'),
        throwsA(
          isA<ImagePreviewUnavailableException>().having(
            (e) => e.reason,
            'reason',
            ImagePreviewUnavailableReason.tooLarge,
          ),
        ),
      );

      respond = () => throw PlatformException(code: 'OUT_OF_MEMORY');
      await expectLater(
        api.getImageThumbnailWithSizeOrThrow(_container, 'x.png'),
        throwsA(
          isA<ImagePreviewUnavailableException>().having(
            (e) => e.reason,
            'reason',
            ImagePreviewUnavailableReason.outOfMemory,
          ),
        ),
      );
    });

    test('any other native failure is still just null', () async {
      respond = () => throw PlatformException(code: 'DECODE_FAILED');
      expect(await api.getImageThumbnailWithSizeOrThrow(_container, 'x.png'), isNull);
    });

    test('a successful result is parsed', () async {
      respond = () => {'bytes': Uint8List.fromList([1, 2, 3]), 'width': 40, 'height': 30};
      final out = await api.getImageThumbnailWithSizeOrThrow(_container, 'x.png');
      expect(out?.bytes, Uint8List.fromList([1, 2, 3]));
      expect(out?.width, 40);
      expect(out?.height, 30);
    });
  });
}
