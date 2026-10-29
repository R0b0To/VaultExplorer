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
}
