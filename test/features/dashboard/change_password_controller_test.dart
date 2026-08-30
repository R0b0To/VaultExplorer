import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/dashboard/widgets/change_password_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('ChangePasswordController Tests', () {
    const uri = 'file:///vault.hc';
    const format = 'veracrypt';
    final provider = changePasswordProvider(uri, format, 0, 0);

    test('initializes with empty keyfile lists', () {
      final state = container.read(provider);

      expect(state.oldKeyfiles, isEmpty);
      expect(state.newKeyfiles, isEmpty);
    });

    test('removeOldKeyfile and removeNewKeyfile filter keyfiles list', () {
      final controller = container.read(provider.notifier);

      const k1 = (uri: 'content://k1', displayName: 'k1.key');
      const k2 = (uri: 'content://k2', displayName: 'k2.key');

      controller.removeOldKeyfile(k1);
      expect(container.read(provider).oldKeyfiles, isEmpty);

      controller.removeNewKeyfile(k2);
      expect(container.read(provider).newKeyfiles, isEmpty);
    });
  });
}