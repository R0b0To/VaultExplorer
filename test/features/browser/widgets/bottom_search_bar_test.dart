import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/widgets/bottom_search_bar.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

Widget _wrapWithApp({
  required Widget child,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  testWidgets('BottomSearchBar respects 3-button navigation when keyboard is dismissed', (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 144); // 48dp * 3.0 ratio
    tester.view.devicePixelRatio = 3.0;

    await tester.pumpWidget(
      _wrapWithApp(
        child: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BottomSearchBar(
                  initialQuery: '',
                  onChanged: (_) {},
                  onClose: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final outerPadding = tester.widget<Padding>(
      find.ancestor(
        of: find.byType(Material),
        matching: find.byType(Padding),
      ).first,
    );
    // 48dp (nav bar) + 8dp = 56dp
    expect((outerPadding.padding as EdgeInsets).bottom, 56.0);
  });

  testWidgets('BottomSearchBar respects 3-button navigation even when Scaffold stripped MediaQuery padding', (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 144); // 48dp * 3.0 ratio
    tester.view.devicePixelRatio = 3.0;

    await tester.pumpWidget(
      _wrapWithApp(
        child: Builder(
          builder: (context) {
            return MediaQuery.removePadding(
              removeBottom: true,
              context: context,
              child: Scaffold(
                body: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: BottomSearchBar(
                        initialQuery: '',
                        onChanged: (_) {},
                        onClose: () {},
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    final outerPadding = tester.widget<Padding>(
      find.ancestor(
        of: find.byType(Material),
        matching: find.byType(Padding),
      ).first,
    );
    // Even though MediaQuery.padding.bottom is 0, View.of(context) fallback provides 48dp + 8dp = 56dp
    expect((outerPadding.padding as EdgeInsets).bottom, 56.0);
  });

  testWidgets('BottomSearchBar sits directly above keyboard when keyboard is open', (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 144); // 48dp * 3.0 ratio
    tester.view.viewInsets = const FakeViewPadding(bottom: 900); // 300dp * 3.0 ratio
    tester.view.devicePixelRatio = 3.0;

    await tester.pumpWidget(
      _wrapWithApp(
        child: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BottomSearchBar(
                  initialQuery: '',
                  onChanged: (_) {},
                  onClose: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final outerPadding = tester.widget<Padding>(
      find.ancestor(
        of: find.byType(Material),
        matching: find.byType(Padding),
      ).first,
    );
    // 300dp (keyboard) + 8dp = 308dp (no double-padding of nav bar over keyboard)
    expect((outerPadding.padding as EdgeInsets).bottom, 308.0);
  });
}
