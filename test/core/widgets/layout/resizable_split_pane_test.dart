import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/layout/resizable_split_pane.dart';

Widget _host({
  required bool? collapsed,
  required ValueChanged<bool> onCollapsed,
  Axis axis = Axis.vertical,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: ResizableSplitPane(
          axis: axis,
          initialFraction: 0.7,
          minFirstExtent: 100,
          minSecondExtent: 100,
          collapseSecondOnResize: true,
          collapsedSecondExtent: 0,
          dividerExtent: 12,
          toggleSecondOnHandleTap: true,
          secondCollapsed: collapsed,
          onSecondCollapsedChanged: onCollapsed,
          first: const SizedBox.expand(key: Key('first')),
          second: const SizedBox.expand(key: Key('second')),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping the handle folds the second child and unfolds it', (
    tester,
  ) async {
    final reported = <bool>[];
    await tester.pumpWidget(_host(collapsed: null, onCollapsed: reported.add));
    expect(find.byKey(const Key('second')), findsOneWidget);

    final handle = find.byIcon(Icons.keyboard_arrow_down_rounded);
    expect(handle, findsOneWidget);
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(reported, [true]);
    expect(find.byKey(const Key('second')), findsNothing);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pumpAndSettle();
    expect(reported, [true, false]);
    expect(find.byKey(const Key('second')), findsOneWidget);
  });

  testWidgets('dragging the handle until little is left folds the child', (
    tester,
  ) async {
    final reported = <bool>[];
    await tester.pumpWidget(_host(collapsed: null, onCollapsed: reported.add));

    await tester.drag(
      find.byIcon(Icons.keyboard_arrow_down_rounded),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(reported, [true]);
    expect(find.byKey(const Key('second')), findsNothing);
  });

  testWidgets('follows the owner when it folds the child', (tester) async {
    await tester.pumpWidget(_host(collapsed: false, onCollapsed: (_) {}));
    expect(find.byKey(const Key('second')), findsOneWidget);

    await tester.pumpWidget(_host(collapsed: true, onCollapsed: (_) {}));
    expect(find.byKey(const Key('second')), findsNothing);

    await tester.pumpWidget(_host(collapsed: false, onCollapsed: (_) {}));
    expect(find.byKey(const Key('second')), findsOneWidget);
  });
}
