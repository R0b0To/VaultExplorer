import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';

/// Shared in-memory backing store for [_FakeFileIoApi]/[_FakeLifecycleApi],
/// keyed by virtual path, plus independently-toggleable failure switches for
/// each of the three write-path calls, so a test can make any single step of
/// saveItem's write-tmp -> finish -> delete-original -> rename sequence fail
/// without touching the others -- exactly what's needed to check that a
/// failure partway through never corrupts or loses the already-saved
/// original.
class _FakeEngineState {
  final Map<String, Uint8List> files;
  bool failWriteFileChunk = false;
  bool failFinishWrite = false;
  bool failRenameFile = false;
  final List<String> calls = [];

  _FakeEngineState([Map<String, Uint8List>? initial]) : files = initial ?? {};
}

/// Fakes the handful of [VaultFileIoApi] calls
/// [VaultItemsService.loadItem]/[VaultItemsService.saveItem] make
/// (getFileSize/readFileChunk/deleteFile/writeFileChunk/renameFile).
///
/// VaultItemsService takes its VaultFileIoApi/VaultLifecycleApi slices via
/// constructor injection (see vault_items_service.dart) rather than the old
/// mutable `vaultExplorerApi` global, so the fake now extends the slice
/// class directly and gets wired in through VaultItemsService's constructor
/// instead of that global -- a real mounted container or platform channel
/// is never touched. The dummy MethodChannel passed to `super` is never
/// invoked since every method that would use it is overridden below.
class _FakeFileIoApi extends VaultFileIoApi {
  final _FakeEngineState state;
  _FakeFileIoApi(this.state) : super(const MethodChannel('test'));

  @override
  Future<int> getFileSize(MountedContainer container, String fileName) async {
    return state.files[fileName]?.length ?? 0;
  }

  @override
  Future<Uint8List?> readFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    int length,
  ) async {
    final bytes = state.files[fileName];
    if (bytes == null) return null;
    final end = (offset + length).clamp(0, bytes.length);
    return Uint8List.sublistView(bytes, offset.clamp(0, bytes.length), end);
  }

  @override
  Future<bool> deleteFile(MountedContainer container, String fileName) async {
    state.calls.add('delete:$fileName');
    state.files.remove(fileName);
    return true;
  }

  @override
  Future<bool> writeFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    Uint8List data,
  ) async {
    state.calls.add('write:$fileName');
    if (state.failWriteFileChunk) return false;
    // offset is always 0 for VaultItemsService's usage (one-shot JSON blob).
    state.files[fileName] = data;
    return true;
  }

  @override
  Future<bool> renameFile(
    MountedContainer container,
    String oldPath,
    String newPath,
  ) async {
    state.calls.add('rename:$oldPath->$newPath');
    if (state.failRenameFile) return false;
    final bytes = state.files.remove(oldPath);
    if (bytes != null) state.files[newPath] = bytes;
    return true;
  }
}

/// Fakes [VaultLifecycleApi.finishWrite] against the same shared
/// [_FakeEngineState] as [_FakeFileIoApi] -- see its doc comment.
class _FakeLifecycleApi extends VaultLifecycleApi {
  final _FakeEngineState state;
  _FakeLifecycleApi(this.state) : super(const MethodChannel('test'), VaultEngineEvents());

  @override
  Future<bool> finishWrite(MountedContainer container, String fileName) async {
    state.calls.add('finish:$fileName');
    return !state.failFinishWrite;
  }
}

VaultItemsService _service(_FakeEngineState state) =>
    VaultItemsService(_FakeFileIoApi(state), _FakeLifecycleApi(state));

MountedContainer _container() => MountedContainer(
      uri: 'file:///test.vault',
      displayName: 'Test Vault',
      volId: 1,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 100000000,
      freeSpace: 50000000,
    );

