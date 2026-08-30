import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/features/decoy/local/local_text_viewer_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File testFile;
  late ProviderContainer container;
  ProviderSubscription<LocalTextViewerState>? subscription;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_text_viewer_test_');
    testFile = File(p.join(tempDir.path, 'note.txt'))..writeAsStringSync('Local plaintext content');

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

  group('LocalTextViewerController Tests', () {
    test('initializes and reads plaintext from filesystem', () async {
      final provider = localTextViewerProvider(testFile.path);
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
      expect(state.loadedText, 'Local plaintext content');
      expect(state.loading, isFalse);
      expect(state.tooLarge, isFalse);
    });

    test('save writes modified content back to local file', () async {
      final provider = localTextViewerProvider(testFile.path);
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

      final ok = await controller.save(testFile.path, 'Modified content');

      expect(ok, isTrue);
      expect(testFile.readAsStringSync(), 'Modified content');
    });
  });
}