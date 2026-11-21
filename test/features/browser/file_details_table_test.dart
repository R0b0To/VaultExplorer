import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/widgets/file_details_table.dart';
import 'package:vaultexplorer/features/browser/widgets/tile_selection_style.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

const _columns = [
  FileDetailColumn.date,
  FileDetailColumn.size,
  FileDetailColumn.type,
];

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

FileDetailsHeader _header({
  SortBy sortBy = SortBy.name,
  bool ascending = true,
  ValueChanged<SortBy>? onSortBy,
}) => FileDetailsHeader(
  columns: _columns,
  sortBy: sortBy,
  sortAscending: ascending,
  onSortBy: onSortBy ?? (_) {},
  zoomLevel: 1.0,
  trailingSlotWidth: 36,
);

void main() {
  void useWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('FileDetailsTable.enabled', () {
    Future<bool> enabledIn(
      WidgetTester tester,
      Size window, {
      bool isCompact = true,
      List<FileDetailColumn> columns = _columns,
    }) async {
      useWindow(tester, window);
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = FileDetailsTable.enabled(
                context,
                isCompact: isCompact,
                columns: columns,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('only the compact layout on a wide window with columns', (
      tester,
    ) async {
      expect(await enabledIn(tester, const Size(1000, 800)), isTrue);
      expect(await enabledIn(tester, const Size(800, 1280)), isTrue);
      expect(await enabledIn(tester, const Size(411, 891)), isFalse);
      expect(
        await enabledIn(tester, const Size(1000, 800), isCompact: false),
        isFalse,
      );
      expect(
        await enabledIn(tester, const Size(1000, 800), columns: const []),
        isFalse,
      );
    });
  });

  group('FileDetailsHeader', () {
    testWidgets('names every column and sorts by the one tapped', (
      tester,
    ) async {
      useWindow(tester, const Size(1000, 800));
      final sorted = <SortBy>[];
      await tester.pumpWidget(_app(_header(onSortBy: sorted.add)));

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);

      await tester.tap(find.text('Date'));
      await tester.tap(find.text('Size'));
      await tester.tap(find.text('Type'));
      await tester.tap(find.text('Name'));
      expect(sorted, [
        SortBy.date,
        SortBy.size,
        SortBy.extension,
        SortBy.name,
      ]);
    });

    testWidgets('marks only the sorted column, with its direction', (
      tester,
    ) async {
      useWindow(tester, const Size(1000, 800));
      await tester.pumpWidget(
        _app(_header(sortBy: SortBy.date, ascending: false)),
      );
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

      await tester.pumpWidget(
        _app(_header(sortBy: SortBy.size, ascending: true)),
      );
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });

    testWidgets('lines up with the rows it heads', (tester) async {
      useWindow(tester, const Size(1000, 800));
      const entry = RawEntry(
        name: 'notes.txt',
        isDir: false,
        sizeBytes: 2048,
        modifiedSecs: 0,
      );
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              _header(),
              SizedBox(
                height: 44,
                child: FileRowShell(
                  icon: Icons.insert_drive_file_outlined,
                  iconColor: Colors.grey,
                  unselectedIconBackground: Colors.black12,
                  displayName: 'notes.txt',
                  entry: entry,
                  detailColumns: _columns,
                  tableColumns: true,
                  isCompact: true,
                  hasTrailingSlot: true,
                  trailing: const SizedBox(width: 32, height: 32),
                  isSelected: false,
                  onTap: () {},
                  onLongPress: () {},
                ),
              ),
            ],
          ),
        ),
      );

      // The date (no date recorded, so a dash) is left-aligned in its
      // column and the size right-aligned: each must start/end exactly where
      // the header's label does.
      final dateHeader = tester.getTopLeft(find.text('Date')).dx;
      final dateCell = tester.getTopLeft(find.text('—')).dx;
      expect(dateCell, closeTo(dateHeader, 0.5));

      final sizeHeader = tester.getTopRight(find.text('Size')).dx;
      final sizeCell = tester.getTopRight(find.text(formatBytes(2048))).dx;
      expect(sizeCell, closeTo(sizeHeader, 0.5));
    });
  });
}
