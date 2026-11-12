import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_operations_controller.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  final l10n = AppLocalizationsEn();

  final destContainer = MountedContainer(
    volId: 1,
    displayName: 'Dest Vault',
    uri: 'content://vault1',
    readOnly: false,
    rootFiles: const [],
    mountedAt: DateTime(2026, 1, 1),
    totalSpace: 100000000,
    freeSpace: 50000000,
  );

  final srcContainer = MountedContainer(
    volId: 2,
    displayName: 'Source Vault',
    uri: 'content://vault2',
    readOnly: false,
    rootFiles: const [],
    mountedAt: DateTime(2026, 1, 1),
    totalSpace: 100000000,
    freeSpace: 50000000,
  );

  late ProviderContainer providerContainer;

  setUp(() {
    providerContainer = ProviderContainer();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    providerContainer.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('FileBrowserOperationsController.pasteStandardTransfer', () {
    test('returns null without showing conflict sheet if all source items are missing', () async {
      // Mock: getFileSize returns -1 (missing), listDirectory returns existing file in dest
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getFileSize') return -1;
            if (call.method == 'listDirectory') {
              return ['F|100|0|test.txt'];
            }
            return null;
          });

      var conflictPrompted = false;
      final controller = providerContainer.read(fileBrowserOperationsControllerProvider);

      final op = await controller.pasteStandardTransfer(
        destContainer: destContainer,
        srcContainer: srcContainer,
        destDirPath: '',
        items: const [ClipboardItem(path: 'test.txt', isDir: false)],
        isCut: false,
        isCrossContainer: true,
        resolveConflicts: (conflicts) async {
          conflictPrompted = true;
          return null;
        },
        l10n: l10n,
      );

      expect(op, isNull);
      expect(conflictPrompted, isFalse, reason: 'Missing items must not trigger conflict resolution');
    });

    test('prunes missing items and only prompts conflict for surviving items', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getFileSize') {
              final fileName = (call.arguments as Map)['fileName'] as String;
              if (fileName == 'alive.txt') return 100;
              return -1; // 'deleted.txt' is missing
            }
            if (call.method == 'listDirectory') {
              // Destination has both names
              return ['F|100|0|alive.txt', 'F|100|0|deleted.txt'];
            }
            return null;
          });

      List<ConflictEntry>? receivedConflicts;
      final controller = providerContainer.read(fileBrowserOperationsControllerProvider);

      await controller.pasteStandardTransfer(
        destContainer: destContainer,
        srcContainer: srcContainer,
        destDirPath: '',
        items: const [
          ClipboardItem(path: 'deleted.txt', isDir: false),
          ClipboardItem(path: 'alive.txt', isDir: false),
        ],
        isCut: false,
        isCrossContainer: true,
        resolveConflicts: (conflicts) async {
          receivedConflicts = conflicts;
          return {for (final c in conflicts) c.item.name: ConflictResolution.skip};
        },
        l10n: l10n,
      );

      expect(receivedConflicts, isNotNull);
      expect(receivedConflicts!.length, 1);
      expect(receivedConflicts!.single.item.name, 'alive.txt',
          reason: 'Only surviving item should appear in conflicts');
    });
  });
}
