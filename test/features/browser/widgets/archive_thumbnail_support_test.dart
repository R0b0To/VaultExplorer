import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_archive_api.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/thumbnail_with_size.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/features/browser/widgets/archive_thumbnail_support.dart';

class _FakeArchiveApi extends VaultArchiveApi {
  _FakeArchiveApi() : super(const MethodChannel('test/archive-api'));

  int stageCalls = 0;
  int discardCalls = 0;
  String? lastStagedEntry;
  String? lastDiscardedPath;
  bool stageSuccess = true;

  @override
  Future<ArchiveEntryStageResult> stageBrowseEntry({
    required String filePath,
    String? vaultPath,
    required int targetIndex,
    required String entryName,
    String? passphrase,
  }) async {
    stageCalls++;
    lastStagedEntry = entryName;
    if (!stageSuccess) {
      return ArchiveEntryStageResult.ioError('Stage failed');
    }
    return const ArchiveEntryStageResult(
      status: ArchiveOpenStatus.ok,
      path: '/tmp/fake_staged_video.mp4',
      errorMessage: '',
    );
  }

  @override
  Future<bool> discardBrowseFile(String path) async {
    discardCalls++;
    lastDiscardedPath = path;
    return true;
  }
}

final _fakeThumbBytes = Uint8List.fromList([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]);

class _FakeFileIoApi extends VaultFileIoApi {
  _FakeFileIoApi() : super(const MethodChannel('test/file-io-api'));

  int getVideoThumbCalls = 0;
  int getVideoThumbWithSizeCalls = 0;
  String? lastSourcePath;
  bool shouldThrow = false;
  Uint8List? returnBytes = _fakeThumbBytes;
  ThumbnailWithSize? returnWithSize = ThumbnailWithSize(
    bytes: _fakeThumbBytes,
    width: 1920,
    height: 1080,
  );

  @override
  Future<Uint8List?> getVideoThumbnailFromLocalPath(
    String sourcePath, {
    int quality = 60,
    int targetSize = 180,
    int? timeUs,
    String? strategy,
    double? framePosition,
  }) async {
    getVideoThumbCalls++;
    lastSourcePath = sourcePath;
    if (shouldThrow) throw Exception('Decode failed');
    return returnBytes;
  }

  @override
  Future<ThumbnailWithSize?> getVideoThumbnailFromLocalPathWithSize(
    String sourcePath, {
    int quality = 60,
    int targetSize = 180,
    String? strategy,
    double? framePosition,
  }) async {
    getVideoThumbWithSizeCalls++;
    lastSourcePath = sourcePath;
    if (shouldThrow) throw Exception('Decode failed');
    return returnWithSize;
  }
}

class _FakeCryptoApi extends VaultCryptoApi {
  _FakeCryptoApi() : super(const MethodChannel('test/crypto-api'));
}

class _FakeHashApi extends VaultHashApi {
  _FakeHashApi() : super(const MethodChannel('test/hash-api'));
}

ArchiveEntryInfo _entry(String path, int size, int index) => ArchiveEntryInfo(
      path: path,
      uncompressedSize: size,
      compressedSize: size,
      modTime: DateTime(2026, 1, 1),
      isEncrypted: false,
      isDirectory: false,
      index: index,
    );

