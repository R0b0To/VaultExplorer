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
      'an unreadable side is treated as empty rather than throwing',
      () async {
        final left = _container('left-vault');
        final right = _container('right-vault');

        final service = VaultSyncService(
          _FakeVaultSyncApi({
            'right-vault::': ['F|1|1000|onlyOnRight.txt'],
            // No entry at all for 'left-vault::' -- listDirectory returns null,
            // mirroring an unreadable/missing directory on that side.
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
        expect(finalUpdate.entries, hasLength(1));
        expect(
          finalUpdate.entries.single.status,
          equals(VaultDiffStatus.onlyRight),
        );
      },
    );

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
}
