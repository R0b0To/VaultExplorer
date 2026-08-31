import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
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
}
