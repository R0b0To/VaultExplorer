import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/camera/camera_capture_screen.dart';
import 'package:vaultexplorer/features/camera/quick_capture_screen.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

MountedContainer _testContainer() => MountedContainer(
  volId: 1,
  uri: 'file:///vault.hc',
  displayName: 'Vault',
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000000,
  freeSpace: 500000,
  containerFormat: 'veracrypt',
);

class _FakeFileIoApi implements VaultFileIoApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeLifecycleApi implements VaultLifecycleApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cameraChannel = MethodChannel('com.aeidolon.vaultexplorer/camera');
  const accelChannel = EventChannel('com.aeidolon.vaultexplorer/camera/accelerometer');
  final methodCalls = <String>[];
  int openCount = 0;
  int closeCount = 0;

  setUp(() async {
    methodCalls.clear();
    openCount = 0;
    closeCount = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, (call) async {
      methodCalls.add(call.method);
      switch (call.method) {
        case 'hasPermissions':
          return true;
        case 'open':
          openCount++;
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
        case 'close':
          closeCount++;
          return null;
        case 'getDisplayRotation':
          return 0;
        case 'setFlash':
        case 'setZoom':
        case 'setOrientationDegrees':
          return null;
        default:
          return null;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(accelChannel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, null);
  });

  Widget buildCameraScreen() {
    return ProviderScope(
      overrides: [
        vaultFileIoApiProvider.overrideWithValue(_FakeFileIoApi()),
        vaultLifecycleApiProvider.overrideWithValue(_FakeLifecycleApi()),
        vaultEngineEventsProvider.overrideWithValue(VaultEngineEvents()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CameraCaptureScreen(
          container: _testContainer(),
          targetDirPath: '/Camera',
        ),
      ),
    );
  }

  Widget buildQuickCaptureScreen() {
    return ProviderScope(
      overrides: [
        vaultFileIoApiProvider.overrideWithValue(_FakeFileIoApi()),
        vaultLifecycleApiProvider.overrideWithValue(_FakeLifecycleApi()),
        vaultEngineEventsProvider.overrideWithValue(VaultEngineEvents()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuickCaptureScreen(),
      ),
    );
  }

  group('CameraCaptureScreen Lifecycle', () {
    testWidgets(
      'inactive→resumed does NOT close or reload camera (status bar drag)',
      (tester) async {
        await tester.pumpWidget(buildCameraScreen());
        await tester.pumpAndSettle();

        expect(openCount, 1, reason: 'camera opened once on init');
        final closesBefore = closeCount;

        // Simulate status-bar drag (inactive then resumed)
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();

        expect(closeCount, closesBefore, reason: 'inactive must NOT close the camera');

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();

        expect(openCount, 1, reason: 'camera must NOT re-open after inactive→resumed');
        expect(closeCount, closesBefore, reason: 'no close calls at any point');
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: 'viewfinder must still be live, not spinner');
      },
    );
  });

  group('QuickCaptureScreen Lifecycle', () {
    testWidgets(
      'inactive→resumed does NOT close or reload camera (status bar drag)',
      (tester) async {
        await tester.pumpWidget(buildQuickCaptureScreen());
        await tester.pumpAndSettle();

        expect(openCount, 1, reason: 'camera opened once on init');
        final closesBefore = closeCount;

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();

        expect(closeCount, closesBefore, reason: 'inactive must NOT close the camera');

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();

        expect(openCount, 1, reason: 'camera must NOT re-open after inactive→resumed');
        expect(closeCount, closesBefore, reason: 'no close calls at any point');
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: 'viewfinder must still be live, not spinner');
      },
    );
  });
}
