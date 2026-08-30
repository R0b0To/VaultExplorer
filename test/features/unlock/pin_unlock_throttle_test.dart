import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/unlock/unlock_lockout_throttle.dart';


// NOTE: authored from scratch (see container_unlock_method_pin_test.dart for
// why), not run against the Flutter toolchain -- please verify with
// `flutter test` locally.
//
// PinUnlockThrottle persists its failure counter and lockout timestamp via
// AppSecureStorage, which itself is a thin wrapper over the same
// `com.aeidolon.vaultexplorer/engine` MethodChannel used everywhere else in
// this app. This fakes that channel with a simple in-memory map so the
// throttle's own scheduling logic (mirrors PatternUnlockThrottle) can be
// exercised without native code.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late Map<String, String> store;

  setUp(() {
    store = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async {
        switch (call.method) {
          case 'readSecure':
            final key = call.arguments['key'] as String;
            return store[key];
          case 'writeSecure':
            final key = call.arguments['key'] as String;
            final value = call.arguments['value'] as String;
            store[key] = value;
            return true;
          case 'deleteSecure':
            final key = call.arguments['key'] as String;
            store.remove(key);
            return true;
          default:
            throw MissingPluginException();
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  const uri = 'content://test/container-a';
  const otherUri = 'content://test/container-b';

  group('PinUnlockThrottle', () {
    test('no lockout before any failures are recorded', () async {
      expect(await PinUnlockThrottle.currentLockout(uri), isNull);
    });

    test('first four failures do not trigger a lockout', () async {
      for (var i = 0; i < 4; i++) {
        final lockout = await PinUnlockThrottle.recordFailure(uri);
        expect(lockout, isNull, reason: 'failure #${i + 1} should not lock out yet');
      }
      expect(await PinUnlockThrottle.currentLockout(uri), isNull);
    });

    test('5th failure triggers a 30s lockout, growing by 30s per further failure, capped at 300s', () async {
      // Failures 1-4: no lockout.
      for (var i = 0; i < 4; i++) {
        await PinUnlockThrottle.recordFailure(uri);
      }

      // 5th failure -> 30s.
      var lockout = await PinUnlockThrottle.recordFailure(uri);
      expect(lockout, const Duration(seconds: 30));

      // 6th failure -> 60s.
      lockout = await PinUnlockThrottle.recordFailure(uri);
      expect(lockout, const Duration(seconds: 60));

      // Failures 7-13 -> 90s..270s in 30s steps.
      final expectedSeconds = [90, 120, 150, 180, 210, 240, 270];
      for (final expected in expectedSeconds) {
        lockout = await PinUnlockThrottle.recordFailure(uri);
        expect(lockout, Duration(seconds: expected));
      }

      // 14th failure -> caps at 300s.
      lockout = await PinUnlockThrottle.recordFailure(uri);
      expect(lockout, const Duration(seconds: 300));

      // 15th failure -> stays capped, does not keep growing.
      lockout = await PinUnlockThrottle.recordFailure(uri);
      expect(lockout, const Duration(seconds: 300));
    });

    test('currentLockout reflects the most recently triggered lockout', () async {
      for (var i = 0; i < 5; i++) {
        await PinUnlockThrottle.recordFailure(uri);
      }
      final remaining = await PinUnlockThrottle.currentLockout(uri);
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, lessThanOrEqualTo(30));
      expect(remaining.inSeconds, greaterThan(0));
    });

    test('clear() resets both the failure count and any active lockout', () async {
      for (var i = 0; i < 5; i++) {
        await PinUnlockThrottle.recordFailure(uri);
      }
      expect(await PinUnlockThrottle.currentLockout(uri), isNotNull);

      await PinUnlockThrottle.clear(uri);
      expect(await PinUnlockThrottle.currentLockout(uri), isNull);

      // Counter should also be back to zero -- next 4 failures shouldn't
      // lock out again.
      for (var i = 0; i < 4; i++) {
        final lockout = await PinUnlockThrottle.recordFailure(uri);
        expect(lockout, isNull);
      }
    });

    test('lockout state is tracked independently per container URI', () async {
      for (var i = 0; i < 5; i++) {
        await PinUnlockThrottle.recordFailure(uri);
      }
      expect(await PinUnlockThrottle.currentLockout(uri), isNotNull);
      expect(await PinUnlockThrottle.currentLockout(otherUri), isNull);
    });
  });
}