VaultItem _item({String id = 'item-1', String title = 'My Bank'}) => VaultItem(
      id: id,
      type: VaultItemType.bankAccount,
      title: title,
      fields: {'bank_name': 'First National', 'account_number': '000123456'},
      createdAt: DateTime(2026, 1, 1, 9),
      updatedAt: DateTime(2026, 1, 1, 9),
      bookmark: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final container = _container();

  group('saveItem then loadItem', () {
    test('round-trips every field, including type and bookmark', () async {
      final service = _service(_FakeEngineState());
      final item = _item();

      final saved = await service.saveItem(container, 'items/bank.json', item);
      expect(saved, isTrue);

      final loaded = await service.loadItem(container, 'items/bank.json');
      expect(loaded, isNotNull);
      expect(loaded!.id, item.id);
      expect(loaded.type, VaultItemType.bankAccount);
      expect(loaded.title, 'My Bank');
      expect(loaded.fields, item.fields);
      expect(loaded.bookmark, isTrue);
      expect(loaded.createdAt, item.createdAt);
      expect(loaded.updatedAt, item.updatedAt);
    });

    test('writes via a .tmp path and only leaves the final path behind', () async {
      final state = _FakeEngineState();
      final service = _service(state);

      await service.saveItem(container, 'items/bank.json', _item());

      expect(state.files.containsKey('items/bank.json'), isTrue);
      expect(state.files.containsKey('items/bank.json.tmp'), isFalse);
      // delete-tmp-before-write, write, finish, delete-original, rename --
      // in that order.
      expect(state.calls, [
        'delete:items/bank.json.tmp',
        'write:items/bank.json.tmp',
        'finish:items/bank.json.tmp',
        'delete:items/bank.json',
        'rename:items/bank.json.tmp->items/bank.json',
      ]);
    });
  });

  group('loadItem error handling', () {
    test('returns null for a path with no file (size 0)', () async {
      final service = _service(_FakeEngineState());

      final loaded = await service.loadItem(container, 'items/missing.json');

      expect(loaded, isNull);
    });

    test('returns null rather than throwing on corrupt (non-JSON) bytes', () async {
      final service = _service(_FakeEngineState({
        'items/corrupt.json': Uint8List.fromList(utf8.encode('not valid { json')),
      }));

      final loaded = await service.loadItem(container, 'items/corrupt.json');

      expect(loaded, isNull);
    });

    test('returns null rather than throwing on valid JSON missing required fields', () async {
      // 'id' is required by VaultItem.fromJson (`j['id'] as String` with no
      // fallback) -- omitting it should surface as a clean null, not a
      // crash that takes the whole item list down with it.
      final service = _service(_FakeEngineState({
        'items/no_id.json': Uint8List.fromList(utf8.encode(jsonEncode({'title': 'Oops'}))),
      }));

      final loaded = await service.loadItem(container, 'items/no_id.json');

      expect(loaded, isNull);
    });
  });

  group('saveItem failure paths leave the original item intact', () {
    test('writeFileChunk failure: returns false, original file untouched', () async {
      final state = _FakeEngineState({
        'items/bank.json': Uint8List.fromList(utf8.encode(jsonEncode(_item(title: 'Original').toJson()))),
      });
      state.failWriteFileChunk = true;
      final service = _service(state);

      final saved = await service.saveItem(container, 'items/bank.json', _item(title: 'Updated'));

      expect(saved, isFalse);
      final loaded = await service.loadItem(container, 'items/bank.json');
      expect(loaded?.title, 'Original', reason: 'a failed write must not touch the pre-existing item');
    });

    test('finishWrite failure: returns false, original file untouched', () async {
      final state = _FakeEngineState({
        'items/bank.json': Uint8List.fromList(utf8.encode(jsonEncode(_item(title: 'Original').toJson()))),
      });
      state.failFinishWrite = true;
      final service = _service(state);

      final saved = await service.saveItem(container, 'items/bank.json', _item(title: 'Updated'));

      expect(saved, isFalse);
      final loaded = await service.loadItem(container, 'items/bank.json');
      expect(loaded?.title, 'Original', reason: 'a failed finishWrite must not touch the pre-existing item');
    });

    test(
      'renameFile failure: returns false, but the original was already deleted -- '
      'documents a real gap, not a regression introduced by this test',
      () async {
        // saveItem() calls deleteFile(path) *before* renameFile(tmp, path)
        // (see the call-order test above). If renameFile then fails, the
        // original is already gone and the new content is stranded under
        // the .tmp name rather than at `path` -- saveItem still (correctly)
        // reports failure via its return value, but the item is not
        // recoverable at its expected path without also recovering
        // `path.tmp`. This test pins that actual behavior down so it's
        // visible rather than silent; it is not asserting this is fine,
        // only that this is what the current code does.
        final state = _FakeEngineState({
          'items/bank.json': Uint8List.fromList(utf8.encode(jsonEncode(_item(title: 'Original').toJson()))),
        });
        state.failRenameFile = true;
        final service = _service(state);

        final saved = await service.saveItem(container, 'items/bank.json', _item(title: 'Updated'));

        expect(saved, isFalse);
        expect(state.files.containsKey('items/bank.json'), isFalse);
        expect(state.files.containsKey('items/bank.json.tmp'), isTrue);
        final strandedJson = jsonDecode(utf8.decode(state.files['items/bank.json.tmp']!));
        expect(strandedJson['title'], 'Updated');
      },
    );
  });
}