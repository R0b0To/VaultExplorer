import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/dashboard/widgets/cryptomator_upgrade_tile.dart';
import 'package:vaultexplorer/features/dashboard/widgets/migrate_cryptomator_vault_screen.dart';

class _MigrateApi implements VaultLifecycleApi {
  final List<(String, String)> calls = [];
  Object? error;

  @override
  Future<bool> migrateCryptomatorVault(String folderUri, String password) async {
    calls.add((folderUri, password));
    if (error != null) throw error!;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const uri = 'content://tree/vault';

  Widget app(Widget child, {_MigrateApi? api}) => ProviderScope(
    overrides: [
      if (api != null) vaultLifecycleApiProvider.overrideWith((ref) => api),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  Widget tile(
    CryptomatorVaultFormat format, {
    bool unlocked = false,
    VoidCallback? onUpgraded,
  }) => CryptomatorUpgradeTile(
    uri: uri,
    format: format,
    vaultIsUnlocked: unlocked,
    onUpgraded: onUpgraded ?? () {},
  );

  group('CryptomatorUpgradeTile', () {
    testWidgets('is hidden for current, too-old and unknown vaults', (tester) async {
      for (final format in [
        CryptomatorVaultFormat.current,
        CryptomatorVaultFormat.tooOld,
        CryptomatorVaultFormat.unknown,
      ]) {
        await tester.pumpWidget(app(tile(format)));
        expect(find.byType(ListTile), findsNothing, reason: '$format');
      }
    });

    testWidgets('is enabled for a locked format 7 vault', (tester) async {
      await tester.pumpWidget(app(tile(CryptomatorVaultFormat.legacy7)));
      expect(find.text('Upgrade vault format'), findsOneWidget);
      expect(find.text('This vault uses the older format 7.'), findsOneWidget);
      expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, isTrue);
    });

    testWidgets('is disabled, with the lock-first hint, while the vault is unlocked', (tester) async {
      await tester.pumpWidget(app(tile(CryptomatorVaultFormat.legacy7, unlocked: true)));
      expect(find.text('Lock the vault to upgrade it'), findsOneWidget);
      final listTile = tester.widget<ListTile>(find.byType(ListTile));
      expect(listTile.enabled, isFalse);
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.byType(MigrateCryptomatorVaultScreen), findsNothing);
    });

    testWidgets('a missing vault.cryptomator is a warning only, never an upgrade', (tester) async {
      await tester.pumpWidget(app(tile(CryptomatorVaultFormat.configMissing)));
      expect(find.textContaining('vault.cryptomator is missing'), findsOneWidget);
      expect(find.text('Upgrade vault format'), findsNothing);
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.byType(MigrateCryptomatorVaultScreen), findsNothing);
    });

    testWidgets('tapping opens the upgrade screen', (tester) async {
      await tester.pumpWidget(app(tile(CryptomatorVaultFormat.legacy7), api: _MigrateApi()));
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.byType(MigrateCryptomatorVaultScreen), findsOneWidget);
    });
  });

  group('MigrateCryptomatorVaultScreen', () {
    Finder upgradeButton() => find.widgetWithText(FilledButton, 'Upgrade');

    testWidgets('the Upgrade button needs both a password and the confirmation', (tester) async {
      await tester.pumpWidget(app(const MigrateCryptomatorVaultScreen(uri: uri), api: _MigrateApi()));
      expect(tester.widget<FilledButton>(upgradeButton()).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.pump();
      expect(tester.widget<FilledButton>(upgradeButton()).onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(tester.widget<FilledButton>(upgradeButton()).onPressed, isNotNull);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(tester.widget<FilledButton>(upgradeButton()).onPressed, isNull);
    });

    testWidgets('a wrong password shows an inline error and stays on the screen', (tester) async {
      final api = _MigrateApi()..error = PlatformException(code: 'AUTH_FAIL');
      await tester.pumpWidget(app(const MigrateCryptomatorVaultScreen(uri: uri), api: api));
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(upgradeButton());
      await tester.pumpAndSettle();

      expect(find.text('Incorrect password'), findsOneWidget);
      expect(find.byType(MigrateCryptomatorVaultScreen), findsOneWidget);
      expect(api.calls, [(uri, 'bad')]);
    });

    testWidgets('success pops with true so the caller can re-probe', (tester) async {
      final api = _MigrateApi();
      var upgraded = 0;
      await tester.pumpWidget(
        app(tile(CryptomatorVaultFormat.legacy7, onUpgraded: () => upgraded++), api: api),
      );
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(upgradeButton());
      await tester.pumpAndSettle();

      expect(api.calls, [(uri, 'secret')]);
      expect(find.byType(MigrateCryptomatorVaultScreen), findsNothing);
      expect(upgraded, 1);
    });
  });
}
