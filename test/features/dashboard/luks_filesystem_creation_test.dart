import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';
import 'package:vaultexplorer/features/dashboard/widgets/create_container_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/usb_create_container_sheet.dart';
import 'package:vaultexplorer/core/widgets/inputs/option_picker_tile.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
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
    );
  }

  group('LUKS File System Creation Options', () {
    testWidgets('CreateContainerSheet preselects ext4 for LUKS1 and LUKS2 while exposing all file systems', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestableWidget(const CreateContainerSheet()));
      await tester.pumpAndSettle();

      // Tap LUKS1
      final luks1Finder = find.text('LUKS1');
      expect(luks1Finder, findsOneWidget);
      await tester.ensureVisible(luks1Finder);
      await tester.tap(luks1Finder);
      await tester.pumpAndSettle();

      // Scroll to ExpansionTile if needed
      final advancedTileFinder = find.byType(ExpansionTile);
      expect(advancedTileFinder, findsOneWidget);
      await tester.ensureVisible(advancedTileFinder);
      await tester.tap(advancedTileFinder);
      await tester.pumpAndSettle();

      // Find OptionPickerTile containing filesystem choices ('ext4')
      final fsTileFinder = find.byWidgetPredicate(
        (w) => w is OptionPickerTile<String> && w.options.any((o) => o.value == 'ext4'),
      );
      expect(fsTileFinder, findsOneWidget);

      final tileWidget = tester.widget<OptionPickerTile<String>>(fsTileFinder);
      expect(tileWidget.value, 'ext4');
      final optionValues = tileWidget.options.map((o) => o.value).toList();
      expect(optionValues, containsAll(['FAT', 'exFAT', 'NTFS', 'ext2', 'ext3', 'ext4']));

      // Switch to LUKS2 and verify ext4 remains preselected and all file systems remain available
      final luks2Finder = find.text('LUKS2');
      expect(luks2Finder, findsOneWidget);
      await tester.ensureVisible(luks2Finder);
      await tester.tap(luks2Finder);
      await tester.pumpAndSettle();

      final tileWidget2 = tester.widget<OptionPickerTile<String>>(fsTileFinder);
      expect(tileWidget2.value, 'ext4');
      final optionValues2 = tileWidget2.options.map((o) => o.value).toList();
      expect(optionValues2, containsAll(['FAT', 'exFAT', 'NTFS', 'ext2', 'ext3', 'ext4']));
    });

    testWidgets('UsbCreateContainerSheet preselects ext4 for LUKS format while exposing all file systems', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestableWidget(const UsbCreateContainerSheet()));
      await tester.pump();

      // Tap LUKS2 format
      final luks2Finder = find.text('LUKS2');
      expect(luks2Finder, findsOneWidget);
      await tester.ensureVisible(luks2Finder);
      await tester.tap(luks2Finder);
      await tester.pump();

      // Scroll and expand Advanced Parameters
      final advancedTileFinder = find.byType(ExpansionTile);
      expect(advancedTileFinder, findsOneWidget);
      await tester.ensureVisible(advancedTileFinder);
      await tester.tap(advancedTileFinder);
      await tester.pump();

      // Find OptionPickerTile containing filesystem choices ('ext4')
      final fsTileFinder = find.byWidgetPredicate(
        (w) => w is OptionPickerTile<String> && w.options.any((o) => o.value == 'ext4'),
      );
      expect(fsTileFinder, findsOneWidget);

      final tileWidget = tester.widget<OptionPickerTile<String>>(fsTileFinder);
      expect(tileWidget.value, 'ext4');
      final optionValues = tileWidget.options.map((o) => o.value).toList();
      expect(optionValues, containsAll(['FAT', 'exFAT', 'NTFS', 'ext2', 'ext3', 'ext4']));
    });
  });
}
