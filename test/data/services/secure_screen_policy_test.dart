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
    'setSecureScreen follows preference alone when nothing is mounted',
    () async {
      policy.anyContainerMounted = false;

      await policy.apply(preference: true);

      expect(fake.secureScreenValue, isTrue);
    },
  );

  test('setSecureScreen stays off when preference is false, even with a '
      'container mounted -- a live screenshot must remain possible', () async {
    policy.anyContainerMounted = true;

    await policy.apply(preference: false);

    // This is the behavior the class doc explicitly calls out as
    // deliberate: FLAG_SECURE must never be forced on just because a
    // container is mounted, or "block screenshots: off" stops meaning
    // what it says.
    expect(fake.secureScreenValue, isFalse);
  });

  test('setRecentsSnapshotBlocked follows anyContainerMounted, not '
      'preference', () async {
    policy.anyContainerMounted = true;

    await policy.apply(preference: false);

    expect(fake.recentsSnapshotBlockedValue, isTrue);
  });

  test('setRecentsSnapshotBlocked is false when nothing is mounted, even '
      'if the user has screenshot-blocking enabled', () async {
    policy.anyContainerMounted = false;

    await policy.apply(preference: true);

    expect(fake.recentsSnapshotBlockedValue, isFalse);
  });

  test('apply always calls both native setters', () async {
    await policy.apply(preference: true);

    expect(fake.secureScreenValue, isNotNull);
    expect(fake.recentsSnapshotBlockedValue, isNotNull);
  });
}
