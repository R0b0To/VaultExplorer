import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/models/viewer_adjustments.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/color_adjust_filter.dart';

void main() {
  const child = SizedBox(key: Key('picture'), width: 10, height: 10);

  testWidgets('identity returns the child with no filter layer', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ColorAdjustFilter(
          adjustments: ViewerAdjustments.identity,
          child: child,
        ),
      ),
    );
    expect(find.byKey(const Key('picture')), findsOneWidget);
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('non-identity wraps the child in a filter', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ColorAdjustFilter(
          adjustments: ViewerAdjustments(brightness: 0.2),
          child: child,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('picture')), findsOneWidget);
    // Impeller shader path or the matrix fallback, depending on the test
    // renderer; either way exactly one of them is present.
    final filtered = find.byType(ColorFiltered).evaluate().length +
        find.byType(ImageFiltered).evaluate().length;
    expect(filtered, 1);
  });

  testWidgets('going back to identity removes the filter', (tester) async {
    Widget build(ViewerAdjustments a) => Directionality(
          textDirection: TextDirection.ltr,
          child: ColorAdjustFilter(adjustments: a, child: child),
        );
    await tester.pumpWidget(build(const ViewerAdjustments(contrast: 1.5)));
    await tester.pump();
    await tester.pumpWidget(build(ViewerAdjustments.identity));
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
  });
}
