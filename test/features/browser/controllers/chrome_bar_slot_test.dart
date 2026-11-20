import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/controllers/chrome_bar_slot.dart';

/// A stand-in for a browser screen: like the real ones, it builds a brand-new
/// bar widget on every build and publishes it after the frame.
class _Screen extends StatefulWidget {
  const _Screen({required this.onBuild, required this.publish});

  final VoidCallback onBuild;
  final ValueChanged<Widget?> publish;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    // Deliberately not const: a const widget is one shared instance, but the
    // real screens build a new bar each time, and that is what loops.
    // ignore: prefer_const_constructors
    final bar = SizedBox(height: 10, child: Text('bar'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.publish(bar);
    });
    return const SizedBox.expand();
  }
}

void main() {
  group('ChromeBarSlot', () {
    testWidgets('hands out one widget for the life of the slot', (tester) async {
      final slot = ChromeBarSlot();
      final first = slot.publish(const Text('a'));
      final second = slot.publish(const Text('b'));
      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
      expect(identical(first, slot.barWidget), isTrue);
    });

    testWidgets('publishing no bar yields null, so the hub shows none', (
      tester,
    ) async {
      final slot = ChromeBarSlot();
      expect(slot.publish(const Text('a')), isNotNull);
      expect(slot.publish(null), isNull);
    });

    testWidgets('what the slot shows follows the latest content', (
      tester,
    ) async {
      final slot = ChromeBarSlot();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: slot.barWidget,
        ),
      );
      expect(find.text('one'), findsNothing);

      slot.publish(const Text('one'));
      await tester.pump();
      expect(find.text('one'), findsOneWidget);

      slot.publish(const Text('two'));
      await tester.pump();
      expect(find.text('one'), findsNothing);
      expect(find.text('two'), findsOneWidget);

      slot.publish(null);
      await tester.pump();
      expect(find.text('two'), findsNothing);
    });

    testWidgets(
      'a screen that publishes a new bar every build loops its shell; '
      'publishing through the slot does not',
      (tester) async {
        Future<int> screenBuilds({required bool useSlot}) async {
          // The shell, as in BrowserTabsHost: it rebuilds the screen whenever
          // the bar published to the hub changes.
          final hub = ValueNotifier<Widget?>(null);
          final slot = ChromeBarSlot();
          var builds = 0;
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: ValueListenableBuilder<Widget?>(
                valueListenable: hub,
                builder: (context, bottomBar, _) => Column(
                  children: [
                    Expanded(
                      child: _Screen(
                        onBuild: () => builds++,
                        publish: (bar) =>
                            hub.value = useSlot ? slot.publish(bar) : bar,
                      ),
                    ),
                    if (bottomBar != null) bottomBar,
                  ],
                ),
              ),
            ),
          );
          for (var i = 0; i < 20; i++) {
            await tester.pump();
          }
          return builds;
        }

        // Without the slot, every frame rebuilds the screen again.
        expect(await screenBuilds(useSlot: false), greaterThan(15));
        // With it, the screen builds a handful of times while things settle.
        expect(await screenBuilds(useSlot: true), lessThan(5));
      },
    );
  });
}
