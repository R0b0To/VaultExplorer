import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_clipboard_chip.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('AppBarClipboardButton long press triggers onPaste directly', (tester) async {
    bool pasteCalled = false;
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Populate clipboard via Riverpod provider notifier
    container.read(crossContainerClipboardProvider.notifier).set(
      volId: 1,
      displayName: 'Test Vault',
      cut: false,
      clipItems: [
        const ClipboardItem(
          path: '/test/file.txt',
          isDir: false,
          sizeBytes: 100,
        ),
      ],
    );

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
            appBar: AppBar(
              actions: [
                AppBarClipboardButton(
                  onPaste: () {
                    pasteCalled = true;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AppBarClipboardButton), findsOneWidget);

    // Long press on the clipboard button
    await tester.longPress(find.byType(AppBarClipboardButton));
    await tester.pumpAndSettle();

    expect(pasteCalled, isTrue);

    // Clean up clipboard
    container.read(crossContainerClipboardProvider.notifier).clear();
  });
}