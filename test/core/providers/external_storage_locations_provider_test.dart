import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_channel.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/services/external_storage_repository.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

/// In-memory stand-in for the JSON file. [saveGate] lets a test park a save
/// half-way (file not yet updated) to reproduce a refresh racing a write.
class _FakeRepo implements ExternalStorageRepository {
  _FakeRepo([List<ExternalStorageLocation> initial = const []])
      : stored = List.of(initial);

  List<ExternalStorageLocation> stored;
  Completer<void>? saveGate;
  bool failNextSave = false;
  int saveCount = 0;

  @override
  Future<List<ExternalStorageLocation>> loadAll() async => List.of(stored);

  @override
  Future<void> saveAll(List<ExternalStorageLocation> list) async {
    saveCount++;
    final gate = saveGate;
    if (gate != null) await gate.future;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('disk full');
    }
    stored = List.of(list);
  }
}

Map<String, Object?> _vol(
  String id, {
  String desc = 'SD card',
  bool primary = false,
  bool removable = true,
  String state = 'mounted',
  String? path,
}) => {
  'id': id,
  'description': desc,
  'isPrimary': primary,
  'isRemovable': removable,
  'state': state,
  'path': path ?? '/storage/$id',
  'hasDirectAccess': true,
};

const _sdTreeRoot =
    'content://com.android.externalstorage.documents/tree/AAAA-1111%3A';
const _sdTreeSubfolder =
    'content://com.android.externalstorage.documents/tree/AAAA-1111%3ADCIM';

