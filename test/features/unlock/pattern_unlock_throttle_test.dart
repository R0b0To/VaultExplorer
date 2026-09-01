import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/unlock/unlock_lockout_throttle.dart';


/// [PatternUnlockThrottle] talks to [AppSecureStorage], which is a thin
/// wrapper over the `com.aeidolon.vaultexplorer/engine` MethodChannel with
/// no settable-fake seam of its own (unlike the constructor-injected
/// `core/api` classes, e.g. [VaultLifecycleApi]). These
/// tests intercept that channel directly with an in-memory
/// `Map<String, String>` standing in for the platform's secure storage --
/// the standard Flutter approach for testing platform-channel-backed code
/// without a real platform side (see
/// https://docs.flutter.dev/testing/plugins-in-tests -- "mock the
/// platform channel").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  final store = <String, String>{};

  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'readSecure':
          return store[key];
        case 'writeSecure':
          store[key] = args['value'] as String;
          return true;
        case 'deleteSecure':
          store.remove(key);
          return true;
        default:
          throw UnimplementedError('unexpected channel call: ${call.method}');
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  const uri = 'content://tree/primary%3AVaults%2Ftest.vc';

  test('currentLockout is null with no prior failures', () async {
    expect(await PatternUnlockThrottle.currentLockout(uri), isNull);
  });

  test('the first four failures never trigger a lockout', () async {
    for (var i = 0; i < 4; i++) {
      expect(await PatternUnlockThrottle.recordFailure(uri), isNull);
    }
    expect(await PatternUnlockThrottle.currentLockout(uri), isNull);
  });

  test('the schedule is 30s at the 5th failure, +30s per failure after, capped at 300s', () async {
    // Matches the formula in PatternUnlockThrottle.recordFailure and
    // LockGateScreen._recordFailure: seconds = clamp(30*(attempts-4), 30, 300).
    const expectedSecondsByAttempt = {
      5: 30,
      6: 60,
      7: 90,
      8: 120,
      9: 150,
      10: 180,
      11: 210,
      12: 240,
      13: 270,
      14: 300,
      15: 300, // stays capped
    };

    for (var attempt = 1; attempt <= 15; attempt++) {
      final lockout = await PatternUnlockThrottle.recordFailure(uri);
      final expectedSeconds = expectedSecondsByAttempt[attempt];
      if (expectedSeconds == null) {
        expect(lockout, isNull, reason: 'attempt $attempt should not yet trigger a lockout');
      } else {
        expect(lockout, isNotNull, reason: 'attempt $attempt should trigger a lockout');
        expect(lockout!.inSeconds, expectedSeconds, reason: 'wrong duration at attempt $attempt');
      }
    }
  });

  test('currentLockout reflects a duration close to what recordFailure just returned', () async {
    for (var i = 0; i < 5; i++) {
      await PatternUnlockThrottle.recordFailure(uri);
    }

    final remaining = await PatternUnlockThrottle.currentLockout(uri);

    expect(remaining, isNotNull);
    // Allow a small margin for wall-clock time elapsed during the test
    // itself -- this isn't asserting exact scheduling, just that a
    // lockout is in effect and roughly the right size.
    expect(remaining!.inSeconds, inInclusiveRange(25, 30));
  });

  test('clear removes both the attempt count and any active lockout', () async {
    for (var i = 0; i < 6; i++) {
      await PatternUnlockThrottle.recordFailure(uri);
    }
    expect(await PatternUnlockThrottle.currentLockout(uri), isNotNull);

    await PatternUnlockThrottle.clear(uri);

    expect(await PatternUnlockThrottle.currentLockout(uri), isNull);
    // And the attempt counter itself was reset, not just the lockout
    // timestamp -- the next 4 failures should again not trigger a lockout.
    for (var i = 0; i < 4; i++) {
      expect(await PatternUnlockThrottle.recordFailure(uri), isNull);
    }
  });

  test('lockout state is independent per container URI', () async {
    const otherUri = 'content://tree/primary%3AVaults%2Fother.vc';

    for (var i = 0; i < 5; i++) {
      await PatternUnlockThrottle.recordFailure(uri);
    }

    expect(await PatternUnlockThrottle.currentLockout(uri), isNotNull);
    expect(await PatternUnlockThrottle.currentLockout(otherUri), isNull);
  });

  test('an expired lockout is treated as no lockout and is cleaned up', () async {
    // Directly seed an already-expired lockout timestamp, since we don't
    // want this test to actually sleep for real time.
    final pastMs = DateTime.now().subtract(const Duration(seconds: 5)).millisecondsSinceEpoch;
    store['pattern_unlock_locked_until_ms_v1:$uri'] = pastMs.toString();

    final remaining = await PatternUnlockThrottle.currentLockout(uri);

    expect(remaining, isNull);
    expect(store.containsKey('pattern_unlock_locked_until_ms_v1:$uri'), isFalse, reason: 'an expired lockout key should be deleted, not just ignored');
  });
}
