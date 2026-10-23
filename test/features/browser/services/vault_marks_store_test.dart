import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/features/browser/services/vault_marks_store.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_marks_service.dart';

// Where a container's bookmarks and pins are kept, and what happens when that
// place is missing, damaged, read-only or unreachable.

VaultMarksStore _make(_MemIo io, _MemSecure secure, File localFile) =>
    VaultMarksStore(
      io: io,
      secure: secure,
      local: DecoyLocalMarksService(fileLocator: () async => localFile),
    );

MountedContainer _container({
  int volId = 1,
  String uri = 'file:///vault.hc',
  bool readOnly = false,
}) => MountedContainer(
  uri: uri,
  displayName: 'Vault',
  volId: volId,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000,
  freeSpace: 500,
  readOnly: readOnly,
);

const _a = VaultBookmark('Docs/a.txt', isDir: false);
const _b = VaultBookmark('Photos', isDir: true);

/// A vault's files in memory: directories, whole-file reads and writes.
class _MemIo implements VaultFileIoApi {
  final Map<String, Uint8List> files = {};
  final Set<String> dirs = {};
  final List<String> writes = [];
  Object? listError;
  Object? writeError;
  bool writeSucceeds = true;

  @override
  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async {
    if (listError != null) throw listError!;
    if (!dirs.contains(dirPath)) return null;
    final prefix = '$dirPath/';
    return [
      for (final path in files.keys)
        if (path.startsWith(prefix) &&
            !path.substring(prefix.length).contains('/'))
          RawEntry(
            name: path.substring(prefix.length),
            isDir: false,
            sizeBytes: files[path]!.length,
            modifiedSecs: 0,
          ).raw,
    ];
  }

  @override
  Future<Uint8List?> readWholeFile(
    MountedContainer container,
    String fileName,
  ) async => files[fileName];

  @override
  Future<bool> createDirectory(
    MountedContainer container,
    String dirPath,
  ) async {
    dirs.add(dirPath);
    return true;
  }

