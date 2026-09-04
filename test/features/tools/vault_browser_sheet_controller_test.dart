import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet_controller.dart';

MountedContainer _testContainer({required int volId, required String uri, required String name}) =>
    MountedContainer(
      volId: volId,
      uri: uri,
      displayName: name,
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

  final vault1 = _testContainer(volId: 1, uri: 'file:///v1.hc', name: 'Vault 1');
  final vault2 = _testContainer(volId: 2, uri: 'file:///v2.hc', name: 'Vault 2');

  final params = VaultBrowserParams(
    mountedContainers: [vault1, vault2],
    initialContainer: vault1,
    initialPath: '',
  );
  final provider = vaultBrowserControllerProvider(params);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listDirectory') {
        return <String>['F|100|1000|file.txt', 'D|0|1000|Docs'];
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

  group('VaultBrowserController Navigation Tests', () {
    test('initializes at root path with initial container', () {
      final state = container.read(provider);

      expect(state.selectedContainer.volId, 1);
      expect(state.currentPath, '');
      expect(state.pathStack, ['']);
    });

    test('navigateToFolder pushes subfolder and navigateUp pops it', () {
      final controller = container.read(provider.notifier);

      controller.navigateToFolder('Docs');
      var state = container.read(provider);
      expect(state.currentPath, 'Docs');
      expect(state.pathStack, ['', 'Docs']);

      controller.navigateToFolder('Invoices');
      state = container.read(provider);
      expect(state.currentPath, 'Docs/Invoices');
      expect(state.pathStack, ['', 'Docs', 'Docs/Invoices']);

      controller.navigateUp();
      state = container.read(provider);
      expect(state.currentPath, 'Docs');
      expect(state.pathStack, ['', 'Docs']);

      controller.navigateUp();
      state = container.read(provider);
      expect(state.currentPath, '');
      expect(state.pathStack, ['']);
    });

    test('jumpTo navigates directly to indexed ancestor segment', () {
      final controller = container.read(provider.notifier);

      controller.navigateToFolder('Docs');
      controller.navigateToFolder('Work');
      controller.navigateToFolder('2026');
      expect(container.read(provider).pathStack, ['', 'Docs', 'Docs/Work', 'Docs/Work/2026']);

      // Jump back to 'Docs' (index 1)
      controller.jumpTo(1);
      final state = container.read(provider);
      expect(state.currentPath, 'Docs');
      expect(state.pathStack, ['', 'Docs']);
    });

    test('switchVault switches active container and resets path stack to root', () {
      final controller = container.read(provider.notifier);

      controller.navigateToFolder('Docs');
      expect(container.read(provider).pathStack.length, 2);

      controller.switchVault(vault2);
      final state = container.read(provider);
      expect(state.selectedContainer.volId, 2);
      expect(state.currentPath, '');
      expect(state.pathStack, ['']);
    });
  });
}