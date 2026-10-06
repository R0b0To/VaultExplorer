// NOTE: authored without running against the Flutter toolchain -- please
// verify with `flutter test test/features/unlock/unlock_throttle_storage_outage_test.dart`.
//
// Pins the behaviour added to PatternUnlockThrottle / PinUnlockThrottle for a
// failing secure storage. Before, a Keystore error (or a write the native side
// reports as `false`) meant failed unlock attempts were not counted at all, so
// anything able to make storage fail got unlimited attempts. Now attempts made
// during an outage are counted in memory and follow the same schedule, while
// the persisted side still fails open (a storage glitch never locks anyone out
// by itself).
//
// The healthy-storage behaviour is covered by pattern_unlock_throttle_test.dart
// and pin_unlock_throttle_test.dart; each test here uses its own URI because
// the in-memory fallback is per-process static state.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/unlock/unlock_lockout_throttle.dart';

typedef _Throttle = ({
  String name,
  Future<Duration?> Function(String) recordFailure,
  Future<Duration?> Function(String) currentLockout,
  Future<void> Function(String) clear,
});

enum _Storage { healthy, throwing, reportsNotPersisted }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late Map<String, String> store;
  var mode = _Storage.healthy;

  setUp(() {
    store = {};
    mode = _Storage.healthy;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async {
        final args = call.arguments as Map;
        final key = args['key'] as String;
        if (mode == _Storage.throwing) {
          throw PlatformException(code: 'KEYSTORE', message: 'secure storage unavailable');
        }
        switch (call.method) {
          case 'readSecure':
            return store[key];
          case 'writeSecure':
            if (mode == _Storage.reportsNotPersisted) return false;
            store[key] = args['value'] as String;
            return true;
          case 'deleteSecure':
            store.remove(key);
            return true;
          default:
            throw UnimplementedError('unexpected channel call: ${call.method}');
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

  final throttles = <_Throttle>[
    (
      name: 'PatternUnlockThrottle',
      recordFailure: PatternUnlockThrottle.recordFailure,
      currentLockout: PatternUnlockThrottle.currentLockout,
      clear: PatternUnlockThrottle.clear,
    ),
    (
      name: 'PinUnlockThrottle',
      recordFailure: PinUnlockThrottle.recordFailure,
      currentLockout: PinUnlockThrottle.currentLockout,
      clear: PinUnlockThrottle.clear,
    ),
  ];

  for (final t in throttles) {
    group(t.name, () {
      test('still locks out at the 5th failure when secure storage throws', () async {
        const uri = 'content://test/outage-throws';
        mode = _Storage.throwing;

        for (var i = 0; i < 4; i++) {
          expect(await t.recordFailure(uri), isNull, reason: 'failure #${i + 1}');
        }
        expect(await t.recordFailure(uri), const Duration(seconds: 30));

        final remaining = await t.currentLockout(uri);
        expect(remaining, isNotNull);
        expect(remaining!.inSeconds, inInclusiveRange(1, 30));

        await t.clear(uri);
      });

      test('treats a write reported as not persisted like a storage failure', () async {
        const uri = 'content://test/outage-not-persisted';
        mode = _Storage.reportsNotPersisted;

        for (var i = 0; i < 4; i++) {
          await t.recordFailure(uri);
        }
        expect(await t.recordFailure(uri), const Duration(seconds: 30));
        // Nothing reached the store, yet the lockout is still honoured.
        expect(store, isEmpty);
        expect(await t.currentLockout(uri), isNotNull);

        await t.clear(uri);
      });

      test('failures counted in memory carry over once storage recovers', () async {
        const uri = 'content://test/outage-recovers';
        mode = _Storage.throwing;
        for (var i = 0; i < 3; i++) {
          await t.recordFailure(uri); // failures 1-3, in memory only
        }

        mode = _Storage.healthy;
        expect(await t.recordFailure(uri), isNull, reason: 'failure #4');
        expect(await t.recordFailure(uri), const Duration(seconds: 30), reason: 'failure #5');

        await t.clear(uri);
      });

      test('clear() drops the in-memory state even while storage is failing', () async {
        const uri = 'content://test/outage-clear';
        mode = _Storage.throwing;
        for (var i = 0; i < 5; i++) {
          await t.recordFailure(uri);
        }
        expect(await t.currentLockout(uri), isNotNull);

        await t.clear(uri);
        expect(await t.currentLockout(uri), isNull);
      });

      test('a failed read with nothing recorded in memory is not a lockout', () async {
        const uri = 'content://test/outage-nothing-recorded';
        mode = _Storage.throwing;
        expect(await t.currentLockout(uri), isNull);
      });
    });
  }
}
