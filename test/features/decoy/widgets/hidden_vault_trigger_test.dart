import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

void main() {
  testWidgets('renders its child unchanged', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: HiddenVaultTrigger(child: Text('PDF Viewer'))),
        ),
      ),
    );

    expect(find.text('PDF Viewer'), findsOneWidget);
  });

  testWidgets('a quick tap does not navigate anywhere', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: HiddenVaultTrigger(child: Text('PDF Viewer'))),
        ),
      ),
    );

    await tester.tap(find.text('PDF Viewer'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('PDF Viewer'), findsOneWidget);
  });

  testWidgets('holding for less than the full duration does not navigate', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: HiddenVaultTrigger(child: Text('PDF Viewer'))),
        ),
      ),
    );

    final gesture = await tester.startGesture(tester.getCenter(find.text('PDF Viewer')));
    await tester.pump(const Duration(seconds: 2, milliseconds: 900));

    expect(find.text('PDF Viewer'), findsOneWidget);

    await gesture.up();
    await tester.pump();
  });
}