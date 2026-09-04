import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/decoy/local/local_destination_picker_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory subDir;
  late ProviderContainer container;
  ProviderSubscription<LocalDestinationPickerState>? subscription;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_dest_picker_test_');
    subDir = Directory(p.join(tempDir.path, 'SubFolder'))..createSync();
    Directory(p.join(subDir.path, 'NestedFolder')).createSync();

    container = ProviderContainer();
  });

  tearDown(() async {
    subscription?.close();
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('LocalDestinationPickerController Tests', () {
    test('initializes and lists root directory folders', () async {
      final provider = localDestinationPickerProvider('Root', tempDir.path);
      final completer = Completer<void>();
      subscription = container.listen(
        provider,
        (previous, next) {
          if (!next.loading && !completer.isCompleted) {
            completer.complete();
          }
        },
        fireImmediately: true,
      );

      await completer.future;

      final state = container.read(provider);
      expect(state.currentPath, tempDir.path);
      expect(state.folders, hasLength(1));
      expect(state.folders.first.name, 'SubFolder');
    });

    test('enter and jumpTo navigate through local directory stack', () async {
      final provider = localDestinationPickerProvider('Root', tempDir.path);
      final completer = Completer<void>();
      subscription = container.listen(
        provider,
        (previous, next) {
          if (!next.loading && !completer.isCompleted) {
            completer.complete();
          }
        },
        fireImmediately: true,
      );

      final controller = container.read(provider.notifier);
      await completer.future;

      const subEntry = RawEntry(name: 'SubFolder', isDir: true, sizeBytes: 0, modifiedSecs: 0);
      controller.enter(subEntry);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(provider).currentPath, subDir.path);
      expect(container.read(provider).stack, hasLength(2));

      controller.jumpTo(0);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(provider).currentPath, tempDir.path);
      expect(container.read(provider).stack, hasLength(1));
    });
  });
}