import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_card.dart';

void main() {
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
