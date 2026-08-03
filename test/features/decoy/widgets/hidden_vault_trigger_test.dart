import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

/// These deliberately never hold long enough to complete the real 3-second
/// trigger: doing so would push the real `LockGateScreen` (which, absent a
/// master password, immediately falls through to `VaultDashboard`), and
/// building either of those screens drags in unrelated platform-channel
/// dependencies that don't belong in a test of this widget. The gating
/// logic itself -- does it fire at exactly 3s, does canceling early
/// suppress it, does holding past 3s fire only once -- is covered
/// end-to-end at the timer level in test/core/utils/hold_trigger_test.dart.
/// What's left to check here is just that the gesture wiring on top of it
/// (GestureDetector callbacks, rendering the child) behaves as expected.
void main() {
  testWidgets('renders its child unchanged', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HiddenVaultTrigger(child: Text('PDF Viewer'))),
      ),
    );

    expect(find.text('PDF Viewer'), findsOneWidget);
  });

  testWidgets('a quick tap does not navigate anywhere', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HiddenVaultTrigger(child: Text('PDF Viewer'))),
      ),
    );

    await tester.tap(find.text('PDF Viewer'));
    await tester.pump(const Duration(milliseconds: 100));

    // Still exactly one route: nothing was pushed by a brief tap.
    expect(find.text('PDF Viewer'), findsOneWidget);
  });

  testWidgets('holding for less than the full duration does not navigate', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HiddenVaultTrigger(child: Text('PDF Viewer'))),
      ),
    );

    final gesture = await tester.startGesture(tester.getCenter(find.text('PDF Viewer')));
    await tester.pump(const Duration(seconds: 2, milliseconds: 900));

    expect(find.text('PDF Viewer'), findsOneWidget);

    await gesture.up();
    await tester.pump();
  });
}
