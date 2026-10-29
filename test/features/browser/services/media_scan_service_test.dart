import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/services/media_scan_service.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

/// Answers [VaultFileIoApi.listDirectory] from a fixed map of
/// container-relative folder -> raw wire-format entries (see `RawEntry`).
class _FakeListingApi extends VaultFileIoApi {
  final Map<String, List<String>> listings;

  _FakeListingApi(this.listings) : super(const MethodChannel('test'));

  @override
  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async => listings[dirPath];
}

MountedContainer _plainFolder() => buildExternalStorageContainer(
  rootPath: '/storage/emulated/0',
  displayName: 'Device',
  volId: -1000,
);

String _file(String name) => 'F|100|0|$name';
String _dir(String name) => 'D|0|0|$name';

/// The same predicate the file browser hands the scan for "play media here":
/// supported media that also passes the active type filter.
bool Function(String) _playable(String? filter) =>
    (name) => MediaViewerConstants.isSupported(name) && matchesFilter(name, filter);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The folder being played holds no media of its own; everything is below it.
  //
  //   ''            (docs.txt only)
  //   ├── a         clip1.mp4, photo1.jpg
  //   ├── b         song.mp3, clip2.mkv
  //   └── c
  //       └── c/d   photo2.png, clip3.webm
  final listings = <String, List<String>>{
    '': [_file('docs.txt'), _dir('a'), _dir('b'), _dir('c')],
    'a': [_file('clip1.mp4'), _file('photo1.jpg')],
    'b': [_file('song.mp3'), _file('clip2.mkv')],
    'c': [_dir('d')],
    'c/d': [_file('photo2.png'), _file('clip3.webm')],
  };

  Future<MediaScanResult> scan(String? filter) {
    return MediaScanService(_FakeListingApi(listings)).scan(
      container: _plainFolder(),
      startPath: '',
      token: CancellationToken(),
      showHiddenFiles: false,
      sortBy: SortBy.name,
      sortAscending: true,
      pinnedPaths: const {},
      isSupportedMedia: _playable(filter),
    );
  }

  group('MediaScanService.scan with the browser type filter', () {
    test('no filter collects every kind of media from all subfolders', () async {
      final result = await scan(null);

      expect(
        result.mediaPaths,
        unorderedEquals([
          'a/clip1.mp4',
          'a/photo1.jpg',
          'b/song.mp3',
          'b/clip2.mkv',
          'c/d/photo2.png',
          'c/d/clip3.webm',
        ]),
      );
    });

    test('video filter collects only videos, at any depth', () async {
      final result = await scan('video');

      expect(
        result.mediaPaths,
        unorderedEquals(['a/clip1.mp4', 'b/clip2.mkv', 'c/d/clip3.webm']),
      );
    });

    test('image filter collects only images', () async {
      final result = await scan('image');

      expect(
        result.mediaPaths,
        unorderedEquals(['a/photo1.jpg', 'c/d/photo2.png']),
      );
    });

    test('audio filter collects only audio', () async {
      final result = await scan('audio');

      expect(result.mediaPaths, ['b/song.mp3']);
    });

    test('a filter nothing matches finds nothing and does not hit a limit', () async {
      // 'document' matches no playable media, so the scan completes empty
      // rather than falling back to "any media".
      final result = await scan('document');

      expect(result.mediaPaths, isEmpty);
      expect(result.cancelled, isFalse);
      expect(result.limitReached, isFalse);
    });
  });
}
