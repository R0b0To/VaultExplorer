import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/features/camera/vault_camera_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/camera');
  late VaultCameraController controller;

  setUp(() {
    controller = VaultCameraController(VaultEngineEvents());

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasPermissions':
          return true;
        case 'open':
          return {
            'sessionId': 42,
            'textureId': 101,
            'cameraId': '0',
            'zoomMin': 1.0,
            'zoomMax': 8.0,
            'minExposureEv': -2.0,
            'maxExposureEv': 2.0,
            'previewWidth': 1920,
            'previewHeight': 1080,
            'sensorOrientation': 90,
            'lenses': [
              {
                'cameraId': '0',
                'facing': 'back',
                'isLogical': true,
                'zoomMin': 1.0,
                'zoomMax': 8.0,
                'relativeZoom': 1.0,
              },
            ],
          };
        case 'takePhoto':
          return {'success': true, 'error': null};
        case 'startVideoRecording':
          return {'success': true, 'error': null};
        case 'stopVideoRecording':
          return {'success': true, 'durationMs': 3500, 'error': null};
        case 'switchLens':
          return {
            'textureId': 102,
            'cameraId': '1',
            'zoomMin': 0.5,
            'zoomMax': 4.0,
          };
        case 'setZoom':
        case 'setFlash':
        case 'setExposureOffset':
        case 'setFocusAndExposurePoint':
        case 'setOrientationDegrees':
        case 'close':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await controller.dispose();
  });

  group('VaultCameraController Tests', () {
    test('initial state is uninitialized', () {
      expect(controller.isInitialized, isFalse);
      expect(controller.sessionId, isNull);
      expect(controller.textureId, isNull);
    });

    test('open initializes session and populates info', () async {
      final info = await controller.open(facing: 'back', quality: 'fhd');

      expect(controller.isInitialized, isTrue);
      expect(info.sessionId, 42);
      expect(info.textureId, 101);
      expect(controller.sessionId, 42);
      expect(controller.textureId, 101);
      expect(controller.cameraId, '0');
      expect(controller.zoomMin, 1.0);
      expect(controller.zoomMax, 8.0);
      expect(controller.lenses.length, 1);
      // Sensor orientation 90 degrees inverts the aspect ratio (1080 / 1920)
      expect(controller.previewAspectRatio, closeTo(1080 / 1920, 0.001));
    });

    test('takePhoto returns success', () async {
      await controller.open();
      final result = await controller.takePhoto(volId: 1, virtualPath: 'photo.jpg');

      expect(result.success, isTrue);
      expect(result.error, isNull);
    });

    test('takePhoto before open returns failure', () async {
      final result = await controller.takePhoto(volId: 1, virtualPath: 'photo.jpg');

      expect(result.success, isFalse);
      expect(result.error, 'Camera not open');
    });

    test('video recording lifecycle works', () async {
      await controller.open();
      final startRes = await controller.startVideoRecording(volId: 1, virtualPath: 'video.mp4');
      expect(startRes.success, isTrue);

      final stopRes = await controller.stopVideoRecording();
      expect(stopRes.success, isTrue);
      expect(stopRes.durationMs, 3500);
    });

    test('switchLens updates parameters', () async {
      await controller.open();
      await controller.switchLens('1');

      expect(controller.cameraId, '1');
      expect(controller.textureId, 102);
      expect(controller.zoomMin, 0.5);
      expect(controller.zoomMax, 4.0);
    });

    test('close resets initialized state', () async {
      await controller.open();
      expect(controller.isInitialized, isTrue);

      await controller.close();
      expect(controller.isInitialized, isFalse);
      expect(controller.sessionId, isNull);
    });
  });
}
