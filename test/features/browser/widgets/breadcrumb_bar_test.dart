import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';

List<PathSegment> _stack() => [
  PathSegment('Root', ''),
  PathSegment('Docs', 'Docs'),
  PathSegment('Taxes', 'Docs/Taxes'),
];

Widget _host(BreadcrumbBar bar) => MaterialApp(
  home: Scaffold(body: Column(children: [bar, const Text('below')])),
);

void main() {
  testWidgets('root crumb shows the storage name, not the home icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        BreadcrumbBar(
          stack: _stack(),
          onTap: (_) {},
          rootLabel: 'My Vault',
          rootIcon: Icons.lock_outline_rounded,
        ),
      ),
    );
    expect(find.text('My Vault'), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(find.byIcon(Icons.home_rounded), findsNothing);
  });

  testWidgets('without rootLabel the home icon stays', (tester) async {
    await tester.pumpWidget(_host(BreadcrumbBar(stack: _stack(), onTap: (_) {})));
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });

  testWidgets('tapping a crumb still navigates', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      _host(
        BreadcrumbBar(
          stack: _stack(),
          onTap: (i) => tapped = i,
          rootLabel: 'V',
          edit: BreadcrumbEditConfig(
            pathText: '/Docs/Taxes',
            onSubmit: (_) async => true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Docs'));
    await tester.pump();
    expect(tapped, 1);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tap on current folder opens editor; submit, reject, escape', (
    tester,
  ) async {
    final submitted = <String>[];
    var accept = false;
    final controller = BreadcrumbBarController();
    await tester.pumpWidget(
      _host(
        BreadcrumbBar(
          stack: _stack(),
          onTap: (_) {},
          rootLabel: 'V',
          controller: controller,
          edit: BreadcrumbEditConfig(
            pathText: '/Docs/Taxes',
            onSubmit: (t) async {
              submitted.add(t);
              return accept;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Taxes'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(controller.isEditing, isTrue);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '/Docs/Taxes');
    expect(field.controller!.selection.extentOffset, '/Docs/Taxes'.length);

    // Rejected: stays open.
    await tester.enterText(find.byType(TextField), '/nope');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(submitted, ['/nope']);
    expect(find.byType(TextField), findsOneWidget);

    // Accepted: closes.
    accept = true;
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(submitted, ['/nope', '/nope']);
    expect(find.byType(TextField), findsNothing);

    // Escape cancels without submitting.
    controller.startEditing();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(submitted.length, 2);
  });

  testWidgets('unchanged text closes without submitting', (tester) async {
    var calls = 0;
    final controller = BreadcrumbBarController();
    await tester.pumpWidget(
      _host(
        BreadcrumbBar(
          stack: _stack(),
          onTap: (_) {},
          controller: controller,
          edit: BreadcrumbEditConfig(
            pathText: '/Docs/Taxes',
            onSubmit: (_) async {
              calls++;
              return true;
            },
          ),
        ),
      ),
    );
    controller.startEditing();
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('without edit config the bar is not editable', (tester) async {
    final controller = BreadcrumbBarController();
    await tester.pumpWidget(
      _host(BreadcrumbBar(stack: _stack(), onTap: (_) {}, controller: controller)),
    );
    controller.startEditing();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });
}
