import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_title_bar.dart';
import 'package:vaultexplorer/features/dashboard/widgets/app_navigation_drawer.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DrawerFooterStrip', () {
    testWidgets('shows Tools and Settings without a footer hide button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(DrawerFooterStrip(onTools: () {}, onSettings: () {})),
      );

      expect(find.byTooltip('Hide side menu'), findsNothing);
      expect(find.byIcon(Icons.build_rounded), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });
  });

  group('DesktopWindowTitleBar leading sidebar toggle', () {
    testWidgets('taps leading toggle immediately when leadingDraggable is true', (
      tester,
    ) async {
      var toggled = 0;
      await tester.pumpWidget(
        _app(
          DesktopWindowTitleBar(
            height: 32,
            leadingWidth: 296,
            leadingDraggable: true,
            leading: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: 48,
                height: 32,
                child: IconButton(
                  icon: const Icon(Icons.menu_open_rounded, size: 18),
                  tooltip: 'Hide side menu',
                  onPressed: () => toggled++,
                ),
              ),
            ),
            tabs: const SizedBox.shrink(),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Hide side menu'));
      await tester.pump();
      expect(toggled, 1);
    });
  });
}