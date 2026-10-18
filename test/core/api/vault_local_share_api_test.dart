import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_local_share_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  const api = VaultLocalShareApi(channel);

  final calls = <MethodCall>[];
  Object? nextResult;
  Object? nextError;

  setUp(() {
    calls.clear();
    nextResult = null;
    nextError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (nextError != null) throw nextError!;
          return nextResult;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('shareLocalFiles', () {
    test('a plain file share sends only the paths', () async {
      nextResult = true;

      final ok = await api.shareLocalFiles(['/storage/emulated/0/a.txt']);

      expect(ok, isTrue);
      expect(calls.single.method, 'shareLocalFile');
      expect(calls.single.arguments['filePaths'], ['/storage/emulated/0/a.txt']);
      expect(calls.single.arguments.containsKey('directoryPaths'), isFalse);
    });

    test('names which paths are folders so native shares them as a zip', () async {
      nextResult = true;

      final ok = await api.shareLocalFiles(
        ['/storage/emulated/0/DCIM', '/storage/emulated/0/a.txt'],
        directoryPaths: ['/storage/emulated/0/DCIM'],
      );

      expect(ok, isTrue);
      expect(calls.single.arguments['directoryPaths'], ['/storage/emulated/0/DCIM']);
    });

    test('returns false without calling the channel when there is nothing to share', () async {
      final ok = await api.shareLocalFiles([]);

      expect(ok, isFalse);
      expect(calls, isEmpty);
    });

    test('returns false instead of throwing when the platform call fails', () async {
      nextError = PlatformException(code: 'SHARE_LOCAL_FILE_ERROR');

      final ok = await api.shareLocalFiles(
        ['/storage/emulated/0/DCIM'],
        directoryPaths: ['/storage/emulated/0/DCIM'],
      );

      expect(ok, isFalse);
    });
  });
}
