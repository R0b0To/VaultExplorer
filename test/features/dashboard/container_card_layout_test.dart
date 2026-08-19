import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_card.dart';

void main() {
  testWidgets(
    'ContainerCard shows occupied space (not total/free) for folder vaults',
    (WidgetTester tester) async {
      // Folder vaults (Cryptomator/gocryptfs/CryFS) have no fixed container
      // size, so totalSpace/freeSpace stay at the "unknown" sentinel (-1)
      // and only occupiedSpace -- the vault's own recursively-computed
      // content size -- should be reflected on the card.
      final folderVaultContainer = MountedContainer(
        uri: 'content://test/folder_vault',
        displayName: 'Folder Vault',
        volId: 2,
        containerFormat: 'gocryptfs',
        rootFiles: const [],
        mountedAt: DateTime(2026, 1, 1),
        totalSpace: -1,
        freeSpace: -1,
        occupiedSpace: 42 * 1024 * 1024,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ContainerCard(
              container: folderVaultContainer,
              onLocked: (_) {},
              onBrowse: () {},
            ),
          ),
        ),
      );

      final expectedText = AppLocalizations.delegate
          .load(const Locale('en'))
          .then((l10n) => l10n.vaultOccupiedSpaceSummary(formatBytes(42 * 1024 * 1024)));

      expect(find.textContaining('used'), findsOneWidget);
      expect(find.text(await expectedText), findsOneWidget);
      // No progress bar comparison is drawn for folder vaults -- confirmed
      // indirectly by containerSpaceSummary's "free · total" text being
      // absent.
      expect(find.textContaining('·'), findsNothing);
    },
  );

  testWidgets('SavedContainerCard and ContainerCard have identical height to prevent CLS', (WidgetTester tester) async {
    final mountedContainer = MountedContainer(
      uri: 'file:///test_vault',
      displayName: 'Test Vault',
      volId: 1,
      containerFormat: 'veracrypt',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SavedContainerCard(
                  key: const ValueKey('locked'),
                  name: 'Test Vault',
                  uri: 'file:///test_vault',
                  containerFormat: 'veracrypt',
                  onUnlock: () {},
                ),
                ContainerCard(
                  key: const ValueKey('mounted'),
                  container: mountedContainer,
                  onLocked: (_) {},
                  onBrowse: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final lockedSize = tester.getSize(find.byKey(const ValueKey('locked')));
    final mountedSize = tester.getSize(find.byKey(const ValueKey('mounted')));

    expect(
      lockedSize.height,
      equals(mountedSize.height),
      reason: 'Container cards must maintain identical height when locked/unlocked to avoid Cumulative Layout Shift (CLS)',
    );
  });
}