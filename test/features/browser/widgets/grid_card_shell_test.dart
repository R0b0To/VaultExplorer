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

  group('GridCardShell corner radius', () {
    Widget shell({double? cornerRadius}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: GridCardShell(
              preview: const ColoredBox(color: Colors.blue),
              label: 'Item',
              isSelected: false,
              isSelectionMode: false,
              onTap: () {},
              onLongPress: () {},
              cornerRadius: cornerRadius ?? 12.0,
            ),
          ),
        ),
      );
    }

    BorderRadius radiusOf(WidgetTester tester) {
      final card = tester.widget<Card>(find.byType(Card));
      return (card.shape! as RoundedRectangleBorder).borderRadius
          as BorderRadius;
    }

    testWidgets('defaults to the rounded 12px look', (tester) async {
      await tester.pumpWidget(shell());
      expect(radiusOf(tester), BorderRadius.circular(12));
    });

    testWidgets('a zero radius gives square corners', (tester) async {
      await tester.pumpWidget(shell(cornerRadius: 0));
      expect(radiusOf(tester), BorderRadius.zero);
    });
  });

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

  group('GridCardShell 3-dots button', () {
    Widget shell({
      VoidCallback? onTap,
      VoidCallback? onMoreTap,
      bool showMoreButton = true,
      bool showFileName = true,
      bool isSelectionMode = false,
      bool isPlaceholder = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: GridCardShell(
              preview: const ColoredBox(color: Colors.blue),
              label: 'Item',
              isSelected: false,
              isSelectionMode: isSelectionMode,
              isPlaceholder: isPlaceholder,
              showFileName: showFileName,
              onTap: onTap ?? () {},
              onLongPress: () {},
              onMoreTap: onMoreTap,
              showMoreButton: showMoreButton,
            ),
          ),
        ),
      );
    }

    final moreIcon = find.byIcon(Icons.more_vert_rounded);

    testWidgets('is shown when a handler is provided', (tester) async {
      await tester.pumpWidget(shell(onMoreTap: () {}));

      expect(moreIcon, findsOneWidget);
    });

    testWidgets('sits in the file name row, after the name', (tester) async {
      await tester.pumpWidget(shell(onMoreTap: () {}));

      final icon = tester.getCenter(moreIcon);
      final name = tester.getCenter(find.text('Item'));
      expect((icon.dy - name.dy).abs(), lessThan(1.0));
      expect(icon.dx, greaterThan(name.dx));
    });

    testWidgets('opens the menu without also activating the card', (
      tester,
    ) async {
      var cardTaps = 0;
      var menuTaps = 0;
      await tester.pumpWidget(
        shell(onTap: () => cardTaps++, onMoreTap: () => menuTaps++),
      );

      await tester.tap(moreIcon);

      expect(menuTaps, 1);
      expect(cardTaps, 0);
    });

    testWidgets('is hidden when there is no handler', (tester) async {
      await tester.pumpWidget(shell());

      expect(moreIcon, findsNothing);
    });

    testWidgets('is hidden when the setting turns it off', (tester) async {
      await tester.pumpWidget(shell(onMoreTap: () {}, showMoreButton: false));

      expect(moreIcon, findsNothing);
    });

    testWidgets('is hidden while selecting', (tester) async {
      await tester.pumpWidget(shell(onMoreTap: () {}, isSelectionMode: true));

      expect(moreIcon, findsNothing);
    });

    testWidgets('is hidden on placeholders', (tester) async {
      await tester.pumpWidget(shell(onMoreTap: () {}, isPlaceholder: true));

      expect(moreIcon, findsNothing);
    });

    testWidgets('keeps the name and card height steady when it hides', (
      tester,
    ) async {
      await tester.pumpWidget(shell(onMoreTap: () {}));
      final nameBefore = tester.getCenter(find.text('Item'));
      final heightBefore = tester.getSize(find.byType(Card)).height;

      await tester.pumpWidget(shell(onMoreTap: () {}, isSelectionMode: true));

      expect(tester.getCenter(find.text('Item')), nameBefore);
      expect(tester.getSize(find.byType(Card)).height, heightBefore);
    });

    testWidgets('falls back to the preview corner when the name is hidden', (
      tester,
    ) async {
      var menuTaps = 0;
      await tester.pumpWidget(
        shell(showFileName: false, onMoreTap: () => menuTaps++),
      );

      expect(moreIcon, findsOneWidget);
      // No name row exists, so it is overlaid on the preview, top right.
      final icon = tester.getCenter(moreIcon);
      final card = tester.getRect(find.byType(Card));
      expect(icon.dy, lessThan(card.center.dy));
      expect(icon.dx, greaterThan(card.center.dx));

      await tester.tap(moreIcon);
      expect(menuTaps, 1);
    });
  });
}
