import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/sensitive_clipboard.dart';

class _RecordingFileIoApi extends VaultFileIoApi {
  final copiedValues = <String>[];
  final clearedValues = <String?>[];

  _RecordingFileIoApi() : super(const MethodChannel('test'));

  @override
  Future<bool> setSensitiveClipboardText(String text) async {
    copiedValues.add(text);
    return true;
  }

  @override
  Future<bool> clearSensitiveClipboardText({String? expectedText}) async {
    clearedValues.add(expectedText);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'marks copied text sensitive and clears it after the configured delay',
    () async {
      final fileIoApi = _RecordingFileIoApi();
      final clipboard = SensitiveClipboard(
        fileIoApi,
        clearAfter: Duration.zero,
      );

      await clipboard.copy('vault-secret');
      await Future<void>.delayed(Duration.zero);

      expect(fileIoApi.copiedValues, ['vault-secret']);
      expect(fileIoApi.clearedValues, ['vault-secret']);
    },
  );

  test('a later copy cancels the previous scheduled clear', () async {
    final fileIoApi = _RecordingFileIoApi();
    final clipboard = SensitiveClipboard(fileIoApi, clearAfter: Duration.zero);

    await clipboard.copy('first');
    await clipboard.copy('second');
    await Future<void>.delayed(Duration.zero);

    expect(fileIoApi.copiedValues, ['first', 'second']);
    expect(fileIoApi.clearedValues, ['second']);
  });
}
