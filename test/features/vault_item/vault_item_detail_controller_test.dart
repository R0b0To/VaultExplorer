import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_detail_controller.dart';

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

  final testVault = _testContainer();
  final initialItem = VaultItem(
    id: 'item_1',
    type: VaultItemType.password,
    title: 'Secret Login',
    fields: {'username': 'alice', 'password': 'hunter2Password'},
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    bookmark: false,
  );

  final provider = vaultItemDetailProvider(1, '/items/login.json', initialItem);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'deleteFile' ||
          call.method == 'writeFileChunk' ||
          call.method == 'finishWrite' ||
          call.method == 'renameFile') {
        return true;
      }
      return null;
    });

    container = ProviderContainer();
    subscription = container.listen(provider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('VaultItemDetailController Tests', () {
    test('initializes with item and empty revealed map', () {
      final state = container.read(provider);

      expect(state.item.title, 'Secret Login');
      expect(state.filePath, '/items/login.json');
      expect(state.isContainerLocked, isFalse);
      expect(state.revealed['password'], isNot(isTrue));
    });

    test('toggleRevealed toggles field key visibility in revealed map', () {
      final controller = container.read(provider.notifier);

      controller.toggleRevealed('password');
      expect(container.read(provider).revealed['password'], isTrue);

      controller.toggleRevealed('password');
      expect(container.read(provider).revealed['password'], isFalse);
    });

    test('delete calls platform channel to remove item file', () async {
      final controller = container.read(provider.notifier);

      await expectLater(controller.delete(testVault), completes);
    });

    test('toggleBookmark flips bookmark status', () async {
      final controller = container.read(provider.notifier);

      await controller.toggleBookmark(testVault);
      expect(container.read(provider).item.bookmark, isTrue);

      await controller.toggleBookmark(testVault);
      expect(container.read(provider).item.bookmark, isFalse);
    });
  });
}