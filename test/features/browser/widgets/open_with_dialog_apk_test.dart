import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/widgets/open_with_dialog.dart';

/// A host screen with one button that opens the APK chooser and records what
/// it returned -- the same way `_showApkOpenChooser` consumes it.
class _Host extends StatefulWidget {
  const _Host({required this.onResult});
  final void Function(ApkOpenChoice) onResult;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () async {
          final choice = await OpenWithDialog.showApkChooser(
            context,
            fileName: 'app.apk',
            ext: 'apk',
          );
          widget.onResult(choice);
        },
        child: const Text('open'),
      ),
    );
  }
}

Widget _app({
  required void Function(ApkOpenChoice) onResult,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    // `builder` sits above the Navigator, so the dialog route -- which is
    // pushed on the root Navigator, not under `home` -- sees the text scale.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: _Host(onResult: onResult)),
  );
}

void _setSurface(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

void main() {
  group('OpenWithDialog.showApkChooser', () {
    testWidgets('offers both the package installer and Open as ZIP', (
      tester,
    ) async {
      await tester.pumpWidget(_app(onResult: (_) {}));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Package installer'), findsOneWidget);
      expect(find.text('Open as ZIP'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets("picking Open as ZIP returns 'archive', not remembered", (
      tester,
    ) async {
      ApkOpenChoice? result;
      await tester.pumpWidget(_app(onResult: (c) => result = c));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open as ZIP'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.action, 'archive');
      expect(result!.remember, isFalse);
    });

    testWidgets("picking the installer returns 'installer'", (tester) async {
      ApkOpenChoice? result;
      await tester.pumpWidget(_app(onResult: (c) => result = c));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Package installer'));
      await tester.pumpAndSettle();

      expect(result!.action, 'installer');
    });

    testWidgets('ticking "remember" is reported alongside the choice', (
      tester,
    ) async {
      ApkOpenChoice? result;
      await tester.pumpWidget(_app(onResult: (c) => result = c));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open as ZIP'));
      await tester.pumpAndSettle();

      expect(result!.action, 'archive');
      expect(result!.remember, isTrue);
    });

    testWidgets('cancel returns no action', (tester) async {
      ApkOpenChoice? result;
      await tester.pumpWidget(_app(onResult: (c) => result = c));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.action, isNull);
    });

    testWidgets('lays out without overflow in every locale (narrow, 2x text)', (
      tester,
    ) async {
      _setSurface(tester, 320, 800);
      for (final locale in AppLocalizations.supportedLocales) {
        await tester.pumpWidget(
          _app(onResult: (_) {}, locale: locale, textScale: 2.0),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow/layout error in locale ${locale.languageCode}',
        );

        // Close it so the next locale starts from a clean route stack.
        await tester.tap(find.byType(TextButton).last);
        await tester.pumpAndSettle();
      }
    });
  });
}