ExternalStorageLocation _userLocation({
  String id = 'ext_1',
  String path = '/storage/emulated/0/Documents',
  String? treeUri,
  int volId = -100,
}) => ExternalStorageLocation(
  id: id,
  path: path,
  treeUri: treeUri,
  displayName: 'Documents',
  volId: volId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kVaultEngineChannelName);
  late List<Map<String, Object?>> volumes;
  late bool volumesThrow;
  late Map<String, Object?>? pickResult;

  setUp(() {
    volumes = [];
    volumesThrow = false;
    pickResult = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case ChannelMethods.getStorageVolumes:
              if (volumesThrow) throw PlatformException(code: 'boom');
              return volumes;
            case ChannelMethods.pickExtractFolder:
              return pickResult;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  ProviderContainer makeContainer(_FakeRepo repo) {
    final container = ProviderContainer(
      overrides: [externalStorageRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Builds the notifier and waits for its initial discovery to finish.
  Future<ExternalStorageLocationsNotifier> settle(
    ProviderContainer container,
  ) async {
    final notifier = container.read(externalStorageLocationsProvider.notifier);
    await notifier.refreshSystemVolumes();
    return notifier;
  }

  List<ExternalStorageLocation> current(ProviderContainer c) =>
      c.read(externalStorageLocationsProvider);

  group('system volume discovery', () {
    test('lists only mounted, removable, non-primary volumes', () async {
      volumes = [
        _vol('primary', primary: true, removable: false,
            path: '/storage/emulated/0'),
        _vol('AAAA-1111'),
        _vol('BBBB-2222', state: 'unmounted'),
        _vol('CCCC-3333', removable: false),
      ];
      final c = makeContainer(_FakeRepo());
      await settle(c);

      final locations = current(c);
      expect(locations.map((l) => l.id), ['sysvol_AAAA-1111']);
      final sd = locations.single;
      expect(sd.isSystemVolume, isTrue);
      expect(sd.path, '/storage/AAAA-1111');
      expect(sd.treeUri, isNull);
      expect(sd.displayName, 'SD card');
      expect(sd.volId, lessThanOrEqualTo(kExternalStorageBaseVolId));
    });

    test('falls back to the native id when there is no description', () async {
      volumes = [_vol('AAAA-1111', desc: '')];
      final c = makeContainer(_FakeRepo());
      await settle(c);
      expect(current(c).single.displayName, 'AAAA-1111');
    });

    test('hides a volume the user already added by raw path', () async {
      volumes = [_vol('AAAA-1111')];
      final c = makeContainer(
        _FakeRepo([_userLocation(path: '/storage/AAAA-1111')]),
      );
      await settle(c);
      expect(current(c).map((l) => l.id), ['ext_1']);
    });

    test('hides a volume the user already added as a SAF root grant', () async {
      volumes = [_vol('AAAA-1111')];
      final c = makeContainer(
        _FakeRepo([_userLocation(path: _sdTreeRoot, treeUri: _sdTreeRoot)]),
      );
      await settle(c);
      expect(current(c).map((l) => l.id), ['ext_1']);
    });

    test('hides a volume the user already added as a SAF root grant with different hex casing', () async {
      volumes = [_vol('aaaa-1111')];
      final c = makeContainer(
        _FakeRepo([_userLocation(path: _sdTreeRoot, treeUri: _sdTreeRoot)]),
      );
      await settle(c);
      expect(current(c).map((l) => l.id), ['ext_1']);
    });

    test('still lists a volume when only a subfolder of it was added', () async {
      volumes = [_vol('AAAA-1111')];
      final c = makeContainer(
        _FakeRepo([
          _userLocation(path: _sdTreeSubfolder, treeUri: _sdTreeSubfolder),
        ]),
      );
      await settle(c);
      expect(current(c).map((l) => l.id), ['ext_1', 'sysvol_AAAA-1111']);
    });

    test('keeps persisted locations when discovery fails', () async {
      volumesThrow = true;
      final c = makeContainer(_FakeRepo([_userLocation()]));
      await settle(c);
      expect(current(c).map((l) => l.id), ['ext_1']);
    });

    test('drops a volume that is no longer present', () async {
      volumes = [_vol('AAAA-1111')];
      final c = makeContainer(_FakeRepo());
      final notifier = await settle(c);
      expect(current(c), hasLength(1));

      volumes = [];
      await notifier.refreshSystemVolumes();
      expect(current(c), isEmpty);
    });
  });

  group('volId stability', () {
    test('repeated refreshes (app resume) do not renumber a volume', () async {
      // Open tabs are keyed by volId, and BrowserTabsHost closes any tab
      // whose volId disappears from the list -- so a refresh that handed the
      // same card a new id would close its tab on every resume.
      volumes = [_vol('AAAA-1111')];
      final c = makeContainer(_FakeRepo());
      final notifier = await settle(c);
      final first = current(c).single.volId;

      for (var i = 0; i < 3; i++) {
        await notifier.refreshSystemVolumes();
        expect(current(c).single.volId, first);
      }
    });

    test('a volume keeps its volId when another one is unplugged', () async {
      volumes = [_vol('AAAA-1111'), _vol('BBBB-2222')];
      final c = makeContainer(_FakeRepo());
      final notifier = await settle(c);
      final before = {for (final l in current(c)) l.id: l.volId};
      expect(before.values.toSet(), hasLength(2));

      volumes = [_vol('BBBB-2222')];
      await notifier.refreshSystemVolumes();

      expect(current(c).single.volId, before['sysvol_BBBB-2222']);
    });

    test('adding a user location never renumbers an open volume', () async {
      volumes = [_vol('AAAA-1111')];
      final repo = _FakeRepo();
      final c = makeContainer(repo);
      final notifier = await settle(c);
      final sdVolId = current(c).single.volId;

      pickResult = {
        'path': '/storage/emulated/0/Documents',
        'treeUri':
            'content://com.android.externalstorage.documents/tree/primary%3ADocuments',
        'displayName': 'Documents',
      };
      final added = await notifier.promptAndAddLocation();
      await notifier.refreshSystemVolumes();

      final byId = {for (final l in current(c)) l.id: l.volId};
      expect(byId['sysvol_AAAA-1111'], sdVolId);
      expect(byId[added!.id], isNot(sdVolId));
      expect(byId.values.toSet(), hasLength(byId.length));
    });
  });

  group('persistence', () {
    test('system volumes are never written to disk', () async {
      volumes = [_vol('AAAA-1111')];
      final repo = _FakeRepo();
      final c = makeContainer(repo);
      final notifier = await settle(c);

      pickResult = {
        'path': '/storage/emulated/0/Documents',
        'treeUri':
            'content://com.android.externalstorage.documents/tree/primary%3ADocuments',
        'displayName': 'Documents',
      };
      await notifier.promptAndAddLocation();

      expect(repo.stored, hasLength(1));
      expect(repo.stored.any((l) => l.isSystemVolume), isFalse);
    });

    test('system volumes cannot be renamed or removed', () async {
      volumes = [_vol('AAAA-1111')];
      final repo = _FakeRepo();
      final c = makeContainer(repo);
      final notifier = await settle(c);

      await notifier.renameLocation('sysvol_AAAA-1111', 'Renamed');
      await notifier.removeLocation('sysvol_AAAA-1111');

      expect(current(c).single.displayName, 'SD card');
      expect(repo.saveCount, 0);
    });
  });

  group('serialized mutations', () {
    test('a refresh during an add does not drop the new location', () async {
      final repo = _FakeRepo();
      final c = makeContainer(repo);
      final notifier = await settle(c);

      pickResult = {
        'path': '/storage/emulated/0/Documents',
        'treeUri':
            'content://com.android.externalstorage.documents/tree/primary%3ADocuments',
        'displayName': 'Documents',
      };
      // Park the save so the file on "disk" is still stale -- exactly the
      // window in which the app-resume refresh fires after the SAF picker.
      repo.saveGate = Completer<void>();
      final add = notifier.promptAndAddLocation();
      await pumpEventQueue();
      expect(repo.saveCount, 1);

      final refresh = notifier.refreshSystemVolumes();
      await pumpEventQueue();
      repo.saveGate!.complete();

      final added = await add;
      await refresh;

      expect(added, isNotNull);
      expect(current(c).map((l) => l.id), contains(added!.id));
      expect(repo.stored.map((l) => l.id), contains(added.id));
    });

    test('a failed save does not block queued work', () async {
      final repo = _FakeRepo([_userLocation()]);
      final c = makeContainer(repo);
      final notifier = await settle(c);

      repo.failNextSave = true;
      await expectLater(
        notifier.renameLocation('ext_1', 'Renamed'),
        throwsA(isA<StateError>()),
      );

      await notifier.refreshSystemVolumes();
      expect(current(c).map((l) => l.id), ['ext_1']);
    });
  });
}
