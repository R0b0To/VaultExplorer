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

      expect(find.text('A very long file name that exceeds container width.png'), findsOneWidget);
    });

    testWidgets('ellipsizeMiddle truncates text and caches result', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              child: FileNameLabel(
                text: 'very_long_photo_filename_that_needs_middle_truncation.jpg',
                mode: LongFileNameDisplayMode.ellipsizeMiddle,
              ),
            ),
          ),
        ),
      );

      // Verify that text contains the ellipsis
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      expect(textWidgets.any((t) => t.data?.contains('…') ?? false), isTrue);

      // Re-pumping the same widget should reuse cached truncation without error
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 80,
              child: FileNameLabel(
                text: 'very_long_photo_filename_that_needs_middle_truncation.jpg',
                mode: LongFileNameDisplayMode.ellipsizeMiddle,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(FileNameLabel), findsOneWidget);
    });

    testWidgets('ellipsizeStart truncates text with leading ellipsis', (tester) async {
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
    });
  });
}
