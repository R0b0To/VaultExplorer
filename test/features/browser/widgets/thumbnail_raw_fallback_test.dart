import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/image_preview_exception.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/widgets/thumbnail_raw_fallback.dart';

class _FakeFileIoApi extends VaultFileIoApi {
  final int size;
  final Uint8List bytes;
  int chunkReads = 0;

  _FakeFileIoApi({required this.size, required this.bytes})
    : super(const MethodChannel('test'));

  @override
  Future<int> getFileSize(MountedContainer container, String path) async => size;

  @override
  Future<Uint8List?> readFileChunk(
    MountedContainer container,
    String path,
    int offset,
    int length,
  ) async {
    chunkReads++;
    return bytes;
  }
}

/// A PNG header claiming [width] x [height] -- all the dimension parser reads.
Uint8List _pngHeader(int width, int height) {
  final b = ByteData(33);
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    b.setUint8(i, signature[i]);
  }
  b.setUint32(8, 13);
  for (final (i, c) in 'IHDR'.codeUnits.indexed) {
    b.setUint8(12 + i, c);
  }
  b.setUint32(16, width);
  b.setUint32(20, height);
  b.setUint8(24, 8);
  b.setUint8(25, 6);
  return b.buffer.asUint8List();
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
  test('a file over the byte cap is refused without reading it', () async {
    final api = _FakeFileIoApi(
      size: maxRawThumbnailFallbackBytes + 1,
      bytes: Uint8List(1),
    );
    await expectLater(
      readRawThumbnailFallback(api, _container, 'huge.jpg'),
      throwsA(isA<ImagePreviewUnavailableException>()),
    );
    expect(api.chunkReads, 0);
  });

  test('a small file holding hundreds of megapixels is refused', () async {
    final header = _pngHeader(47770, 17949);
    final api = _FakeFileIoApi(size: header.length, bytes: header);
    await expectLater(
      readRawThumbnailFallback(api, _container, 'dense.png'),
      throwsA(isA<ImagePreviewUnavailableException>()),
    );
  });

  test('an ordinary small image still comes back as raw bytes', () async {
    final header = _pngHeader(800, 600);
    final api = _FakeFileIoApi(size: header.length, bytes: header);
    expect(await readRawThumbnailFallback(api, _container, 'ok.png'), header);
  });
}
