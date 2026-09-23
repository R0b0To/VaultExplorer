import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';

void main() {
  group('ContainerRecord isExemptFromGlobalLock', () {
    test('is false when container is at App Default (autoCloseMins == 0, autoCloseNever == false)', () {
      const record = ContainerRecord(
        uri: 'file:///vault.hc',
        label: 'Default Vault',
        autoCloseMins: 0,
        autoCloseNever: false,
      );
      expect(record.isExemptFromGlobalLock, isFalse);
    });

    test('is true when container explicitly has autoCloseNever set to true', () {
      const record = ContainerRecord(
        uri: 'file:///vault.hc',
        label: 'Never Lock Vault',
        autoCloseMins: 0,
        autoCloseNever: true,
      );
      expect(record.isExemptFromGlobalLock, isTrue);
    });

    test('is true when container explicitly has autoCloseMins > 0 (e.g. 1 minute)', () {
      const record = ContainerRecord(
        uri: 'file:///vault.hc',
        label: '1-Min Vault',
        autoCloseMins: 1,
        autoCloseNever: false,
      );
      expect(record.isExemptFromGlobalLock, isTrue);
    });

    test('is true when container explicitly has custom duration (e.g. 15 minutes)', () {
      const record = ContainerRecord(
        uri: 'file:///vault.hc',
        label: '15-Min Vault',
        autoCloseMins: 15,
        autoCloseNever: false,
      );
      expect(record.isExemptFromGlobalLock, isTrue);
    });
  });
}
