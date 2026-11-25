import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ve_desktop_transfer/ve_desktop_transfer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('vaultexplorer/desktop_transfer');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') {
            return <Object?, Object?>{'supported': true, 'backend': 'test'};
          }
          if (call.method == 'registerView') return true;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('DesktopDropTarget filters by viewId and emits enter/drop/exit', (
    tester,
  ) async {
    if (!(Platform.isWindows || Platform.isLinux)) return;

    var entered = 0;
    var exited = 0;
    DesktopDropDetails? dropped;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 300,
            child: DesktopDropTarget(
              onDragEntered: (_) => entered++,
              onDragExited: (_) => exited++,
              onDragDone: (details) => dropped = details,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final viewId = View.of(tester.element(find.byType(DesktopDropTarget))).viewId;
    expect(
      calls.any(
        (c) => c.method == 'registerView' && (c.arguments as Map)['viewId'] == viewId,
      ),
      isTrue,
    );

    const codec = StandardMethodCodec();
    Future<void> dispatchNative(String method, Map<Object?, Object?> args) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            codec.encodeMethodCall(MethodCall(method, args)),
            (_) {},
          );
    }

    // Drop targeting another view must be ignored.
    await dispatchNative('onDropEntered', {'viewId': viewId + 99, 'x': 20.0, 'y': 20.0});
    await dispatchNative('onDropReceived', {
      'viewId': viewId + 99,
      'x': 20.0,
      'y': 20.0,
      'paths': ['C:/tmp/other.txt'],
    });
    expect(entered, 0);
    expect(dropped, isNull);

    // Matching viewId receives scaled enter + drop events.
    await dispatchNative('onDropEntered', {'viewId': viewId, 'x': 40.0, 'y': 50.0});
    expect(entered, 1);

    await dispatchNative('onDropReceived', {
      'viewId': viewId,
      'x': 40.0,
      'y': 50.0,
      'paths': ['C:/tmp/imported.txt'],
    });
    expect(dropped, isNotNull);
    expect(dropped!.paths, ['C:/tmp/imported.txt']);
    expect(exited, 1);
  });
}
