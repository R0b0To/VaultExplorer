import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/widgets/desktop_semantics_gate.dart';

void main() {
  Widget host({required bool exclude}) => Directionality(
    textDirection: TextDirection.ltr,
    child: DesktopSemanticsGate(
      exclude: exclude,
      child: Semantics(label: 'tile', child: const SizedBox(width: 10)),
    ),
  );

  testWidgets('excluding leaves no semantics for the content', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(exclude: true));
    expect(find.bySemanticsLabel('tile'), findsNothing);
    handle.dispose();
  });

  testWidgets('not excluding keeps the content in the semantics tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(exclude: false));
    expect(find.bySemanticsLabel('tile'), findsOneWidget);
    handle.dispose();
  });
}
