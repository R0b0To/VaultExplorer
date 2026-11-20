import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/services/vault_sync_service.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';

/// Fakes [VaultFileIoApi.listDirectory] with a fixed map of
/// "containerUri::dirPath" -> raw wire-format entries (see [RawEntry]),
/// so [VaultSyncService.scanDiff]'s walk/diff logic can be exercised
/// without a real mounted container or native call.
class _FakeVaultSyncApi extends VaultFileIoApi {
  final Map<String, List<String>> listings;
  _FakeVaultSyncApi(this.listings) : super(const MethodChannel('test'));

  @override
  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async {
    return listings['${container.uri}::$dirPath'];
  }
}

/// A [_FakeVaultSyncApi] whose listing of [throwingKey] throws, like a
/// platform-channel error from a vault that can't be read.
class _ThrowingApi extends _FakeVaultSyncApi {
  final String throwingKey;
  _ThrowingApi(super.listings, {required this.throwingKey});

  @override
  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async {
    if ('${container.uri}::$dirPath' == throwingKey) {
      throw PlatformException(code: 'LIST_FAILED');
    }
    return super.listDirectory(container, dirPath, refresh: refresh);
  }
}

/// A [_FakeVaultSyncApi] that also records every listing request.
class _RecordingApi extends _FakeVaultSyncApi {
  final List<({String uri, bool refresh})> requests = [];
  _RecordingApi(super.listings);

  @override
  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) {
    requests.add((uri: container.uri, refresh: refresh));
    return super.listDirectory(container, dirPath, refresh: refresh);
  }
}

