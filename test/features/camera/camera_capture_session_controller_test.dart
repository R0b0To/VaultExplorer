import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/camera/camera_capture_session_controller.dart';
import 'package:vaultexplorer/features/camera/vault_camera_controller.dart';

void main() {
  group('CameraCaptureSession controller', () {
    test('initializes with default state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(cameraCaptureSessionProvider('session-1'));
      expect(state.isInitialized, isFalse);
      expect(state.selectedCameraId, '');
      expect(state.lenses, isEmpty);
      expect(state.permissionError, isNull);
      expect(state.isRecording, isFalse);
      expect(state.isEncrypting, isFalse);
      expect(state.isStartingVideo, isFalse);
      expect(state.busyLabel, '');
      expect(state.timerText, '00:00');
      expect(state.isCountingDown, isFalse);
      expect(state.countdownValue, 0);
      expect(state.minZoom, 1.0);
      expect(state.maxZoom, 1.0);
      expect(state.currentZoom, 1.0);
      expect(state.minExposureEv, 0.0);
      expect(state.maxExposureEv, 0.0);
      expect(state.currentExposureEv, 0.0);
      expect(state.showExposureSlider, isFalse);
    });

    test('setCameraOpened sets lens info, zoom bounds and resets exposure', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(cameraCaptureSessionProvider('session-1').notifier);

      const info = VaultCameraSessionInfo(
        sessionId: 10,
        textureId: 4,
        cameraId: 'cam_0',
        zoomMin: 1.0,
        zoomMax: 8.0,
        minExposureEv: -2.0,
        maxExposureEv: 2.0,
        previewWidth: 1920,
        previewHeight: 1080,
        sensorOrientation: 90,
        lenses: [
          NativeCameraLens(
            cameraId: 'cam_0',
            facing: 'back',
            isLogical: true,
            zoomMin: 1.0,
            zoomMax: 8.0,
          ),
        ],
      );

      notifier.setCameraOpened(info);

      final state = container.read(cameraCaptureSessionProvider('session-1'));
      expect(state.isInitialized, isTrue);
      expect(state.permissionError, isNull);
      expect(state.selectedCameraId, 'cam_0');
      expect(state.lenses, hasLength(1));
      expect(state.minZoom, 1.0);
      expect(state.maxZoom, 8.0);
      expect(state.currentZoom, 1.0);
      expect(state.minExposureEv, -2.0);
      expect(state.maxExposureEv, 2.0);
      expect(state.currentExposureEv, 0.0);
    });

    test('setZoom clamps to min and max', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(cameraCaptureSessionProvider('session-1').notifier);

      const info = VaultCameraSessionInfo(
        sessionId: 10,
        textureId: 4,
        cameraId: 'cam_0',
        zoomMin: 1.0,
        zoomMax: 5.0,
        minExposureEv: -2.0,
        maxExposureEv: 2.0,
        previewWidth: 1920,
        previewHeight: 1080,
        sensorOrientation: 90,
        lenses: [],
      );
      notifier.setCameraOpened(info);

      notifier.setZoom(3.5);
      expect(
        container.read(cameraCaptureSessionProvider('session-1')).currentZoom,
        3.5,
      );

      notifier.setZoom(10.0);
      expect(
        container.read(cameraCaptureSessionProvider('session-1')).currentZoom,
        5.0,
      );

      notifier.setZoom(0.5);
      expect(
        container.read(cameraCaptureSessionProvider('session-1')).currentZoom,
        1.0,
      );
    });

    test('setExposureEv clamps to range', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(cameraCaptureSessionProvider('session-1').notifier);

      const info = VaultCameraSessionInfo(
        sessionId: 10,
        textureId: 4,
        cameraId: 'cam_0',
        zoomMin: 1.0,
        zoomMax: 5.0,
        minExposureEv: -2.0,
        maxExposureEv: 2.0,
        previewWidth: 1920,
        previewHeight: 1080,
        sensorOrientation: 90,
        lenses: [],
      );
      notifier.setCameraOpened(info);

      notifier.setExposureEv(1.5);
      expect(
        container
            .read(cameraCaptureSessionProvider('session-1'))
            .currentExposureEv,
        1.5,
      );

      notifier.setExposureEv(5.0);
      expect(
        container
            .read(cameraCaptureSessionProvider('session-1'))
            .currentExposureEv,
        2.0,
      );

      notifier.setExposureEv(-4.0);
      expect(
        container
            .read(cameraCaptureSessionProvider('session-1'))
            .currentExposureEv,
        -2.0,
      );
    });

    test('countdown lifecycle functions correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(cameraCaptureSessionProvider('session-1').notifier);

      notifier.startCountdown(3);
      var state = container.read(cameraCaptureSessionProvider('session-1'));
      expect(state.isCountingDown, isTrue);
      expect(state.countdownValue, 3);

      notifier.updateCountdown(2);
      state = container.read(cameraCaptureSessionProvider('session-1'));
      expect(state.countdownValue, 2);

      notifier.stopCountdown();
      state = container.read(cameraCaptureSessionProvider('session-1'));
      expect(state.isCountingDown, isFalse);
    });

    test('recording and encryption state transitions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(cameraCaptureSessionProvider('session-1').notifier);

      notifier.setStartingVideo(true);
      expect(
        container
            .read(cameraCaptureSessionProvider('session-1'))
            .isStartingVideo,
        isTrue,
      );

      notifier.startRecording();
      var state = container.read(cameraCaptureSessionProvider('session-1'));
      expect(state.isRecording, isTrue);
      expect(state.timerText, '00:00');

      notifier.updateTimerText('00:05');
      state = container.read(cameraCaptureSessionProvider('session-1'));
      expect(state.timerText, '00:05');

      notifier.setEncrypting(true, label: 'Encrypting video...');
      state = container.read(cameraCaptureSessionProvider('session-1'));
      expect(state.isRecording, isFalse);
      expect(state.isEncrypting, isTrue);
      expect(state.busyLabel, 'Encrypting video...');

      notifier.setEncrypting(false);
      state = container.read(cameraCaptureSessionProvider('session-1'));
      expect(state.isEncrypting, isFalse);
    });

    test('permission error marks uninitialized and stashes error message', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier =
          container.read(cameraCaptureSessionProvider('session-1').notifier);

      notifier.setPermissionError('Camera permission denied');
      final state = container.read(cameraCaptureSessionProvider('session-1'));
      expect(state.isInitialized, isFalse);
      expect(state.permissionError, 'Camera permission denied');
    });

    test('keeps state isolated by session key', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier1 =
          container.read(cameraCaptureSessionProvider('sess-a').notifier);
      final notifier2 =
          container.read(cameraCaptureSessionProvider('sess-b').notifier);

      notifier1.setStartingVideo(true);
      expect(
        container.read(cameraCaptureSessionProvider('sess-a')).isStartingVideo,
        isTrue,
      );
      expect(
        container.read(cameraCaptureSessionProvider('sess-b')).isStartingVideo,
        isFalse,
      );
    });
  });
}
