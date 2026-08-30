import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_format_selector.dart';

void main() {
  Widget wrap(Widget child) => ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

  testWidgets('renders a segment for each format', (tester) async {
    await tester.pumpWidget(wrap(
      ContainerFormatSelector(
        selected: CreateFormat.veracrypt,
        busy: false,
        onChanged: (_) {},
      ),
    ));

    expect(find.text('VeraCrypt'), findsOneWidget);
    expect(find.text('LUKS1'), findsOneWidget);
    expect(find.text('LUKS2'), findsOneWidget);
  });

  testWidgets('reflects the selected format', (tester) async {
    await tester.pumpWidget(wrap(
      ContainerFormatSelector(
        selected: CreateFormat.luks2,
        busy: false,
        onChanged: (_) {},
      ),
    ));

    final widget = tester.widget<SegmentedButton<CreateFormat>>(
      find.byType(SegmentedButton<CreateFormat>),
    );
    expect(widget.selected, {CreateFormat.luks2});
  });

  testWidgets('tapping a segment calls onChanged with that format', (tester) async {
    CreateFormat? tapped;
    await tester.pumpWidget(wrap(
      ContainerFormatSelector(
        selected: CreateFormat.veracrypt,
        busy: false,
        onChanged: (f) => tapped = f,
      ),
    ));

    await tester.tap(find.text('LUKS1'));
    await tester.pumpAndSettle();

    expect(tapped, CreateFormat.luks1);
  });

  testWidgets('does nothing when busy is true', (tester) async {
    CreateFormat? tapped;
    await tester.pumpWidget(wrap(
      ContainerFormatSelector(
        selected: CreateFormat.veracrypt,
        busy: true,
        onChanged: (f) => tapped = f,
      ),
    ));

    await tester.tap(find.text('LUKS1'));
    await tester.pumpAndSettle();

    expect(tapped, isNull);
  });
}