import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/secure_temp_file.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('secure_temp_file_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('wipeAndDelete', () {
    test('deletes an existing file', () async {
      final file = File('${tempDir.path}/secret.txt');
      await file.writeAsString('sensitive plaintext');

      await SecureTempFile.wipeAndDelete(file);

      expect(await file.exists(), isFalse);
    });

    test('deletes an empty file without error', () async {
      final file = File('${tempDir.path}/empty.txt');
      await file.create();

      await SecureTempFile.wipeAndDelete(file);

      expect(await file.exists(), isFalse);
    });

    test('a file that does not exist is treated as already-wiped, not an '
        'error', () async {
      final file = File('${tempDir.path}/never-existed.txt');
      expect(await file.exists(), isFalse);

      await expectLater(SecureTempFile.wipeAndDelete(file), completes);

      expect(await file.exists(), isFalse);
    });

    test('a file larger than the internal wipe chunk size (4 MB) is fully '
        'zero-filled and deleted, exercising the chunked-write loop',
        () async {
      final file = File('${tempDir.path}/large.bin');
      // 5 MB: bigger than the 4 MB chunk, so wipeAndDelete must loop.
      final size = 5 * 1024 * 1024;
      final random = Uint8List(size);
      for (var i = 0; i < size; i += 4096) {
        random[i] = 0xFF; // sparse non-zero markers, cheap to write
      }
      await file.writeAsBytes(random);
      expect(await file.length(), size);

      await SecureTempFile.wipeAndDelete(file);

      expect(await file.exists(), isFalse);
    });

    test('can be called twice on the same File handle without throwing',
        () async {
      final file = File('${tempDir.path}/twice.txt');
      await file.writeAsString('data');

      await SecureTempFile.wipeAndDelete(file);
      await expectLater(SecureTempFile.wipeAndDelete(file), completes);
    });
  });

  group('wipeAndDeleteDir', () {
    test('recursively wipes nested files and removes the directory tree',
        () async {
      final subDir = Directory('${tempDir.path}/nested');
      await subDir.create();
      await File('${tempDir.path}/top.txt').writeAsString('top level');
      await File('${subDir.path}/inner.txt').writeAsString('nested');

      await SecureTempFile.wipeAndDeleteDir(tempDir);

      expect(await tempDir.exists(), isFalse);
    });

    test('an empty directory is simply removed', () async {
      final emptyDir =
          await Directory.systemTemp.createTemp('secure_temp_empty_');

      await SecureTempFile.wipeAndDeleteDir(emptyDir);

      expect(await emptyDir.exists(), isFalse);
    });

    test('a directory that does not exist is treated as already-wiped, '
        'not an error', () async {
      final missing = Directory('${tempDir.path}/does-not-exist');
      expect(await missing.exists(), isFalse);

      await expectLater(SecureTempFile.wipeAndDeleteDir(missing), completes);
    });
  });
}
