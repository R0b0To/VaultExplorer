import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Follows the pattern documented in vault_explorer_api_test.dart: extend
/// the concrete VaultExplorerApi and override only what's needed.
class _RecordingVaultExplorerApi extends VaultExplorerApi {
  bool? secureScreenValue;
  bool? recentsSnapshotBlockedValue;

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
  late _RecordingVaultExplorerApi fake;

  setUp(() {
    fake = _RecordingVaultExplorerApi();
    vaultExplorerApi = fake;
    SecureScreenPolicy.anyContainerMounted = false;
  });

  tearDown(() {
    vaultExplorerApi = const VaultExplorerApi();
    SecureScreenPolicy.anyContainerMounted = false;
  });

  test('setSecureScreen follows preference alone when nothing is mounted', () async {
    SecureScreenPolicy.anyContainerMounted = false;

    await SecureScreenPolicy.apply(preference: true);

    expect(fake.secureScreenValue, isTrue);
  });

  test('setSecureScreen stays off when preference is false, even with a '
      'container mounted -- a live screenshot must remain possible', () async {
    SecureScreenPolicy.anyContainerMounted = true;

    await SecureScreenPolicy.apply(preference: false);

    // This is the behavior the class doc explicitly calls out as
    // deliberate: FLAG_SECURE must never be forced on just because a
    // container is mounted, or "block screenshots: off" stops meaning
    // what it says.
    expect(fake.secureScreenValue, isFalse);
  });

  test('setRecentsSnapshotBlocked follows anyContainerMounted, not '
      'preference', () async {
    SecureScreenPolicy.anyContainerMounted = true;

    await SecureScreenPolicy.apply(preference: false);

    expect(fake.recentsSnapshotBlockedValue, isTrue);
  });

  test('setRecentsSnapshotBlocked is false when nothing is mounted, even '
      'if the user has screenshot-blocking enabled', () async {
    SecureScreenPolicy.anyContainerMounted = false;

    await SecureScreenPolicy.apply(preference: true);

    expect(fake.recentsSnapshotBlockedValue, isFalse);
  });

  test('apply always calls both native setters', () async {
    await SecureScreenPolicy.apply(preference: true);

    expect(fake.secureScreenValue, isNotNull);
    expect(fake.recentsSnapshotBlockedValue, isNotNull);
  });
}
