import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_app_bar_builder.dart';

void main() {
  Widget buildTestWidget({
    required int dirCount,
    required int fileCount,
    required bool isFiltered,
    required int? freeSpace,
  }) {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => buildBrowserAppBarStatsSubtitle(
            context,
            dirCount: dirCount,
            fileCount: fileCount,
            isFiltered: isFiltered,
            freeSpace: freeSpace,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'buildBrowserAppBarStatsSubtitle omits free space when freeSpace is null',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          dirCount: 2,
          fileCount: 5,
          isFiltered: false,
          freeSpace: null,
        ),
      );

      expect(find.textContaining('free'), findsNothing);
      expect(find.textContaining('2 folders · 5 files'), findsOneWidget);
    },
  );

  testWidgets(
    'buildBrowserAppBarStatsSubtitle shows free space when freeSpace is provided',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          dirCount: 1,
          fileCount: 3,
          isFiltered: false,
          freeSpace: 500 * 1024 * 1024,
        ),
      );

      expect(find.textContaining('500 MB free'), findsOneWidget);
    },
  );

  testWidgets(
    'buildBrowserAppBarStatsSubtitle displays 0 B free only when freeSpace is explicitly 0',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          dirCount: 0,
          fileCount: 0,
          isFiltered: false,
          freeSpace: 0,
        ),
      );

      expect(find.textContaining('0 B free'), findsOneWidget);
    },
  );
}
