import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/widgets/grid_card_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

Widget buildShell({
  required bool showFileName,
  String label = 'My Item',
  VoidCallback? onTap,
  VoidCallback? onLongPress,
  double? aspectRatio,
  double? height,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 200,
        // Standard grid items (aspectRatio == null) need a bounded height for Expanded.
        // Masonry items (aspectRatio != null) size dynamically to their content.
        height: height ?? (aspectRatio != null ? null : 200),
        child: GridCardShell(
          preview: const ColoredBox(color: Colors.blue),
          label: label,
          isSelected: false,
          isSelectionMode: false,
          showFileName: showFileName,
          onTap: onTap ?? () {},
          onLongPress: onLongPress ?? () {},
          aspectRatio: aspectRatio,
        ),
      ),
    ),
  );
}

  group('GridCardShell label visibility', () {
    testWidgets('renders the label when showFileName is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildShell(showFileName: true, label: 'Vacation Photos'),
      );

      expect(find.text('Vacation Photos'), findsOneWidget);
    });

    testWidgets('hides the label when showFileName is false', (tester) async {
      await tester.pumpWidget(
        buildShell(showFileName: false, label: 'Vacation Photos'),
      );

      expect(find.text('Vacation Photos'), findsNothing);
    });

    testWidgets('folder-style usage (showFileName: true) stays visible '
        'independent of aspect ratio mode used by masonry items', (
      tester,
    ) async {
      // Masonry items pass an explicit aspectRatio; grid items leave it
      // null. Folder cells always pass showFileName: true regardless of
      // which view renders them (see FileGridView/_buildDirCell and
      // FileMasonryView/_buildDirCell), so the label must show in both.
      await tester.pumpWidget(
        buildShell(showFileName: true, label: 'Documents', aspectRatio: 1.0),
      );

      expect(find.text('Documents'), findsOneWidget);
    });
  });

  group('GridCardShell interaction regressions', () {
    testWidgets('tap and long-press still fire when the label is hidden', (
      tester,
    ) async {
      var tapped = false;
      var longPressed = false;

      await tester.pumpWidget(
        buildShell(
          showFileName: false,
          onTap: () => tapped = true,
          onLongPress: () => longPressed = true,
        ),
      );

      await tester.tap(find.byType(GridCardShell));
      expect(tapped, isTrue);

      await tester.longPress(find.byType(GridCardShell));
      expect(longPressed, isTrue);
    });

    testWidgets('tap and long-press still fire when the label is shown', (
      tester,
    ) async {
      var tapped = false;
      var longPressed = false;

      await tester.pumpWidget(
        buildShell(
          showFileName: true,
          onTap: () => tapped = true,
          onLongPress: () => longPressed = true,
        ),
      );

      await tester.tap(find.byType(GridCardShell));
      expect(tapped, isTrue);

      await tester.longPress(find.byType(GridCardShell));
      expect(longPressed, isTrue);
    });
  });
}
