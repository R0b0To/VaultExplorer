import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_body_view.dart';

MountedContainer _container() => MountedContainer(
      volId: 1,
      uri: 'file:///vault.hc',
      displayName: 'Vault',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
    );

void main() {
  group('MarkdownBodyView.bottomInset', () {
    // Uniform paragraphs so the lazy list's extent estimate is exact.
    final source = [for (var i = 0; i < 60; i++) 'Paragraph $i'].join('\n\n');

    Future<double> maxExtent(WidgetTester tester, double bottomInset) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: MarkdownBodyView(
                  source: source,
                  container: _container(),
                  currentFilePath: '/note.md',
                  onLinkTap: (_) {},
                  scrollController: controller,
                  bottomInset: bottomInset,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return controller.position.maxScrollExtent;
    }

    testWidgets('adds exactly that much scrollable space after the last block',
        (tester) async {
      final without = await maxExtent(tester, 0);
      final withInset = await maxExtent(tester, 40);

      expect(withInset - without, closeTo(40, 0.01));
    });
  });

  group('MarkdownBodyView ordered lists', () {
    Future<void> pump(WidgetTester tester, String source) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MarkdownBodyView(
                source: source,
                container: _container(),
                currentFilePath: '/note.md',
                onLinkTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('numbers of three or more digits are not clipped or wrapped',
        (tester) async {
      await pump(tester, '100. Grapes\n101. Carrot\n102. ter');

      for (final label in ['100.', '101.', '102.']) {
        // One line of body text. A clipped marker wraps onto several lines.
        expect(tester.getSize(find.text(label)).height, lessThan(24),
            reason: label);
      }

      // The item text still lines up across the list.
      final left = {
        for (final t in ['Grapes', 'Carrot', 'ter'])
          tester.getTopLeft(find.text(t, findRichText: true)).dx,
      };
      expect(left, hasLength(1));
    });

    testWidgets('a long list sizes the marker for its largest number',
        (tester) async {
      await pump(tester, '98. a\n99. b\n100. c');

      expect(tester.getSize(find.text('98.')).height, lessThan(24));
      expect(tester.getSize(find.text('100.')).height, lessThan(24));
    });
  });
}