MountedContainer _container(String uri) => MountedContainer(
  uri: uri,
  displayName: uri,
  volId: uri.hashCode,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 100000000,
  freeSpace: 50000000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VaultSyncService.scanDiff', () {
    test('classifies onlyLeft/onlyRight/newer/conflicted/identical entries and '
        'descends into folders present on both sides', () async {
      final left = _container('left-vault');
      final right = _container('right-vault');

      final service = VaultSyncService(
        _FakeVaultSyncApi({
          'left-vault::': [
            'F|100|1000|same.txt', // same size on both sides -- identical
            'F|50|1000|onlyLeft.txt',
            // Different sizes + mtimes far enough apart to clear the
            // service's mtime tolerance (_mtimeToleranceSecs = 2).
            'F|15|5000|leftNewer.txt', // newer AND bigger on the left
            'F|10|1000|rightNewer.txt', // older AND smaller on the left
            'F|10|1000|conflict.txt', // different size, same mtime
            'F|5|1000|typeMismatch', // file on the left...
            'D|0|1000|subdir', // folder on both -- descend, don't list
          ],
          'right-vault::': [
            'F|100|1000|same.txt',
            'F|50|1000|onlyRight.txt',
            'F|10|1000|leftNewer.txt',
            'F|15|5000|rightNewer.txt',
            'F|20|1000|conflict.txt',
            'D|0|1000|typeMismatch', // ...but a folder on the right
            'D|0|1000|subdir',
          ],
          'left-vault::subdir': ['F|1|1000|nested.txt'],
          'right-vault::subdir': <String>[],
        }),
      );

      final updates = await service
          .scanDiff(
            left: VaultSyncSide(container: left, relativePath: ''),
            right: VaultSyncSide(container: right, relativePath: ''),
          )
          .toList();

      final finalUpdate = updates.last;
      expect(finalUpdate.progress.stage, equals(VaultSyncScanStage.complete));
      expect(finalUpdate.identicalCount, equals(1)); // same.txt only

      final byPath = {for (final e in finalUpdate.entries) e.relativePath: e};

      expect(byPath['onlyLeft.txt']!.status, equals(VaultDiffStatus.onlyLeft));
      expect(
        byPath['onlyRight.txt']!.status,
        equals(VaultDiffStatus.onlyRight),
      );
      expect(
        byPath['leftNewer.txt']!.status,
        equals(VaultDiffStatus.leftNewer),
      );
      expect(
        byPath['rightNewer.txt']!.status,
        equals(VaultDiffStatus.rightNewer),
      );
      expect(
        byPath['conflict.txt']!.status,
        equals(VaultDiffStatus.conflicted),
      );
      expect(
        byPath['typeMismatch']!.status,
        equals(VaultDiffStatus.conflicted),
      );
      expect(byPath['typeMismatch']!.typeMismatch, isTrue);

      // Descended into the shared "subdir" rather than listing it as an
      // entry itself; the file only present inside it on the left shows
      // up with the folder-qualified relative path.
      expect(byPath.containsKey('subdir'), isFalse);
      expect(
        byPath['subdir/nested.txt']!.status,
        equals(VaultDiffStatus.onlyLeft),
      );
    });

    test(
      'same-size files count as identical even when modified times differ',
      () async {
        // Regression test for the "smart guard": storage backends that reset
        // mtimes on write shouldn't cause a same-size file to be flagged as
        // out of sync and repeatedly re-copied.
        final left = _container('left-vault');
        final right = _container('right-vault');

        final service = VaultSyncService(
          _FakeVaultSyncApi({
            'left-vault::': ['F|42|1000|same-size.txt'],
            'right-vault::': ['F|42|9999|same-size.txt'],
          }),
        );

        final updates = await service
            .scanDiff(
              left: VaultSyncSide(container: left, relativePath: ''),
              right: VaultSyncSide(container: right, relativePath: ''),
            )
            .toList();

        final finalUpdate = updates.last;
        expect(finalUpdate.identicalCount, equals(1));
        expect(finalUpdate.entries, isEmpty);
      },
    );

    test(
      'a mtime difference within tolerance on a differently-sized file is conflicted, not newer',
      () async {
        final left = _container('left-vault');
        final right = _container('right-vault');

        final service = VaultSyncService(
          _FakeVaultSyncApi({
            'left-vault::': ['F|10|1000|near.txt'],
            'right-vault::': [
              'F|20|1001|near.txt',
            ], // 1s apart, under the 2s tolerance
          }),
        );

        final updates = await service
            .scanDiff(
              left: VaultSyncSide(container: left, relativePath: ''),
              right: VaultSyncSide(container: right, relativePath: ''),
            )
            .toList();

        final entry = updates.last.entries.single;
        expect(entry.status, equals(VaultDiffStatus.conflicted));
      },
    );

    test(
      'an unreadable vault side fails the scan instead of being treated as '
      'empty',
      () async {
        final left = _container('left-vault');
        final right = _container('right-vault');

        final service = VaultSyncService(
          _FakeVaultSyncApi({
            'right-vault::': ['F|1|1000|onlyOnRight.txt'],
            // No entry at all for 'left-vault::' -- listDirectory returns
            // null, which for a vault means the folder couldn't be read.
            // Diffing against "empty" would offer to copy (and overwrite)
            // everything from the right.
          }),
        );

        final updates = await service
            .scanDiff(
              left: VaultSyncSide(container: left, relativePath: ''),
              right: VaultSyncSide(container: right, relativePath: ''),
            )
            .toList();

        final finalUpdate = updates.last;
        expect(finalUpdate.progress.stage, equals(VaultSyncScanStage.failed));
        expect(finalUpdate.progress.currentPath, equals(''));
        expect(finalUpdate.entries, isEmpty);
      },
    );

    test('a vault folder that can\'t be read part-way fails the scan and '
        'offers nothing to sync', () async {
      final left = _container('left-vault');
      final right = _container('right-vault');

      final service = VaultSyncService(
        _FakeVaultSyncApi({
          'left-vault::': ['F|1|1000|only-left.txt', 'D|0|1000|subdir'],
          'right-vault::': ['D|0|1000|subdir'],
          'left-vault::subdir': ['F|1|1000|nested.txt'],
          // 'right-vault::subdir' is missing -> unreadable.
        }),
      );

      final updates = await service
          .scanDiff(
            left: VaultSyncSide(container: left, relativePath: ''),
            right: VaultSyncSide(container: right, relativePath: ''),
          )
          .toList();

      final finalUpdate = updates.last;
      expect(finalUpdate.progress.stage, equals(VaultSyncScanStage.failed));
      expect(finalUpdate.progress.currentPath, equals('subdir'));
      // Not even the differences found before the failure are offered.
      expect(finalUpdate.entries, isEmpty);
    });

    test('a vault listing that throws fails the scan', () async {
      final left = _container('left-vault');
      final right = _container('right-vault');

      final service = VaultSyncService(
        _ThrowingApi({
          'left-vault::': ['F|1|1000|a.txt'],
          'right-vault::': <String>[],
        }, throwingKey: 'right-vault::'),
      );

      final updates = await service
          .scanDiff(
            left: VaultSyncSide(container: left, relativePath: ''),
            right: VaultSyncSide(container: right, relativePath: ''),
          )
          .toList();

      expect(updates.last.progress.stage, equals(VaultSyncScanStage.failed));
      expect(updates.last.entries, isEmpty);
    });

    test('a genuinely empty vault folder still compares normally', () async {
      final left = _container('left-vault');
      final right = _container('right-vault');

      final service = VaultSyncService(
        _FakeVaultSyncApi({
          'left-vault::': ['F|1|1000|a.txt'],
          'right-vault::': <String>[],
        }),
      );

      final updates = await service
          .scanDiff(
            left: VaultSyncSide(container: left, relativePath: ''),
            right: VaultSyncSide(container: right, relativePath: ''),
          )
          .toList();

      expect(updates.last.progress.stage, equals(VaultSyncScanStage.complete));
      expect(updates.last.entries.single.status, VaultDiffStatus.onlyLeft);
    });

    test(
      'a token cancelled before scanning reports the cancelled stage and no entries',
      () async {
        final left = _container('left-vault');
        final right = _container('right-vault');

        final service = VaultSyncService(
          _FakeVaultSyncApi({
            'left-vault::': ['F|1|1000|a.txt'],
            'right-vault::': <String>[],
          }),
        );

        final token = VaultSyncCancellationToken()..cancel();
        final updates = await service
            .scanDiff(
              left: VaultSyncSide(container: left, relativePath: ''),
              right: VaultSyncSide(container: right, relativePath: ''),
              cancelToken: token,
            )
            .toList();

        expect(
          updates.last.progress.stage,
          equals(VaultSyncScanStage.cancelled),
        );
        expect(updates.last.entries, isEmpty);
      },
    );
  });


  group('VaultSyncService with device and provider storage', () {
    MountedContainer vault(String uri, int volId) => MountedContainer(
      uri: uri,
      displayName: uri,
      volId: volId,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 100000000,
      freeSpace: 50000000,
      containerFormat: 'veracrypt',
    );
    final local = buildLocalStorageContainer(
      rootPath: '/local',
      displayName: 'Local Storage',
    );
    final provider = buildExternalStorageContainer(
      rootPath: 'content://provider/tree/x',
      displayName: 'Drive',
      volId: -100,
    );

    VaultSyncSide side(MountedContainer c) =>
        VaultSyncSide(container: c, relativePath: '');

    test('an unreadable device-storage or provider side is still treated as '
        'empty (only vaults fail the scan)', () async {
      final service = VaultSyncService(
        _FakeVaultSyncApi({
          // No listing for '/local::' -> null.
          'content://provider/tree/x::': ['F|20|1000|a.txt'],
        }),
      );

      final updates = await service
          .scanDiff(left: side(local), right: side(provider))
          .toList();

      expect(updates.last.progress.stage, VaultSyncScanStage.complete);
      expect(updates.last.entries.single.status, VaultDiffStatus.onlyRight);
    });

    test('a file whose modified time the storage did not report is left for '
        'the user rather than guessed newer or older', () async {
      final service = VaultSyncService(
        _FakeVaultSyncApi({
          '/local::': ['F|10|5000|notes.txt'],
          // Some document providers report no modified time (0).
          'content://provider/tree/x::': ['F|20|0|notes.txt'],
        }),
      );

      final updates = await service
          .scanDiff(left: side(local), right: side(provider))
          .toList();

      final entries = updates.last.entries;
      expect(entries, hasLength(1));
      expect(entries.single.status, VaultDiffStatus.conflicted);
      expect(
        service.defaultAction(entries.single, SyncDirection.twoWay),
        EntryAction.skip,
      );
    });

    test('lists device storage fresh, but not vaults or provider folders',
        () async {
      final api = _RecordingApi({
        '/local::': <String>[],
        'vault.hc::': <String>[],
        'content://provider/tree/x::': <String>[],
      });
      final service = VaultSyncService(api);

      await service
          .scanDiff(left: side(local), right: side(vault('vault.hc', 7)))
          .toList();
      await service
          .scanDiff(left: side(provider), right: side(vault('vault.hc', 7)))
          .toList();

      expect(
        api.requests.where((r) => r.uri == '/local').map((r) => r.refresh),
        everyElement(isTrue),
      );
      expect(
        api.requests.where((r) => r.uri != '/local').map((r) => r.refresh),
        everyElement(isFalse),
      );
    });

    test('plaintextDestinations flags only vault-to-plain-storage flows', () {
      final service = VaultSyncService(_FakeVaultSyncApi({}));
      final v = side(vault('vault.hc', 7));
      final other = side(vault('other.hc', 8));
      final plain = side(local);
      final drive = side(provider);

      List<VaultSyncSide> run(
        VaultSyncSide l,
        VaultSyncSide r,
        List<EntryAction> actions,
      ) => service.plaintextDestinations(left: l, right: r, actions: actions);

      // Vault (left) -> device storage (right): plain files land on the right.
      expect(run(v, plain, [EntryAction.copyToRight]), [plain]);
      // Same, with the vault on the right and copying to the left.
      expect(run(plain, v, [EntryAction.copyToLeft]), [plain]);
      expect(run(v, drive, [EntryAction.copyToRight]), [drive]);
      // Importing into a vault, or copying nothing, exports nothing.
      expect(run(v, plain, [EntryAction.copyToLeft]), isEmpty);
      expect(run(v, plain, [EntryAction.skip]), isEmpty);
      // Vault to vault stays encrypted; plain to plain was never encrypted.
      expect(run(v, other, [EntryAction.copyToRight]), isEmpty);
      expect(run(plain, drive, [EntryAction.copyToRight]), isEmpty);
      // Both directions at once against plain storage lists it once.
      expect(
        run(v, plain, [EntryAction.copyToRight, EntryAction.copyToLeft]),
        [plain],
      );
    });
  });

  group('VaultSyncService.defaultAction mirror directions', () {
    final service = VaultSyncService(_FakeVaultSyncApi({}));

    VaultDiffEntry entry(VaultDiffStatus status, {bool typeMismatch = false}) =>
        VaultDiffEntry(
          relativePath: 'a.txt',
          name: 'a.txt',
          isDir: false,
          status: status,
          typeMismatch: typeMismatch,
        );

    test('mirrorToRight copies everything left over right and deletes extras '
        'on the right', () {
      EntryAction a(VaultDiffStatus s) =>
          service.defaultAction(entry(s), SyncDirection.mirrorToRight);
      expect(a(VaultDiffStatus.onlyLeft), EntryAction.copyToRight);
      expect(a(VaultDiffStatus.onlyRight), EntryAction.deleteRight);
      expect(a(VaultDiffStatus.leftNewer), EntryAction.copyToRight);
      // A mirror makes the target identical even when its copy is newer.
      expect(a(VaultDiffStatus.rightNewer), EntryAction.copyToRight);
      expect(a(VaultDiffStatus.conflicted), EntryAction.copyToRight);
    });

    test('mirrorToLeft is the same in the other direction', () {
      EntryAction a(VaultDiffStatus s) =>
          service.defaultAction(entry(s), SyncDirection.mirrorToLeft);
      expect(a(VaultDiffStatus.onlyRight), EntryAction.copyToLeft);
      expect(a(VaultDiffStatus.onlyLeft), EntryAction.deleteLeft);
      expect(a(VaultDiffStatus.rightNewer), EntryAction.copyToLeft);
      expect(a(VaultDiffStatus.leftNewer), EntryAction.copyToLeft);
      expect(a(VaultDiffStatus.conflicted), EntryAction.copyToLeft);
    });

    test('only the mirror directions ever delete', () {
      for (final direction in [
        SyncDirection.twoWay,
        SyncDirection.leftToRight,
        SyncDirection.rightToLeft,
      ]) {
        for (final status in VaultDiffStatus.values) {
          expect(
            service.defaultAction(entry(status), direction).isDelete,
            isFalse,
            reason: '$direction / $status',
          );
        }
      }
    });

    test('type mismatches and in-sync items are skipped even when mirroring',
        () {
      for (final direction in [
        SyncDirection.mirrorToRight,
        SyncDirection.mirrorToLeft,
      ]) {
        expect(
          service.defaultAction(
            entry(VaultDiffStatus.conflicted, typeMismatch: true),
            direction,
          ),
          EntryAction.skip,
        );
        expect(
          service.defaultAction(entry(VaultDiffStatus.identical), direction),
          EntryAction.skip,
        );
        expect(
          service.defaultAction(entry(VaultDiffStatus.bothFolders), direction),
          EntryAction.skip,
        );
      }
    });
  });

  group('VaultSyncService.listFolder', () {
    test('merges both sides, keeps in-sync items and shared folders, and '
        'lists folders first', () async {
      final left = _container('left-vault');
      final right = _container('right-vault');
      final service = VaultSyncService(
        _FakeVaultSyncApi({
          'left-vault::docs': [
            'F|100|1000|same.txt',
            'F|50|1000|onlyLeft.txt',
            'F|15|5000|newer.txt',
            'D|0|1000|shared',
            'D|0|1000|leftOnlyDir',
          ],
          'right-vault::docs': [
            'F|100|1000|same.txt',
            'F|50|1000|onlyRight.txt',
            'F|10|1000|newer.txt',
            'D|0|1000|shared',
          ],
        }),
      );

      final listing = await service.listFolder(
        left: VaultSyncSide(container: left, relativePath: ''),
        right: VaultSyncSide(container: right, relativePath: ''),
        relDir: 'docs',
      );

      expect(listing.unreadable, isFalse);
      final byPath = {for (final e in listing.entries) e.relativePath: e};
      expect(byPath['docs/same.txt']!.status, VaultDiffStatus.identical);
      expect(byPath['docs/onlyLeft.txt']!.status, VaultDiffStatus.onlyLeft);
      expect(byPath['docs/onlyRight.txt']!.status, VaultDiffStatus.onlyRight);
      expect(byPath['docs/newer.txt']!.status, VaultDiffStatus.leftNewer);
      expect(byPath['docs/shared']!.status, VaultDiffStatus.bothFolders);
      expect(byPath['docs/leftOnlyDir']!.status, VaultDiffStatus.onlyLeft);
      expect(byPath['docs/leftOnlyDir']!.isDir, isTrue);

      // Folders first, then files, each alphabetical.
      expect(listing.entries.map((e) => e.name).toList(), [
        'leftOnlyDir',
        'shared',
        'newer.txt',
        'onlyLeft.txt',
        'onlyRight.txt',
        'same.txt',
      ]);
    });

    test('a folder that exists on only one side lists as one-sided', () async {
      final service = VaultSyncService(
        _FakeVaultSyncApi({
          'left-vault::only': ['F|1|1000|a.txt'],
          'right-vault::only': <String>[],
        }),
      );
      final listing = await service.listFolder(
        left: VaultSyncSide(container: _container('left-vault'), relativePath: ''),
        right: VaultSyncSide(container: _container('right-vault'), relativePath: ''),
        relDir: 'only',
      );
      expect(listing.entries.single.status, VaultDiffStatus.onlyLeft);
    });

    test('an unreadable vault folder is reported, not shown as empty', () async {
      final service = VaultSyncService(
        _FakeVaultSyncApi({
          // No listing at all for the right vault's folder -> null.
          'left-vault::x': ['F|1|1000|a.txt'],
        }),
      );
      final listing = await service.listFolder(
        left: VaultSyncSide(container: _container('left-vault'), relativePath: ''),
        right: VaultSyncSide(container: _container('right-vault'), relativePath: ''),
        relDir: 'x',
      );
      expect(listing.unreadable, isTrue);
      expect(listing.entries, isEmpty);
    });

    test('a file-versus-folder mismatch is flagged', () async {
      final service = VaultSyncService(
        _FakeVaultSyncApi({
          'left-vault::': ['F|5|1000|thing'],
          'right-vault::': ['D|0|1000|thing'],
        }),
      );
      final listing = await service.listFolder(
        left: VaultSyncSide(container: _container('left-vault'), relativePath: ''),
        right: VaultSyncSide(container: _container('right-vault'), relativePath: ''),
        relDir: '',
      );
      final e = listing.entries.single;
      expect(e.typeMismatch, isTrue);
      expect(e.status, VaultDiffStatus.conflicted);
    });
  });

  group('VaultSyncService.deleteItemsFor', () {
    final service = VaultSyncService(_FakeVaultSyncApi({}));
    final side = VaultSyncSide(
      container: _container('left-vault'),
      relativePath: 'root',
    );

    VaultDiffEntry e(String path, {bool isDir = false, bool mismatch = false}) =>
        VaultDiffEntry(
          relativePath: path,
          name: path.split('/').last,
          isDir: isDir,
          status: mismatch
              ? VaultDiffStatus.conflicted
              : VaultDiffStatus.onlyLeft,
          typeMismatch: mismatch,
        );

    test('paths are resolved under the side root', () {
      final items = service.deleteItemsFor(side, [e('a.txt')], sideIsLeft: true);
      expect(items.single.path, 'root/a.txt');
      expect(items.single.isDir, isFalse);
    });

    test('an entry inside another selected folder is dropped', () {
      final items = service.deleteItemsFor(
        side,
        [e('dir/inner.txt'), e('dir', isDir: true), e('dirOther.txt')],
        sideIsLeft: true,
      );
      expect(items.map((i) => i.path).toSet(), {'root/dir', 'root/dirOther.txt'});
    });

    test('a file next to a folder with a similar name is not dropped', () {
      final items = service.deleteItemsFor(
        side,
        [e('dir', isDir: true), e('dir2/x.txt')],
        sideIsLeft: true,
      );
      expect(items, hasLength(2));
    });

    test('the right side of a type mismatch has the opposite type', () {
      // Left is a file, so right is a folder.
      final fileOnLeft = e('thing', isDir: false, mismatch: true);
      expect(
        service.deleteItemsFor(side, [fileOnLeft], sideIsLeft: true).single.isDir,
        isFalse,
      );
      expect(
        service.deleteItemsFor(side, [fileOnLeft], sideIsLeft: false).single.isDir,
        isTrue,
      );
    });
  });
}
