import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_card.dart';

// --- In-memory test fakes ---

class FakeAppSettingsService extends AppSettingsService {
  const FakeAppSettingsService();

  @override
  Future<AppSettings> loadSettings() async => AppSettings();

  @override
  Future<void> saveSettings(AppSettings settings) async {}

  @override
  Future<void> saveMasterPassword(
    AppSettings settings,
    String hash,
    String salt,
  ) async {}

  @override
  Future<void> clearMasterPassword(AppSettings settings) async {}
}

class FakeContainerRepository extends ContainerRepository {
  FakeContainerRepository(super.cryptoApi) : super.withCryptoApi();

  @override
  Future<Map<String, ContainerRecord>> loadAll() async => const {};

  @override
  Future<List<String>> loadOrder() async => const [];

  @override
  Future<void> save(ContainerRecord record) async {}

  @override
  Future<void> saveOrder(List<String> orderedUris) async {}

  @override
  Future<void> remove(String uri) async {}
}

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
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'lockContainer':
          return true;
        case 'deleteSecure':
          return true;
        case 'readSecure':
          return null;
        case 'readAllSecure':
        case 'readAll':
          return <String, String>{};
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
          return true;
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
      final container = ProviderContainer(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(const FakeAppSettingsService()),
          containerRepositoryProvider.overrideWith(
            (ref) => FakeContainerRepository(ref.watch(vaultCryptoApiProvider)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(vaultDashboardControllerProvider.notifier);
      await controller.loadAll();

      final vaultA = _testContainer(volId: 1, uri: 'file:///vaultA.hc', name: 'Vault A');
      final vaultB = _testContainer(volId: 2, uri: 'file:///vaultB.hc', name: 'Vault B');
      controller.onContainerMounted(vaultA);
      controller.onContainerMounted(vaultB);

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
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final mounted = ref.watch(vaultDashboardControllerProvider).mounted;
                  return Column(
                    children: mounted.map((c) {
                      final key = c.volId == vaultA.volId ? vaultAKey : vaultBKey;
                      return ContainerCard(
                        key: key,
                        container: c,
                        onLocked: controller.onContainerLocked,
                        onBrowse: () {},
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byKey(vaultAKey), findsOneWidget);
      expect(find.byKey(vaultBKey), findsOneWidget);

      // Matches material_ui's FilledButton correctly
      final vaultALockButton = find.descendant(
        of: find.byKey(vaultAKey),
        matching: find.byType(FilledButton),
      );
      expect(vaultALockButton, findsOneWidget);

      // Tap lock button on Vault A
      await tester.tap(vaultALockButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Assert state: Vault A removed from controller, Vault B intact
      final state = container.read(vaultDashboardControllerProvider);
      expect(state.mounted, hasLength(1));
      expect(state.mounted.single.volId, vaultB.volId);

      // Assert UI: Vault A card is gone, Vault B card remains
      expect(find.byKey(vaultAKey), findsNothing);
      expect(find.byKey(vaultBKey), findsOneWidget);

      // Confirm locking one container did not trigger app-wide lock
      expect(enforceAppLockCalls, 0);
      expect(lockAllMountedContainersCalls, 0);
    },
  );
}