ArchiveContext _buildContext({
  required _FakeArchiveApi api,
  bool isSolid = false,
  bool isSevenZip = false,
  List<ArchiveEntryInfo>? entries,
}) {
  return ArchiveContext.fromScanResult(
    archivePathInContainer: 'archive.zip',
    pathStackEntryIndex: 0,
    api: api,
    vaultFilePath: 'vault-uri',
    vaultPath: 'archive.zip',
    indexResult: ArchiveIndexResult(
      status: ArchiveOpenStatus.ok,
      isSolid: isSolid,
      isSevenZip: isSevenZip,
      errorMessage: '',
      entries: entries ??
          [
            _entry('clip.mp4', 10 * 1024 * 1024, 0),
            _entry('huge.mp4', 600 * 1024 * 1024, 1),
          ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('archiveRelativeSubPath', () {
    test('extracts relative path correctly', () {
      expect(archiveRelativeSubPath('archive.zip', 'archive.zip'), '');
      expect(
        archiveRelativeSubPath('archive.zip/clip.mp4', 'archive.zip'),
        'clip.mp4',
      );
      expect(
        archiveRelativeSubPath('archive.zip/sub/clip.mp4', 'archive.zip'),
        'sub/clip.mp4',
      );
      expect(archiveRelativeSubPath('short', 'longer/path'), '');
    });
  });

  group('ArchiveThumbnailUnavailable', () {
    test('provides default and custom messages', () {
      expect(
        const ArchiveThumbnailUnavailable().toString(),
        contains('solid archives'),
      );
      expect(
        const ArchiveThumbnailUnavailable('Custom message').toString(),
        'Custom message',
      );
    });
  });

  group('fetchArchiveVideoEntryForThumbnail', () {
    late _FakeArchiveApi archiveApi;
    late _FakeFileIoApi fileIoApi;

    setUp(() {
      archiveApi = _FakeArchiveApi();
      fileIoApi = _FakeFileIoApi();
    });

    test('refuses solid non-7z archives', () async {
      final context = _buildContext(
        api: archiveApi,
        isSolid: true,
        isSevenZip: false,
      );

      expect(
        () => fetchArchiveVideoEntryForThumbnail(
          archiveContext: context,
          archiveRootPath: 'archive.zip',
          fullPath: 'archive.zip/clip.mp4',
          fileIoApi: fileIoApi,
          targetSize: 180,
          quality: 60,
        ),
        throwsA(isA<ArchiveThumbnailUnavailable>()),
      );
      expect(archiveApi.stageCalls, 0);
    });

    test('allows solid 7z archives', () async {
      final context = _buildContext(
        api: archiveApi,
        isSolid: true,
        isSevenZip: true,
      );

      final bytes = await fetchArchiveVideoEntryForThumbnail(
        archiveContext: context,
        archiveRootPath: 'archive.zip',
        fullPath: 'archive.zip/clip.mp4',
        fileIoApi: fileIoApi,
        targetSize: 180,
        quality: 60,
      );

      expect(bytes, fileIoApi.returnBytes);
      expect(archiveApi.stageCalls, 1);
      expect(archiveApi.discardCalls, 1);
    });

    test('refuses entries exceeding size limit', () async {
      final context = _buildContext(api: archiveApi);

      expect(
        () => fetchArchiveVideoEntryForThumbnail(
          archiveContext: context,
          archiveRootPath: 'archive.zip',
          fullPath: 'archive.zip/huge.mp4',
          fileIoApi: fileIoApi,
          targetSize: 180,
          quality: 60,
        ),
        throwsA(isA<ArchiveThumbnailUnavailable>()),
      );
      expect(archiveApi.stageCalls, 0);
    });

    test('stages, fetches thumbnail, and discards staged entry', () async {
      final context = _buildContext(api: archiveApi);

      final bytes = await fetchArchiveVideoEntryForThumbnail(
        archiveContext: context,
        archiveRootPath: 'archive.zip',
        fullPath: 'archive.zip/clip.mp4',
        fileIoApi: fileIoApi,
        targetSize: 180,
        quality: 60,
      );

      expect(bytes, _fakeThumbBytes);
      expect(archiveApi.stageCalls, 1);
      expect(archiveApi.lastStagedEntry, 'clip.mp4');
      expect(fileIoApi.getVideoThumbCalls, 1);
      expect(fileIoApi.lastSourcePath, '/tmp/fake_staged_video.mp4');
      expect(archiveApi.discardCalls, 1);
      expect(archiveApi.lastDiscardedPath, '/tmp/fake_staged_video.mp4');
    });

    test('always discards staged entry even when decoding throws', () async {
      final context = _buildContext(api: archiveApi);
      fileIoApi.shouldThrow = true;

      await expectLater(
        () => fetchArchiveVideoEntryForThumbnail(
          archiveContext: context,
          archiveRootPath: 'archive.zip',
          fullPath: 'archive.zip/clip.mp4',
          fileIoApi: fileIoApi,
          targetSize: 180,
          quality: 60,
        ),
        throwsA(isA<Exception>()),
      );

      expect(archiveApi.stageCalls, 1);
      expect(archiveApi.discardCalls, 1);
      expect(archiveApi.lastDiscardedPath, '/tmp/fake_staged_video.mp4');
    });
  });

  group('fetchArchiveVideoEntryForThumbnailWithSize', () {
    late _FakeArchiveApi archiveApi;
    late _FakeFileIoApi fileIoApi;

    setUp(() {
      archiveApi = _FakeArchiveApi();
      fileIoApi = _FakeFileIoApi();
    });

    test('stages, fetches thumbnail with dimensions, and discards staged entry', () async {
      final context = _buildContext(api: archiveApi);

      final (bytes, width, height) =
          await fetchArchiveVideoEntryForThumbnailWithSize(
        archiveContext: context,
        archiveRootPath: 'archive.zip',
        fullPath: 'archive.zip/clip.mp4',
        fileIoApi: fileIoApi,
        targetSize: 180,
        quality: 60,
      );

      expect(bytes, _fakeThumbBytes);
      expect(width, 1920);
      expect(height, 1080);
      expect(archiveApi.stageCalls, 1);
      expect(fileIoApi.getVideoThumbWithSizeCalls, 1);
      expect(archiveApi.discardCalls, 1);
      expect(archiveApi.lastDiscardedPath, '/tmp/fake_staged_video.mp4');
    });
  });

  group('VideoThumbnailFetcher with archive context', () {
    late _FakeArchiveApi archiveApi;
    late _FakeFileIoApi fileIoApi;
    late ThumbnailCacheService thumbnailCache;
    final container = MountedContainer(
      volId: 1,
      displayName: 'Vault',
      uri: 'vault-uri',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000,
      freeSpace: 500,
    );

    setUp(() {
      archiveApi = _FakeArchiveApi();
      fileIoApi = _FakeFileIoApi();
      ThumbnailCacheService.configure(
        fileIoApi: fileIoApi,
        cryptoApi: _FakeCryptoApi(),
        hashApi: _FakeHashApi(),
      );
      thumbnailCache = const ThumbnailCacheService();
    });

    test('fetch caches in-memory only', () async {
      final context = _buildContext(api: archiveApi);

      final bytes = await VideoThumbnailFetcher.fetch(
        thumbnailCache,
        fileIoApi,
        container,
        'archive.zip/clip.mp4',
        mode: ThumbnailCacheMode.appCache,
        quality: ThumbnailQuality.defaultQuality,
        targetSize: 180,
        archiveContext: context,
        archiveRootPath: 'archive.zip',
      );

      expect(bytes, _fakeThumbBytes);
      // Memory cache should now hit
      final peeked = thumbnailCache.peekMemory(
        container,
        'archive.zip/clip.mp4',
        ThumbnailQuality.defaultQuality,
      );
      expect(peeked, _fakeThumbBytes);
    });

    test('fetchWithSize caches in-memory with dimensions and notifies onSizeKnown', () async {
      final context = _buildContext(api: archiveApi);
      int? knownW;
      int? knownH;

      final bytes = await VideoThumbnailFetcher.fetchWithSize(
        thumbnailCache,
        fileIoApi,
        container,
        'archive.zip/clip.mp4',
        mode: ThumbnailCacheMode.appCache,
        quality: ThumbnailQuality.defaultQuality,
        targetSize: 180,
        onSizeKnown: (w, h) {
          knownW = w;
          knownH = h;
        },
        onUnknownSize: (_) async {},
        archiveContext: context,
        archiveRootPath: 'archive.zip',
      );

      expect(bytes, _fakeThumbBytes);
      expect(knownW, 1920);
      expect(knownH, 1080);

      final peeked = thumbnailCache.peekMemoryWithSize(
        container,
        'archive.zip/clip.mp4',
        ThumbnailQuality.defaultQuality,
      );
      expect(peeked?.$1, _fakeThumbBytes);
      expect(peeked?.$2, 1920);
      expect(peeked?.$3, 1080);
    });
  });
}
