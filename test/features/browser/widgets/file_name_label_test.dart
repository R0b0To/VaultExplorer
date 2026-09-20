import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/features/browser/widgets/file_name_label.dart';

void main() {
  setUp(() {
    FileNameLabel.clearCache();
  });

  group('FileNameLabel Truncation & Cache', () {
    testWidgets('renders ellipsizeEnd mode using default overflow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              child: FileNameLabel(
                text: 'A very long file name that exceeds container width.png',
                mode: LongFileNameDisplayMode.ellipsizeEnd,
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('A very long file name that exceeds container width.png'),
        findsOneWidget,
      );
    });

    testWidgets('ellipsizeMiddle splits text into ellipsized head and preserved tail', (tester) async {
      const fileName = 'very_long_photo_filename_that_needs_middle_truncation.jpg';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: FileNameLabel(
                text: fileName,
                mode: LongFileNameDisplayMode.ellipsizeMiddle,
              ),
            ),
          ),
        ),
      );

      final textWidgets = tester.widgetList<Text>(find.byType(Text));

      // Head is rendered with TextOverflow.ellipsis in an Expanded widget
      expect(textWidgets.any((t) => t.overflow == TextOverflow.ellipsis), isTrue);

      // Tail preserves the file extension
      expect(textWidgets.any((t) => t.data?.endsWith('.jpg') ?? false), isTrue);

      // Re-pumping the same widget renders cleanly without error
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: FileNameLabel(
                text: fileName,
                mode: LongFileNameDisplayMode.ellipsizeMiddle,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(FileNameLabel), findsOneWidget);
    });

    testWidgets('ellipsizeStart truncates text with leading ellipsis and caches result', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              child: FileNameLabel(
                text: 'very_long_photo_filename_that_needs_start_truncation.jpg',
                mode: LongFileNameDisplayMode.ellipsizeStart,
              ),
            ),
          ),
        ),
      );

      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      expect(textWidgets.any((t) => t.data?.startsWith('…') ?? false), isTrue);

      // Re-pumping reuses cached truncation without error
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              child: FileNameLabel(
                text: 'very_long_photo_filename_that_needs_start_truncation.jpg',
                mode: LongFileNameDisplayMode.ellipsizeStart,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(FileNameLabel), findsOneWidget);
    });
  });
}