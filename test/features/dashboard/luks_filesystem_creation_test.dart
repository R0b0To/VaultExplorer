import 'package:flutter_localizations/flutter_localizations.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/features/dashboard/widgets/create_container_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/create_container_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/usb_create_container_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              height: 2000,
              width: 800,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  group('LUKS File System Creation State & Options', () {
    test('CreateContainerController preselects ext4 for LUKS1 and LUKS2', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(createContainerProvider.notifier);

      // Verify VeraCrypt default
      expect(container.read(createContainerProvider).fileSystem, 'FAT');

      // Switch to LUKS1
      controller.setFormat(CreateFormat.luks1);
      expect(container.read(createContainerProvider).format, CreateFormat.luks1);
      expect(container.read(createContainerProvider).fileSystem, 'ext4');

      // Switch to LUKS2
      controller.setFormat(CreateFormat.luks2);
      expect(container.read(createContainerProvider).format, CreateFormat.luks2);
      expect(container.read(createContainerProvider).fileSystem, 'ext4');

      // Switch back to VeraCrypt
      controller.setFormat(CreateFormat.veracrypt);
      expect(container.read(createContainerProvider).format, CreateFormat.veracrypt);
      expect(container.read(createContainerProvider).fileSystem, 'FAT');
    });

    test('UsbCreateContainerController preselects ext4 for LUKS1 and LUKS2', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(usbCreateContainerProvider.notifier);

      // Verify default
      expect(container.read(usbCreateContainerProvider).fileSystem, 'exFAT');

      // Switch to LUKS1
      controller.setFormat(CreateFormat.luks1);
      expect(container.read(usbCreateContainerProvider).format, CreateFormat.luks1);
      expect(container.read(usbCreateContainerProvider).fileSystem, 'ext4');

      // Switch to LUKS2
      controller.setFormat(CreateFormat.luks2);
      expect(container.read(usbCreateContainerProvider).format, CreateFormat.luks2);
      expect(container.read(usbCreateContainerProvider).fileSystem, 'ext4');
    });

    testWidgets('CreateContainerSheet renders format options within ProviderScope', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestableWidget(const CreateContainerSheet()));
      await tester.pumpAndSettle();

      final luks1Finder = find.text('LUKS1');
      expect(luks1Finder, findsOneWidget);

      final luks2Finder = find.text('LUKS2');
      expect(luks2Finder, findsOneWidget);
    });
  });
}