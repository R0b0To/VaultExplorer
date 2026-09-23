import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/camera/camera_ui_components.dart';

void main() {
  _zoomLabelGroup();
  group('cameraPreviewQuarterTurns', () {
    test('counter-rotates by the display rotation', () {
      // Surface.ROTATION_0/90/180/270 -> clockwise quarter turns.
      expect(cameraPreviewQuarterTurns(0), 0);
      expect(cameraPreviewQuarterTurns(1), 3);
      expect(cameraPreviewQuarterTurns(2), 2);
      expect(cameraPreviewQuarterTurns(3), 1);
    });

    test('a display rotation plus its compensation is a full turn', () {
      for (var r = 0; r < 4; r++) {
        expect((r + cameraPreviewQuarterTurns(r)) % 4, 0);
      }
    });
  });

  group('cameraDisplayPointToNatural', () {
    test('rotation 0 is the identity', () {
      final p = cameraDisplayPointToNatural(0.2, 0.7, 0);
      expect(p.x, closeTo(0.2, 1e-9));
      expect(p.y, closeTo(0.7, 1e-9));
    });

    test('rotation 180 mirrors both axes', () {
      final p = cameraDisplayPointToNatural(0.2, 0.7, 2);
      expect(p.x, closeTo(0.8, 1e-9));
      expect(p.y, closeTo(0.3, 1e-9));
    });

    test('display top-left corner lands on the expected natural corner', () {
      // ROTATION_90: UI top edge is the phone's right edge, UI left edge is
      // the phone's top edge -> UI (0,0) is the natural top-right corner.
      final r1 = cameraDisplayPointToNatural(0, 0, 1);
      expect((r1.x, r1.y), (1.0, 0.0));
      // ROTATION_270: UI top edge is the phone's left edge, UI left edge is
      // the phone's bottom edge -> UI (0,0) is the natural bottom-left corner.
      final r3 = cameraDisplayPointToNatural(0, 0, 3);
      expect((r3.x, r3.y), (0.0, 1.0));
    });

    test('rotations 1 and 3 are inverses of each other', () {
      final a = cameraDisplayPointToNatural(0.3, 0.6, 1);
      final back = cameraDisplayPointToNatural(a.x, a.y, 3);
      expect(back.x, closeTo(0.3, 1e-9));
      expect(back.y, closeTo(0.6, 1e-9));
    });
  });

  group('cameraIconTurns', () {
    test('portrait display keeps the raw device rotation', () {
      expect(cameraIconTurns(deviceTurns: 0.0, displayRotation: 0), 0.0);
      expect(cameraIconTurns(deviceTurns: 0.25, displayRotation: 0), 0.25);
      expect(cameraIconTurns(deviceTurns: -0.25, displayRotation: 0), -0.25);
      expect(cameraIconTurns(deviceTurns: 0.5, displayRotation: 0), 0.5);
    });

    test('no extra icon rotation when the display followed the device', () {
      // device turned counter-clockwise, OS rotated the UI to match
      expect(cameraIconTurns(deviceTurns: 0.25, displayRotation: 1), 0.0);
      expect(cameraIconTurns(deviceTurns: -0.25, displayRotation: 3), 0.0);
      expect(cameraIconTurns(deviceTurns: 0.5, displayRotation: 2), 0.0);
    });

    test('rotation lock: device landscape, display still portrait', () {
      expect(cameraIconTurns(deviceTurns: 0.25, displayRotation: 0), 0.25);
    });

    test('result is always one of the four snapped values', () {
      final allowed = {0.0, 0.25, 0.5, -0.25};
      for (final t in const [0.0, 0.25, 0.5, -0.25]) {
        for (var r = 0; r < 4; r++) {
          expect(allowed, contains(cameraIconTurns(deviceTurns: t, displayRotation: r)));
        }
      }
    });
  });
}

void _zoomLabelGroup() {
  group('formatCameraZoom', () {
    test('whole values have no decimal', () {
      expect(formatCameraZoom(1.0), '1x');
      expect(formatCameraZoom(2.0), '2x');
      expect(formatCameraZoom(0.98), '1x');
    });

    test('fractional values show one decimal', () {
      expect(formatCameraZoom(0.5), '0.5x');
      expect(formatCameraZoom(2.34), '2.3x');
      expect(formatCameraZoom(7.96), '8x');
    });
  });
}
