import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/dashboard_layout_mode.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_card_row.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_layout_views.dart';

MountedVaultItem _mounted({String name = 'Work vault', bool withSpace = true}) {
  final container = MountedContainer(
    uri: 'file:///work.vault',
    displayName: name,
    volId: 1,
    containerFormat: 'veracrypt',
    rootFiles: const [],
    mountedAt: DateTime(2026, 1, 1),
    totalSpace: withSpace ? 1000 * 1024 * 1024 : 0,
    freeSpace: withSpace ? 400 * 1024 * 1024 : 0,
  );
  return MountedVaultItem(container, sortDate: DateTime(2026, 1, 1));
}

LockedVaultItem _locked({String name = 'Archive vault'}) => LockedVaultItem(
  ContainerRecord(
    uri: 'file:///archive.vault',
    label: name,
    containerFormat: 'gocryptfs',
  ),
  sortDate: DateTime(2026, 1, 1),
);

Future<void> _pump(
  WidgetTester tester, {
  required VaultListItem item,
  required DashboardLayoutMode layout,
  required VoidCallback onOpen,
  double width = 360,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: VaultCardRow(
                  index: 0,
                  item: item,
                  record: null,
                  appSettings: AppSettings(),
                  onOpen: onOpen,
                  onEdit: () {},
                  onDelete: () {},
                  onLocked: (_) {},
                  dragEnabled: false,
                  layout: layout,
                  rowWidth: width,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('DashboardLayoutMode', () {
    test('round-trips through JSON', () {
      for (final mode in DashboardLayoutMode.values) {
        expect(DashboardLayoutMode.fromJson(mode.toJson()), mode);
      }
    });

    test('an unknown or missing value falls back to cards', () {
      expect(DashboardLayoutMode.fromJson(null), DashboardLayoutMode.cards);
      expect(DashboardLayoutMode.fromJson('???'), DashboardLayoutMode.cards);
    });

    test('is stored in the app settings; settings without it get cards', () {
      final settings = AppSettings()
        ..dashboardLayoutMode = DashboardLayoutMode.details;
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.dashboardLayoutMode, DashboardLayoutMode.details);

      final legacy = settings.toJson()..remove('dashboardLayoutMode');
      expect(
        AppSettings.fromJson(legacy).dashboardLayoutMode,
        DashboardLayoutMode.cards,
      );
    });
  });

  group('VaultDetailsColumns', () {
    test('drops columns as the width shrinks', () {
      final wide = VaultDetailsColumns.forWidth(1200);
      expect(wide.compact, isFalse);
      expect(wide.showFormat && wide.showTotal && wide.showUsage, isTrue);

      final medium = VaultDetailsColumns.forWidth(700);
      expect(medium.showFormat, isFalse);
      expect(medium.showTotal, isFalse);
      expect(medium.showUsage, isTrue);

      expect(VaultDetailsColumns.forWidth(360).compact, isTrue);
    });
  });

  for (final layout in DashboardLayoutMode.values) {
    group('${layout.name} layout', () {
      testWidgets('shows an unlocked vault and opens it on tap', (
        tester,
      ) async {
        var opened = 0;
        await _pump(
          tester,
          item: _mounted(),
          layout: layout,
          onOpen: () => opened++,
        );
        expect(find.text('Work vault'), findsOneWidget);
        await tester.tap(find.text('Work vault'));
        expect(opened, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('shows a locked vault and opens it on tap', (tester) async {
        var opened = 0;
        await _pump(
          tester,
          item: _locked(),
          layout: layout,
          onOpen: () => opened++,
        );
        expect(find.text('Archive vault'), findsOneWidget);
        await tester.tap(find.text('Archive vault'));
        expect(opened, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('does not overflow with a long name, big text, narrow cell', (
        tester,
      ) async {
        await _pump(
          tester,
          item: _mounted(
            name: 'A very long vault name that cannot possibly fit in a tile',
          ),
          layout: layout,
          onOpen: () {},
          width: 160,
          textScale: 1.6,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('an unlocked vault of unknown capacity has no usage bar', (
        tester,
      ) async {
        await _pump(
          tester,
          item: _mounted(withSpace: false),
          layout: layout,
          onOpen: () {},
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('grid tiles of locked and unlocked vaults have the same height', (
    tester,
  ) async {
    await _pump(
      tester,
      item: _mounted(),
      layout: DashboardLayoutMode.grid,
      onOpen: () {},
      width: 170,
    );
    final mountedHeight = tester.getSize(find.byType(VaultGridTile)).height;
    await _pump(
      tester,
      item: _locked(),
      layout: DashboardLayoutMode.grid,
      onOpen: () {},
      width: 170,
    );
    final lockedHeight = tester.getSize(find.byType(VaultGridTile)).height;
    expect(lockedHeight, mountedHeight);
  });

  testWidgets('details rows line up with the header columns', (tester) async {
    await _pump(
      tester,
      item: _mounted(),
      layout: DashboardLayoutMode.details,
      onOpen: () {},
      width: 1000,
    );
    expect(find.text('Unlocked'), findsOneWidget);
    expect(find.text('VeraCrypt'), findsOneWidget);
    expect(find.text('40%'), findsNothing);
    expect(find.text('60%'), findsOneWidget);
  });
}
