import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_edit_controller.dart';

MountedContainer _testContainer() => MountedContainer(
      volId: 1,
      uri: 'file:///vault.hc',
      displayName: 'Vault',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      containerFormat: 'veracrypt',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;
  late ProviderSubscription subscription;
  late VaultEngineEvents engineEvents;

  final testVault = _testContainer();
  final provider = vaultItemEditProvider(1);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listDirectory') {
        return <String>['F|100|1000|existing.password'];
      }
      if (call.method == 'writeFileChunk' ||
          call.method == 'finishWrite' ||
          call.method == 'renameFile') {
        return true;
      }
      return null;
    });

    engineEvents = VaultEngineEvents();
    container = ProviderContainer(
      overrides: [vaultEngineEventsProvider.overrideWithValue(engineEvents)],
    );
    subscription = container.listen(provider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('VaultItemEdit Controller Tests', () {
    test('Initial state is not locked and not saving', () {
      final state = container.read(provider);
      expect(state.isContainerLocked, isFalse);
      expect(state.saving, isFalse);
    });

    test('container locked listener updates isContainerLocked', () {
      engineEvents.notifyContainerLocked(1);
      final state = container.read(provider);
      expect(state.isContainerLocked, isTrue);
    });

    test('save creates new item and makes unique name when collision exists', () async {
      final notifier = container.read(provider.notifier);

      final savedPath = await notifier.save(
        container: testVault,
        type: VaultItemType.password,
        existing: null,
        filePath: null,
        currentDirPath: 'vault_items',
        newTitle: 'existing',
        fieldMap: {'username': 'bob', 'password': '123'},
      );

      expect(savedPath, 'vault_items/existing (1).password');
      expect(container.read(provider).saving, isFalse);
    });

    test('save updates existing item without rename when title matches', () async {
      final notifier = container.read(provider.notifier);
      final existingItem = VaultItem(
        id: '123',
        type: VaultItemType.password,
        title: 'existing',
        fields: {'username': 'bob'},
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final savedPath = await notifier.save(
        container: testVault,
        type: VaultItemType.password,
        existing: existingItem,
        filePath: 'vault_items/existing.password',
        currentDirPath: 'vault_items',
        newTitle: 'existing',
        fieldMap: {'username': 'bob_updated'},
      );

      expect(savedPath, 'vault_items/existing.password');
    });

    test('save renames existing item when title changes', () async {
      final notifier = container.read(provider.notifier);
      final existingItem = VaultItem(
        id: '123',
        type: VaultItemType.password,
        title: 'old_title',
        fields: {'username': 'bob'},
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final savedPath = await notifier.save(
        container: testVault,
        type: VaultItemType.password,
        existing: existingItem,
        filePath: 'vault_items/old_title.password',
        currentDirPath: 'vault_items',
        newTitle: 'new_title',
        fieldMap: {'username': 'bob'},
      );

      expect(savedPath, 'vault_items/new_title.password');
    });
  });
}
