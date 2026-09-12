import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/share_import/share_destination_sheet.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

// --- In-memory test fakes ---

class _FakeAppSettingsService extends AppSettingsService {
  const _FakeAppSettingsService();

  @override
  Future<AppSettings> loadSettings() async => AppSettings();
}

/// A [ContainerRepository] whose [loadAll]/[loadOrder] don't resolve until
/// the test calls [releaseRecords] -- stands in for the real disk I/O
/// `VaultDashboardController._performLoadAll` awaits, so a test can freeze
/// the sheet at "still loading" and inspect it before letting the load
/// finish, instead of racing real file I/O timing.
class _GatedContainerRepository extends ContainerRepository {
  _GatedContainerRepository(super.cryptoApi) : super.withCryptoApi();

  final _recordsCompleter = Completer<Map<String, ContainerRecord>>();

  void releaseRecords(Map<String, ContainerRecord> records) {
    _recordsCompleter.complete(records);
  }

  @override
  Future<Map<String, ContainerRecord>> loadAll() => _recordsCompleter.future;

  @override
  Future<List<String>> loadOrder() async =>
      (await _recordsCompleter.future).keys.toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getActiveContainerSessions':
          return {'sessions': <Map<String, dynamic>>[]};
        case 'readAllSecure':
        case 'readAll':
          return <String, String>{};
        case 'deleteSecure':
        case 'writeSecure':
        case 'hasAllFilesAccess':
          return true;
        case 'syncBackgroundService':
          return null;
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
    'ShareDestinationSheet keeps showing progress indicator even if '
    'dashboardState.isLoading was initially false, until loadAll resolves',
    (tester) async {
      late _GatedContainerRepository gatedRepo;
      final container = ProviderContainer(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(
            const _FakeAppSettingsService(),
          ),
          containerRepositoryProvider.overrideWith((ref) {
            gatedRepo = _GatedContainerRepository(
              ref.watch(vaultCryptoApiProvider),
            );
            return gatedRepo;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ShareDestinationSheet(),
          ),
        ),
      );

      // Verify that while gatedRepo is unresolved, the indicator is always shown
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ShareDestinationSheet)),
      )!;
      expect(
        find.text(l10n.noVaultsAvailableAddFromDashboardPrompt),
        findsNothing,
      );

      // Release records
      gatedRepo.releaseRecords({
        'file:///vault_cold.hc': const ContainerRecord(
          uri: 'file:///vault_cold.hc',
          label: 'Cold Start Vault',
        ),
      });
      await tester.pumpAndSettle();

      expect(find.text('Cold Start Vault'), findsOneWidget);
      expect(
        find.text(l10n.noVaultsAvailableAddFromDashboardPrompt),
        findsNothing,
      );
    },
  );

  testWidgets(
    'ShareDestinationSheet shows a loading indicator -- not the "no '
    'vaults" prompt -- while the vault list is still loading, then lists '
    'a locked (never-mounted) vault once loading finishes',
    (tester) async {
      // Regression test for: opening the hidden-reveal door in Mask Mode
      // with only locked vaults (none currently unlocked) landed on the
      // "no vaults available, add one from the dashboard" empty state
      // instead of listing them, because ShareDestinationSheet judged
      // "empty" purely from the vault list, without accounting for
      // VaultDashboardController still being mid-load the very first
      // time this keepAlive provider is touched this session -- exactly
      // what happens reaching it via the hidden-reveal path, since
      // nothing else has read it yet. See VaultDashboardScreen's own
      // `!state.isLoading` guard for the pattern this now mirrors.
      late _GatedContainerRepository gatedRepo;
      final container = ProviderContainer(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(
            const _FakeAppSettingsService(),
          ),
          containerRepositoryProvider.overrideWith((ref) {
            gatedRepo = _GatedContainerRepository(
              ref.watch(vaultCryptoApiProvider),
            );
            return gatedRepo;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ShareDestinationSheet(),
          ),
        ),
      );

      // One frame: the sheet has mounted and kicked off loadAll(), but
      // _GatedContainerRepository hasn't resolved yet -- the moment a
      // fresh VaultDashboardController is in right after being read for
      // the very first time.
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ShareDestinationSheet)),
      )!;
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text(l10n.noVaultsAvailableAddFromDashboardPrompt),
        findsNothing,
      );

      // Now the load resolves with a single locked vault and nothing
      // mounted -- the exact locked-only scenario from the bug report.
      gatedRepo.releaseRecords({
        'file:///vault1.hc': const ContainerRecord(
          uri: 'file:///vault1.hc',
          label: 'Vault 1',
        ),
      });
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.noVaultsAvailableAddFromDashboardPrompt),
        findsNothing,
      );
      expect(find.text('Vault 1'), findsOneWidget);
    },
  );
}
