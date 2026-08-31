import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';

class _FakeFileIoApi extends VaultFileIoApi {
  _FakeFileIoApi(this.bytes) : super(const MethodChannel('test/archive'));

  final Uint8List bytes;
  final writtenPaths = <String>[];

  @override
  Future<Uint8List?> readWholeFile(
    MountedContainer container,
    String fileName,
  ) async => bytes;

  @override
  Future<bool> writeWholeFile(
    MountedContainer container,
    String fileName,
    Uint8List bytes,
  ) async {
    writtenPaths.add(fileName);
    return true;
  }
}

final _container = MountedContainer(
  uri: 'content://test-container',
  displayName: 'Test Vault',
  volId: 1,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 100000000,
  freeSpace: 50000000,
);

void main() {
  Uint8List zipBytes() {
    final archive = Archive()
      ..addFile(ArchiveFile('notes.txt', 2, Uint8List.fromList([1, 2])));
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  test(
    'uses the configured file I/O API to open and extract an archive',
    () async {
      final fileIoApi = _FakeFileIoApi(zipBytes());
      ArchiveService.configure(fileIoApi);

      final context = await ArchiveService.open(
        container: _container,
        archivePathInContainer: 'backup.zip',
        pathStackEntryIndex: 0,
      );
      final extracted = await ArchiveService.extractToContainer(
        container: _container,
        archiveContext: context,
        entryPaths: const ['notes.txt'],
        targetDirInContainer: 'restored',
      );

    expect(context.listDirectory(''), contains(endsWith('|notes.txt')));
      expect(extracted, 1);
      expect(fileIoApi.writtenPaths, ['restored/notes.txt']);
    },
  );
}