  @override
  Future<bool> writeWholeFile(
    MountedContainer container,
    String fileName,
    Uint8List bytes,
  ) async {
    if (writeError != null) throw writeError!;
    writes.add(fileName);
    if (!writeSucceeds) return false;
    files[fileName] = bytes;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemSecure extends AppSecureStorage {
  final Map<String, String> data = {};
  bool writeSucceeds = true;

  @override
  Future<String?> read({required String key}) async => data[key];

  @override
  Future<bool> writeVerified({
    required String key,
    required String value,
  }) async {
    if (!writeSucceeds) return false;
    data[key] = value;
    return true;
  }
}

void registerVaultMarksStoreScenarios(
  VaultMarksStore Function(_MemIo io, _MemSecure secure, File localFile) make,
) {
  late Directory tmp;
  late _MemIo io;
  late _MemSecure secure;
  late File localFile;
  late VaultMarksStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('vault_marks_store_test_');
    io = _MemIo();
    secure = _MemSecure();
    localFile = File('${tmp.path}/decoy_local_marks.json');
    store = make(io, secure, localFile);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('each kind of container keeps its marks in the right place', () {
    expect(
      VaultMarksStore.locationFor(_container()),
      VaultMarksLocation.inVault,
    );
    expect(
      VaultMarksStore.locationFor(_container(readOnly: true)),
      VaultMarksLocation.thisDevice,
    );
    expect(
      VaultMarksStore.locationFor(_container(volId: -1)),
      VaultMarksLocation.phoneStorage,
    );
  });

  group('a writable vault', () {
    test('nothing stored yet loads as empty, and loading writes nothing',
        () async {
      expect((await store.load(_container())).isEmpty, isTrue);
      io.dirs.add('.vaultexplorer'); // folder exists, file does not
      expect((await store.load(_container())).isEmpty, isTrue);
      expect(io.writes, isEmpty);
    });

    test('saves inside the vault and loads back what was saved', () async {
      final marks = VaultMarks(
        bookmarks: const [_a, _b],
        pinnedPaths: const {'Docs/a.txt'},
      );

      expect(await store.save(_container(), marks), isTrue);

      expect(io.dirs, contains('.vaultexplorer'));
      expect(io.writes, ['.vaultexplorer/marks.json']);
      expect(await store.load(_container()), marks);
      // Nothing about the vault leaks into device storage.
      expect(secure.data, isEmpty);
      expect(localFile.existsSync(), isFalse);
    });

    test('the kind of each bookmark is stored with it', () async {
      await store.save(_container(), VaultMarks().withBookmarks([_a, _b]));

      final json = jsonDecode(
        utf8.decode(io.files['.vaultexplorer/marks.json']!),
      ) as Map<String, dynamic>;
      expect(json['bookmarks'], [
        {'path': 'Docs/a.txt', 'dir': false},
        {'path': 'Photos', 'dir': true},
      ]);
    });

    test('an unparseable file counts as empty, and a save replaces it',
        () async {
      io.dirs.add('.vaultexplorer');
      io.files['.vaultexplorer/marks.json'] = Uint8List.fromList(
        utf8.encode('{not json'),
      );

      expect((await store.load(_container())).isEmpty, isTrue);
      await store.save(_container(), VaultMarks().withBookmarks([_a]));
      expect((await store.load(_container())).bookmarkPaths, ['Docs/a.txt']);
    });

    test('if the vault cannot be reached, load throws instead of pretending '
        'there is nothing', () async {
      io.listError = StateError('vault went away');
      await expectLater(store.load(_container()), throwsStateError);
    });

    test('a write that fails or throws is reported, not raised', () async {
      io.writeSucceeds = false;
      expect(await store.save(_container(), VaultMarks()), isFalse);

      io
        ..writeSucceeds = true
        ..writeError = StateError('disk full');
      expect(await store.save(_container(), VaultMarks()), isFalse);
    });
  });

  group('a read-only vault', () {
    final readOnly = _container(readOnly: true);

    test('saves on this device and never writes to the vault', () async {
      final marks = VaultMarks().withBookmarks([_b]);

      expect(await store.save(readOnly, marks), isTrue);

      expect(io.writes, isEmpty);
      expect(io.dirs, isEmpty);
      expect(secure.data.keys.single, startsWith('vc2_marks_'));
      expect(await store.load(readOnly), marks);
    });

    test('shows the vault\'s own marks until the first change here', () async {
      io.dirs.add('.vaultexplorer');
      io.files['.vaultexplorer/marks.json'] = Uint8List.fromList(
        utf8.encode(jsonEncode(VaultMarks().withBookmarks([_a]).toJson())),
      );

      expect((await store.load(readOnly)).bookmarkPaths, ['Docs/a.txt']);

      await store.save(readOnly, VaultMarks().withBookmarks([_b]));
      expect((await store.load(readOnly)).bookmarkPaths, ['Photos']);
    });

    test('removing the last bookmark stays removed instead of falling back '
        'to the vault\'s copy', () async {
      io.dirs.add('.vaultexplorer');
      io.files['.vaultexplorer/marks.json'] = Uint8List.fromList(
        utf8.encode(jsonEncode(VaultMarks().withBookmarks([_a]).toJson())),
      );

      await store.save(readOnly, VaultMarks.empty);

      expect((await store.load(readOnly)).isEmpty, isTrue);
    });

    test('a failed device write is reported', () async {
      secure.writeSucceeds = false;
      expect(await store.save(readOnly, VaultMarks().withBookmarks([_a])),
          isFalse);
    });
  });

  group('phone storage', () {
    final phone = _container(volId: -1, uri: '/storage/emulated/0');
    final sdCard = _container(volId: -2, uri: '/storage/ABCD-1234');

    test('each location keeps its own marks', () async {
      await store.save(phone, VaultMarks().withBookmarks([_a]));
      await store.save(sdCard, VaultMarks().withBookmarks([_b]));

      expect((await store.load(phone)).bookmarkPaths, ['Docs/a.txt']);
      expect((await store.load(sdCard)).bookmarkPaths, ['Photos']);
      // Not in a vault, not in the Keystore.
      expect(io.writes, isEmpty);
      expect(secure.data, isEmpty);
    });

    test('marks survive a restart', () async {
      await store.save(phone, VaultMarks().withBookmarks([_a]));

      final afterRestart = make(_MemIo(), _MemSecure(), localFile);
      expect((await afterRestart.load(phone)).bookmarkPaths, ['Docs/a.txt']);
    });

    test('emptying a location removes its entry and leaves the others',
        () async {
      await store.save(phone, VaultMarks().withBookmarks([_a]));
      await store.save(sdCard, VaultMarks().withBookmarks([_b]));

      await store.save(phone, VaultMarks.empty);

      final stored = jsonDecode(localFile.readAsStringSync()) as Map;
      expect(stored.keys, ['/storage/ABCD-1234']);
      expect((await store.load(sdCard)).bookmarkPaths, ['Photos']);
    });

    test('concurrent saves from two locations do not lose either', () async {
      await Future.wait([
        store.save(phone, VaultMarks().withBookmarks([_a])),
        store.save(sdCard, VaultMarks().withBookmarks([_b])),
      ]);

      expect((await store.load(phone)).bookmarkPaths, ['Docs/a.txt']);
      expect((await store.load(sdCard)).bookmarkPaths, ['Photos']);
    });

    test('a damaged file loads as empty and can be written again', () async {
      localFile.writeAsStringSync('][');

      expect((await store.load(phone)).isEmpty, isTrue);
      expect(await store.save(phone, VaultMarks().withBookmarks([_a])), isTrue);
      expect((await store.load(phone)).bookmarkPaths, ['Docs/a.txt']);
    });
  });
}

void main() {
  registerVaultMarksStoreScenarios(_make);
}
