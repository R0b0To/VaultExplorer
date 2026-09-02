// Regression coverage for: "closing/locking a single vault while another
// vault is open must only affect that one vault -- it must never tear down
// the other mounted vault or trigger the app-wide master-password lock
// gate (SessionLockController.enforceAppLock)."
//
// Unlike vault_dashboard_controller_test.dart (which calls
// VaultDashboardController methods directly), this test drives the *real*
// ContainerCard / _LockButton widget the user actually taps, wired up to a
// real SessionLockController the same way VaultDashboardScreen.initState()
// wires it -- so a future regression that accidentally couples
// onContainerLocked to enforceAppLock/performAutoLock would be caught here.
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_card.dart';

MountedContainer _testContainer({
  required int volId,
  required String uri,
  required String name,
}) =>
    MountedContainer(
      volId: volId,
      uri: uri,
      displayName: name,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      containerFormat: 'veracrypt',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'lockContainer':
          return true;
        case 'deleteSecure':
          return true;
        case 'readSecure':
          return null;
        case 'writeSecure':
          return true;
        case 'syncBackgroundService':
          return null;
        case 'getSpaceInfo':
          return [1000000, 500000];
        case 'hasAllFilesAccess':
          return true;
        case 'getActiveContainerSessions':
          return {'sessions': <Map<String, dynamic>>[]};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'tapping the lock button on Vault A while Vault B is open leaves Vault '
    'B mounted and never triggers enforceAppLock',
    (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(vaultDashboardControllerProvider.notifier);
      await controller.loadAll();

      final vaultA = _testContainer(volId: 1, uri: 'file:///vaultA.hc', name: 'Vault A');
      final vaultB = _testContainer(volId: 2, uri: 'file:///vaultB.hc', name: 'Vault B');
      controller.onContainerMounted(vaultA);
      controller.onContainerMounted(vaultB);

      // Wire SessionLockController exactly the way VaultDashboardScreen
      // does in initState(), so we can assert enforceAppLock is never
      // reached as a side effect of locking a single container.
      var enforceAppLockCalls = 0;
      var lockAllMountedContainersCalls = 0;
      container.read(sessionLockControllerProvider).configure(
            settings: () => container.read(vaultDashboardControllerProvider).appSettings,
            lockAllMountedContainers: () async {
              lockAllMountedContainersCalls++;
            },
            enforceAppLock: () {
              enforceAppLockCalls++;
            },
          );

      const vaultAKey = ValueKey('vaultA-card');
      const vaultBKey = ValueKey('vaultB-card');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  ContainerCard(
                    key: vaultAKey,
                    container: vaultA,
                    onLocked: controller.onContainerLocked,
                    onBrowse: () {},
                  ),
                  ContainerCard(
                    key: vaultBKey,
                    container: vaultB,
                    onLocked: controller.onContainerLocked,
                    onBrowse: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(vaultAKey), findsOneWidget);
      expect(find.byKey(vaultBKey), findsOneWidget);

      final vaultALockButton = find.descendant(
        of: find.byKey(vaultAKey),
        matching: find.byType(FilledButton),
      );
      expect(vaultALockButton, findsOneWidget);

      await tester.tap(vaultALockButton);
      await tester.pumpAndSettle();

      // Vault A is gone, Vault B is untouched.
      final state = container.read(vaultDashboardControllerProvider);
      expect(state.mounted, hasLength(1));
      expect(state.mounted.single.volId, vaultB.volId);
      expect(find.byKey(vaultBKey), findsOneWidget);

      // Locking one container must never cascade into the app-wide lock
      // gate or a "lock everything" sweep.
      expect(enforceAppLockCalls, 0);
      expect(lockAllMountedContainersCalls, 0);
    },
  );
}
