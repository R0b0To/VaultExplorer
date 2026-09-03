import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_archive_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';

/// Fakes the native scan/extract channel calls so [ArchiveService] can be
/// exercised without a real MethodChannel platform implementation. Mirrors
/// a small archive: scanning returns one indexed entry per file, and
/// extracting an index returns that file's bytes -- matching the native
/// engine's index-addressed extraction contract (see [ArchiveEntryInfo.index]).
class _FakeArchiveApi extends VaultArchiveApi {
  _FakeArchiveApi(this._files) : super(const MethodChannel('test/archive')) {
    _paths = _files.keys.toList();
  }

  final Map<String, Uint8List> _files;
  late final List<String> _paths;
  final scannedVaultPaths = <String>[];
  final extractedIndexes = <int>[];

  List<ArchiveEntryInfo> get _entries => [
        for (var i = 0; i < _paths.length; i++)
          ArchiveEntryInfo(
            path: _paths[i],
            uncompressedSize: _files[_paths[i]]!.length,
            compressedSize: _files[_paths[i]]!.length,
            modTime: DateTime.utc(2026, 1, 1),
            isEncrypted: false,
            isDirectory: false,
            index: i,
          ),
      ];

  @override
  Future<ArchiveIndexResult> scanVaultArchive({
    required String filePath,
    required String vaultPath,
    String? passphrase,
  }) async {
    scannedVaultPaths.add(vaultPath);
    return ArchiveIndexResult(
      status: ArchiveOpenStatus.ok,
      entries: _entries,
      isSolid: false,
      errorMessage: '',
    );
  }

  @override
  Future<Uint8List?> extractVaultArchiveEntry({
    required String filePath,
    required String vaultPath,
    required int targetIndex,
    String? passphrase,
  }) async {
    extractedIndexes.add(targetIndex);
    return _files[_paths[targetIndex]];
  }
}

class _FakeFileIoApi extends VaultFileIoApi {
  _FakeFileIoApi() : super(const MethodChannel('test/file-io'));

  final writtenPaths = <String>[];

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
  test(
    'uses the configured archive/file-IO APIs to open and extract an archive',
    () async {
      final archiveApi = _FakeArchiveApi({'notes.txt': Uint8List.fromList([1, 2])});
      final fileIoApi = _FakeFileIoApi();
      ArchiveService.configureWithArchiveApi(archiveApi: archiveApi, fileIoApi: fileIoApi);

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
      expect(archiveApi.scannedVaultPaths, ['backup.zip']);
      expect(archiveApi.extractedIndexes, [0]);
    },
  );
}