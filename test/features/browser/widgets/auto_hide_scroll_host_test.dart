import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/widgets/auto_hide_scroll_host.dart';

void main() {
  testWidgets('AutoHideScrollHost stays visible when enabled is false', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AutoHideScrollHost(
            enabled: false,
            bar: const SizedBox(height: 40, child: Text('Breadcrumb')),
            child: ListView.builder(
              itemCount: 100,
              itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Breadcrumb'), findsOneWidget);
    final alignBefore = tester.widget<Align>(
      find.ancestor(of: find.text('Breadcrumb'), matching: find.byType(Align)),
    );
    expect(alignBefore.heightFactor, 1.0);

    // Scroll down
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    final alignAfter = tester.widget<Align>(
      find.ancestor(of: find.text('Breadcrumb'), matching: find.byType(Align)),
    );
    expect(alignAfter.heightFactor, 1.0);
  });

  testWidgets('AutoHideScrollHost hides bar on scroll down when enabled is true', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AutoHideScrollHost(
            enabled: true,
            barHeight: 40,
            bar: const SizedBox(height: 40, child: Text('Breadcrumb')),
            child: ListView.builder(
              itemCount: 100,
              itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Breadcrumb'), findsOneWidget);

    // Scroll down by 200px
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    final alignAfter = tester.widget<Align>(
      find.ancestor(of: find.text('Breadcrumb'), matching: find.byType(Align)),
    );
    expect(alignAfter.heightFactor, 0.0);

    // Scroll back up
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();

    final alignRevealed = tester.widget<Align>(
      find.ancestor(of: find.text('Breadcrumb'), matching: find.byType(Align)),
    );
    expect(alignRevealed.heightFactor, 1.0);
  });

  testWidgets('AutoHideScrollHost resets visibility when resetKey changes', (tester) async {
    var currentPath = '/root';

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: AutoHideScrollHost(
                enabled: true,
                resetKey: currentPath,
                barHeight: 40,
                bar: const SizedBox(height: 40, child: Text('Breadcrumb')),
                child: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => setState(() => currentPath = '/root/subfolder'),
                      child: const Text('Navigate'),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: 100,
                        itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    // Scroll down to hide
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    var align = tester.widget<Align>(
      find.ancestor(of: find.text('Breadcrumb'), matching: find.byType(Align)),
    );
    expect(align.heightFactor, 0.0);

    // Navigate to new folder (resetKey changes)
    await tester.tap(find.text('Navigate'));
    await tester.pump();

    align = tester.widget<Align>(
      find.ancestor(of: find.text('Breadcrumb'), matching: find.byType(Align)),
    );
    expect(align.heightFactor, 1.0);
  });
}
