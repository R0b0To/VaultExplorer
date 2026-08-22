import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';

// NOTE: No `test/` directory existed anywhere in the source this was
// authored against, so there was no existing suite/convention to match.
// This file was written from scratch, scoped to the pieces of the PIN
// unlock feature that are pure Dart (no platform channel, no BuildContext)
// and therefore need no mocking to exercise meaningfully. It has not been
// run against the Flutter toolchain (unavailable in the authoring
// environment) -- please run `flutter test` locally before relying on it.
void main() {
  group('ContainerUnlockMethod.pin', () {
    test('is included in .values alongside the other four methods', () {
      expect(ContainerUnlockMethod.values, hasLength(5));
      expect(ContainerUnlockMethod.values, contains(ContainerUnlockMethod.pin));
    });

    test('label and subtitle are PIN-specific, not shared with pattern', () {
      expect(ContainerUnlockMethod.pin.label, 'PIN Unlock');
      expect(ContainerUnlockMethod.pin.subtitle, isNot(ContainerUnlockMethod.pattern.subtitle));
    });

    test('toJson/fromJson round-trip', () {
      expect(ContainerUnlockMethod.pin.toJson(), 'pin');
      expect(ContainerUnlockMethod.fromJson('pin'), ContainerUnlockMethod.pin);
    });

    test('fromJson falls back to password for unknown/null values, not pin', () {
      expect(ContainerUnlockMethod.fromJson('not-a-real-method'), ContainerUnlockMethod.password);
      expect(ContainerUnlockMethod.fromJson(null), ContainerUnlockMethod.password);
    });

    test('every value round-trips through toJson/fromJson', () {
      for (final method in ContainerUnlockMethod.values) {
        expect(ContainerUnlockMethod.fromJson(method.toJson()), method);
      }
    });

    test('icon is distinct from the other four unlock methods', () {
      final icons = ContainerUnlockMethod.values.map((m) => m.icon).toSet();
      // 5 distinct enum values should map to 5 distinct icons -- if PIN's
      // icon assignment were accidentally copy-pasted from another method,
      // this set would come up short.
      expect(icons, hasLength(5));
    });
  });

  group('ContainerRecord.pendingPinHash', () {
    test('is null by default and settable via copyWith', () {
      final record = ContainerRecord(
        uri: 'content://test/container',
        label: 'Test Container',
        unlockMethod: ContainerUnlockMethod.pin,
      );
      expect(record.pendingPinHash, isNull);

      final withHash = record.copyWith(pendingPinHash: 'salt_b64:hash_b64');
      expect(withHash.pendingPinHash, 'salt_b64:hash_b64');
      // copyWith shouldn't have disturbed the unrelated pattern field.
      expect(withHash.pendingPatternHash, isNull);
    });
  });
}
