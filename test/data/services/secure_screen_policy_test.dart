import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';

class _RecordingVaultFileIoApi extends VaultFileIoApi {
  bool? secureScreenValue;
  bool? recentsSnapshotBlockedValue;

  _RecordingVaultFileIoApi() : super(const MethodChannel('test'));

  @override
  Future<bool> setSecureScreen(bool enabled) async {
    secureScreenValue = enabled;
    return true;
  }

  @override
  Future<void> setRecentsSnapshotBlocked(bool blocked) async {
    recentsSnapshotBlockedValue = blocked;
  }
}

void main() {
  late _RecordingVaultFileIoApi fake;
  late SecureScreenPolicy policy;

  setUp(() {
    fake = _RecordingVaultFileIoApi();
    policy = SecureScreenPolicy(fake);
  });

  test(
    'setSecureScreen follows the enabled global preference',
    () async {
      await policy.apply(preference: true);

      expect(fake.secureScreenValue, isTrue);
    },
  );

  test('setSecureScreen follows the disabled global preference', () async {
    await policy.apply(preference: false);

    // The disabled global preference must leave live screenshots available.
    expect(fake.secureScreenValue, isFalse);
  });

  test('setRecentsSnapshotBlocked follows the disabled global preference',
      () async {
    await policy.apply(preference: false);

    expect(fake.recentsSnapshotBlockedValue, isFalse);
  });

  test('setRecentsSnapshotBlocked follows the enabled global preference',
      () async {
    await policy.apply(preference: true);

    expect(fake.recentsSnapshotBlockedValue, isTrue);
  });

  test('apply always calls both native setters', () async {
    await policy.apply(preference: true);

    expect(fake.secureScreenValue, isNotNull);
    expect(fake.recentsSnapshotBlockedValue, isNotNull);
  });
}
