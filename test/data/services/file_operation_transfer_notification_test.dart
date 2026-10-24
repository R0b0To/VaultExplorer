import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_channel.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

MountedContainer _container(int volId) => MountedContainer(
  uri: 'content://test-container-$volId',
  displayName: 'Vault $volId',
  volId: volId,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 100000000,
  freeSpace: 50000000,
);

/// Lets a copy/move start and stop without touching the platform: listing the
/// destination fails, so the operation ends as "failed" straight away. A
/// finished operation must notify other views whatever its outcome.
class _FailingListingFileIoApi extends VaultFileIoApi {
  _FailingListingFileIoApi() : super(const MethodChannel('test/file-operation'));

  @override
  Future<void> beginBatchWrite(MountedContainer container) async {}

  @override
  Future<void> endBatchWrite(MountedContainer container) async {}

  @override
  Future<void> clearCopyState(int opId) async {}

  @override
  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async => throw StateError('listing failed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = AppLocalizationsEn();
  late FileOperationService opSvc;
  late List<VolumeContentChange> changes;

  setUp(() {
    final engineEvents = VaultEngineEvents()
      ..registerHandler(kVaultEngineChannel);
    opSvc = FileOperationService.withEngineApis(
      engineEvents: engineEvents,
      fileIoApi: _FailingListingFileIoApi(),
      lifecycleApi: VaultLifecycleApi(kVaultEngineChannel, engineEvents),
    );
    changes = <VolumeContentChange>[];
    opSvc.addVolumeContentChangedListener(changes.add);
  });

  FileOperation transfer({
    required bool isCut,
    required int sourceVolId,
    required int destVolId,
  }) => opSvc.enqueue(
    isCut: isCut,
    source: _container(sourceVolId),
    dest: _container(destVolId),
    destDirPath: 'sub',
    items: const [ClipboardItem(path: 'file1.txt', isDir: false)],
    l10n: l10n,
  );

  group('copy/move completion notifies views of the changed volumes', () {
    test('a move within one volume notifies it once, even though it failed', () async {
      final op = transfer(isCut: true, sourceVolId: 1, destVolId: 1);
      await pumpEventQueue();

      expect(op.isTransfer, isTrue);
      expect(changes.map((c) => c.volId), [1]);
      expect(changes.single.opId, op.id);
    });

    test('a move between volumes notifies the destination, then the source', () async {
      final op = transfer(isCut: true, sourceVolId: 1, destVolId: 2);
      await pumpEventQueue();

      expect(changes.map((c) => c.volId), [2, 1]);
      expect(changes.every((c) => c.opId == op.id), isTrue);
    });

    test('a copy leaves the source volume alone', () async {
      transfer(isCut: false, sourceVolId: 1, destVolId: 2);
      await pumpEventQueue();

      expect(changes.map((c) => c.volId), [2]);
    });
  });
}
