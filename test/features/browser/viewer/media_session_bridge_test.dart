import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/media_session_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/player');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('dispatch', () {
    test('maps native action names onto the stream', () async {
      final received = <MediaSessionAction>[];
      final sub = MediaSessionBridge.actions.listen(received.add);

      MediaSessionBridge.dispatch('next');
      MediaSessionBridge.dispatch('previous');
      await Future<void>.delayed(Duration.zero);

      expect(received, [MediaSessionAction.next, MediaSessionAction.previous]);
      await sub.cancel();
    });

    test('ignores unknown and missing actions', () async {
      final received = <MediaSessionAction>[];
      final sub = MediaSessionBridge.actions.listen(received.add);

      MediaSessionBridge.dispatch('rewind');
      MediaSessionBridge.dispatch('');
      MediaSessionBridge.dispatch(null);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });
  });

  group('setNavigation', () {
    test(
      'sends navigation and playlist position over the player channel',
      () async {
        MethodCall? seen;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              seen = call;
              return null;
            });

        await MediaSessionBridge.setNavigation(
          hasPrevious: true,
          hasNext: false,
        );

        expect(seen?.method, 'setMediaNavigation');
        expect(seen?.arguments, {
          'hasPrevious': true,
          'hasNext': false,
          'currentPosition': 0,
          'totalItems': 0,
        });
      },
    );

    test('swallows platform failures', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'boom');
          });

      await expectLater(
        MediaSessionBridge.setNavigation(hasPrevious: false, hasNext: true),
        completes,
      );
    });
  });
}
