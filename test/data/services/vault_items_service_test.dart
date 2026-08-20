import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';

/// Fakes the handful of [VaultExplorerApi] file-IO calls
/// [VaultItemsService.loadItem]/[VaultItemsService.saveItem] make
/// (getFileSize/readFileChunk/deleteFile/writeFileChunk/finishWrite/
/// renameFile), mirroring the fake-per-test-file pattern already used by
/// [hash_verifier_service_test.dart] and
/// [keyfile_passphrase_generator_service_test.dart] rather than a real
/// mounted container or platform channel.
///
/// Backed by a plain in-memory `Map<String, Uint8List>` keyed by virtual
/// path, plus independently-toggleable failure switches for each of the
/// three write-path calls, so a test can make any single step of
/// saveItem's write-tmp -> finish -> delete-original -> rename sequence
/// fail without touching the others -- exactly what's needed to check
/// that a failure partway through never corrupts or loses the
/// already-saved original.
class _FakeVaultItemsApi extends VaultExplorerApi {
  final Map<String, Uint8List> files;
  bool failWriteFileChunk = false;
  bool failFinishWrite = false;
  bool failRenameFile = false;
  final List<String> calls = [];

  _FakeVaultItemsApi([Map<String, Uint8List>? initial]) : files = initial ?? {};

  @override
  Future<int> getFileSize(MountedContainer container, String fileName) async {
    return files[fileName]?.length ?? 0;
  }

  @override
  Future<Uint8List?> readFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    int length,
  ) async {
    final bytes = files[fileName];
    if (bytes == null) return null;
    final end = (offset + length).clamp(0, bytes.length);
    return Uint8List.sublistView(bytes, offset.clamp(0, bytes.length), end);
  }

  @override
  Future<bool> deleteFile(MountedContainer container, String fileName) async {
    calls.add('delete:$fileName');
    files.remove(fileName);
    return true;
  }

  @override
  Future<bool> writeFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    Uint8List data,
  ) async {
    calls.add('write:$fileName');
    if (failWriteFileChunk) return false;
    // offset is always 0 for VaultItemsService's usage (one-shot JSON blob).
    files[fileName] = data;
    return true;
  }

  @override
  Future<bool> finishWrite(MountedContainer container, String fileName) async {
    calls.add('finish:$fileName');
    return !failFinishWrite;
  }

  @override
  Future<bool> renameFile(
    MountedContainer container,
    String oldPath,
    String newPath,
  ) async {
    calls.add('rename:$oldPath->$newPath');
    if (failRenameFile) return false;
    final bytes = files.remove(oldPath);
    if (bytes != null) files[newPath] = bytes;
    return true;
  }
}

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

  tearDown(() => vaultExplorerApi = const VaultExplorerApi());

  final service = VaultItemsService.instance;
  final container = _container();

  group('saveItem then loadItem', () {
    test('round-trips every field, including type and bookmark', () async {
      final api = _FakeVaultItemsApi();
      vaultExplorerApi = api;
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
      final api = _FakeVaultItemsApi();
      vaultExplorerApi = api;

      await service.saveItem(container, 'items/bank.json', _item());

      expect(api.files.containsKey('items/bank.json'), isTrue);
      expect(api.files.containsKey('items/bank.json.tmp'), isFalse);
      // delete-tmp-before-write, write, finish, delete-original, rename --
      // in that order.
      expect(api.calls, [
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
      vaultExplorerApi = _FakeVaultItemsApi();

      final loaded = await service.loadItem(container, 'items/missing.json');

      expect(loaded, isNull);
    });

    test('returns null rather than throwing on corrupt (non-JSON) bytes', () async {
      vaultExplorerApi = _FakeVaultItemsApi({
        'items/corrupt.json': Uint8List.fromList(utf8.encode('not valid { json')),
      });

      final loaded = await service.loadItem(container, 'items/corrupt.json');

      expect(loaded, isNull);
    });

    test('returns null rather than throwing on valid JSON missing required fields', () async {
      // 'id' is required by VaultItem.fromJson (`j['id'] as String` with no
      // fallback) -- omitting it should surface as a clean null, not a
      // crash that takes the whole item list down with it.
      vaultExplorerApi = _FakeVaultItemsApi({
        'items/no_id.json': Uint8List.fromList(utf8.encode(jsonEncode({'title': 'Oops'}))),
      });

      final loaded = await service.loadItem(container, 'items/no_id.json');

      expect(loaded, isNull);
    });
  });

  group('saveItem failure paths leave the original item intact', () {
    test('writeFileChunk failure: returns false, original file untouched', () async {
      final api = _FakeVaultItemsApi({
        'items/bank.json': Uint8List.fromList(utf8.encode(jsonEncode(_item(title: 'Original').toJson()))),
      });
      api.failWriteFileChunk = true;
      vaultExplorerApi = api;

      final saved = await service.saveItem(container, 'items/bank.json', _item(title: 'Updated'));

      expect(saved, isFalse);
      final loaded = await service.loadItem(container, 'items/bank.json');
      expect(loaded?.title, 'Original', reason: 'a failed write must not touch the pre-existing item');
    });

    test('finishWrite failure: returns false, original file untouched', () async {
      final api = _FakeVaultItemsApi({
        'items/bank.json': Uint8List.fromList(utf8.encode(jsonEncode(_item(title: 'Original').toJson()))),
      });
      api.failFinishWrite = true;
      vaultExplorerApi = api;

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
        final api = _FakeVaultItemsApi({
          'items/bank.json': Uint8List.fromList(utf8.encode(jsonEncode(_item(title: 'Original').toJson()))),
        });
        api.failRenameFile = true;
        vaultExplorerApi = api;

        final saved = await service.saveItem(container, 'items/bank.json', _item(title: 'Updated'));

        expect(saved, isFalse);
        expect(api.files.containsKey('items/bank.json'), isFalse);
        expect(api.files.containsKey('items/bank.json.tmp'), isTrue);
        final strandedJson = jsonDecode(utf8.decode(api.files['items/bank.json.tmp']!));
        expect(strandedJson['title'], 'Updated');
      },
    );
  });
}
