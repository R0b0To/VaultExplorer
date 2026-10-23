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
  final stagedIndexes = <int>[];

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
  Future<ArchiveEntryExtractResult> extractVaultArchiveEntry({
    required String filePath,
    required String vaultPath,
    required int targetIndex,
    String? passphrase,
  }) async {
    extractedIndexes.add(targetIndex);
    return ArchiveEntryExtractResult(
      status: ArchiveOpenStatus.ok,
      data: _files[_paths[targetIndex]],
      errorMessage: '',
    );
  }

 @override
  Future<ArchiveEntryStageResult> stageBrowseEntry({
    required String filePath,
    String? vaultPath,
    required int targetIndex,
    required String entryName,
    String? passphrase,
  }) async {
    stagedIndexes.add(targetIndex);
    return ArchiveEntryStageResult(
      status: ArchiveOpenStatus.ok,
      path: '/private/cache/archive_browse_$entryName',
      errorMessage: '',
    );
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

/// Models the part of a vault that matters for extraction: `createDirectory`
/// and file writes fail when the parent folder doesn't exist yet. Plain device
/// storage behaves differently (its writes create missing parents), which is
/// why a nested-folder extract worked there but not inside a vault.
class _VaultLikeFileIoApi extends VaultFileIoApi {
  _VaultLikeFileIoApi() : super(const MethodChannel('test/vault-file-io'));

  final dirs = <String>{''};
  final files = <String>[];
  final createCalls = <String>[];

  static String _parent(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  @override
  Future<bool> createDirectory(
    MountedContainer container,
    String dirPath,
  ) async {
    createCalls.add(dirPath);
    if (!dirs.contains(_parent(dirPath))) return false;
    return dirs.add(dirPath);
  }

  @override
  Future<bool> writeWholeFile(
    MountedContainer container,
    String fileName,
    Uint8List bytes,
  ) async {
    if (!dirs.contains(_parent(fileName))) return false;
    files.add(fileName);
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
      final archiveApi = _FakeArchiveApi({
        'notes.txt': Uint8List.fromList([1, 2]),
      });
      final fileIoApi = _FakeFileIoApi();
      ArchiveService.configureWithArchiveApi(
        archiveApi: archiveApi,
        fileIoApi: fileIoApi,
      );

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

  test(
    'streams an archive media preview through the native archive API',
    () async {
      final archiveApi = _FakeArchiveApi({
        'clip.mp4': Uint8List.fromList([1, 2]),
      });
      ArchiveService.configureWithArchiveApi(
        archiveApi: archiveApi,
        fileIoApi: _FakeFileIoApi(),
      );

      final context = await ArchiveService.open(
        container: _container,
        archivePathInContainer: 'backup.zip',
        pathStackEntryIndex: 0,
      );

       final stageResult = await context.stageEntryForBrowse('clip.mp4');
      expect(stageResult.status, ArchiveOpenStatus.ok);
      expect(stageResult.path, '/private/cache/archive_browse_clip.mp4');
      expect(archiveApi.stagedIndexes, [0]);
    },
  );

  group('extracting nested folders into a vault-like destination', () {
    test('extracts a folder whose files all sit in nested subfolders', () async {
      final archiveApi = _FakeArchiveApi({
        'sub1/sub2/deep.txt': Uint8List.fromList([1]),
        'sub1/sub2/more.txt': Uint8List.fromList([2]),
      });
      final io = _VaultLikeFileIoApi();
      ArchiveService.configureWithArchiveApi(
        archiveApi: archiveApi,
        fileIoApi: io,
      );
      final context = await ArchiveService.open(
        container: _container,
        archivePathInContainer: 'test.zip',
        pathStackEntryIndex: 0,
      );

      final count = await ArchiveService.extractSelectedToContainer(
        container: _container,
        archiveContext: context,
        entryPaths: const ['sub1'],
        targetDirInContainer: '',
      );

      expect(count, 2);
      expect(io.files, ['sub1/sub2/deep.txt', 'sub1/sub2/more.txt']);
      // Parents first, and each folder only once.
      expect(io.createCalls, ['sub1', 'sub1/sub2']);
    });

    test('creates a destination folder that does not exist yet', () async {
      final archiveApi = _FakeArchiveApi({
        'sub1/sub2/deep.txt': Uint8List.fromList([1]),
        'sub1/top.txt': Uint8List.fromList([2]),
      });
      final io = _VaultLikeFileIoApi();
      ArchiveService.configureWithArchiveApi(
        archiveApi: archiveApi,
        fileIoApi: io,
      );
      final context = await ArchiveService.open(
        container: _container,
        archivePathInContainer: 'test.zip',
        pathStackEntryIndex: 0,
      );

      final count = await ArchiveService.extractSelectedToContainer(
        container: _container,
        archiveContext: context,
        entryPaths: const ['sub1'],
        targetDirInContainer: 'out/test',
      );

      expect(count, 2);
      expect(io.files, [
        'out/test/sub1/sub2/deep.txt',
        'out/test/sub1/top.txt',
      ]);
    });

    test('the case-collision route also creates every missing ancestor', () async {
      final archiveApi = _FakeArchiveApi({
        'sub1/sub2/deep.txt': Uint8List.fromList([1]),
      });
      final io = _VaultLikeFileIoApi();
      ArchiveService.configureWithArchiveApi(
        archiveApi: archiveApi,
        fileIoApi: io,
      );
      final context = await ArchiveService.open(
        container: _container,
        archivePathInContainer: 'test.zip',
        pathStackEntryIndex: 0,
      );

      final count = await ArchiveService.extractMappedToContainer(
        container: _container,
        archiveContext: context,
        destRelByEntryPath: const {
          'sub1/sub2/deep.txt': 'sub1/sub2/deep.txt',
        },
        targetDirInContainer: '',
      );

      expect(count, 1);
      expect(io.files, ['sub1/sub2/deep.txt']);
    });
  });

  group('ArchiveService extension helpers', () {
    test('.apk is openable as an archive but is not an archive extension', () {
      // isArchive() also backs isUnsupportedArchiveCarrierName() (composite
      // containers), where an .apk is a valid carrier -- so it must stay
      // false there even though the native engine can read an APK as a ZIP.
      expect(ArchiveService.isArchive('apk'), isFalse);
      expect(ArchiveService.isZipLikePackage('apk'), isTrue);
      expect(ArchiveService.isOpenableAsArchive('apk'), isTrue);
    });

    test('helpers are case-insensitive', () {
      expect(ArchiveService.isZipLikePackage('APK'), isTrue);
      expect(ArchiveService.isOpenableAsArchive('Apk'), isTrue);
      expect(ArchiveService.isOpenableAsArchive('ZIP'), isTrue);
    });

    test('real archive extensions stay openable', () {
      for (final ext in ArchiveService.allArchiveExtensions) {
        expect(ArchiveService.isArchive(ext), isTrue, reason: ext);
        expect(ArchiveService.isOpenableAsArchive(ext), isTrue, reason: ext);
        expect(ArchiveService.isZipLikePackage(ext), isFalse, reason: ext);
      }
    });

    test('every format the app can create is openable and opens on tap', () {
      // tar.gz / tar.bz2 / tar.xz / tar.zst / tar.lzma are named by their last
      // extension; iso and cpio have their own.
      for (final ext in [
        'zip', '7z', 'tar', 'gz', 'bz2', 'xz', 'zst', 'lzma', 'iso', 'cpio',
      ]) {
        expect(ArchiveService.opensOnTap(ext), isTrue, reason: ext);
        expect(ArchiveService.isOpenableAsArchive(ext), isTrue, reason: ext);
      }
      expect(ArchiveService.opensOnTap('ISO'), isTrue);
      expect(ArchiveService.opensOnTap('Cpio'), isTrue);
    });

    test('iso/cpio open on tap but are not rejected as composite carriers', () {
      // isArchive() backs isUnsupportedArchiveCarrierName(); an ISO image is a
      // valid composite-container carrier, so it must stay false there.
      expect(ArchiveService.isArchive('iso'), isFalse);
      expect(ArchiveService.isArchive('cpio'), isFalse);
      expect(ArchiveService.isIsoOrCpio('iso'), isTrue);
      expect(ArchiveService.isZipLikePackage('iso'), isFalse);
    });

    test('an apk is still not opened on tap', () {
      expect(ArchiveService.opensOnTap('apk'), isFalse);
    });

    test('unrelated extensions are not openable as an archive', () {
      for (final ext in ['txt', 'pdf', 'xapk', '']) {
        expect(ArchiveService.isOpenableAsArchive(ext), isFalse, reason: ext);
      }
    });
  });
}
