import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';


const _narrowWidth = 320.0; // narrowest common Android width
const _phoneWidth = 360.0; // typical small-phone width, for the 3-way nav split
Widget _harness({
  required Locale locale,
  required Widget child,
  double width = _narrowWidth,
  double textScale = 1.0,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates, // <-- Note the 's' and the spread operator (...)
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

/// Mirrors the icon+label ButtonSegment shape used throughout the app's
/// SegmentedButtons after the overflow fix: label wrapped with
/// maxLines:1 + ellipsis + softWrap:false.
Widget _segmentedButtonShape(String labelA, String labelB) {
  return SegmentedButton<int>(
    segments: [
      ButtonSegment(
        value: 0,
        icon: const Icon(Icons.casino_outlined),
        label: Text(labelA, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
      ),
      ButtonSegment(
        value: 1,
        icon: const Icon(Icons.tune_rounded),
        label: Text(labelB, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
      ),
    ],
    selected: const {0},
    onSelectionChanged: (_) {},
  );
}

/// Mirrors the "icon + Expanded(ellipsis label) + Flexible(ellipsis
/// trailing button)" row shape used by _PickerRow (container_splitter_sheet),
/// the manifest-load button (hash_verifier_sheet), and the change-target
/// button (container_repair_sheet).
Widget _labelWithTrailingActionShape(String captionLabel, String valueLabel, String buttonLabel) {
  return Row(
    children: [
      const Icon(Icons.description_outlined, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(captionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(valueLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: TextButton(
          onPressed: () {},
          child: Text(buttonLabel, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
        ),
      ),
    ],
  );
}

/// Mirrors _MainBottomBarItem (lib/app/main_shell.dart): a fixed-height
/// 68dp bar with three Expanded items, each an icon pill above a
/// single-line ellipsis label.
Widget _navBarShape(List<String> labels) {
  return SizedBox(
    key: const Key('nav_bar'),
    height: 68,
    child: Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: const Icon(Icons.circle, size: 22),
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

void main() {
  final locales = AppLocalizations.supportedLocales;

  group('InlineBanner with trailing action stays overflow-safe across locales', () {
    for (final locale in locales) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('locale=${locale.languageCode} textScale=$scale', (tester) async {
          await tester.pumpWidget(_harness(
            locale: locale,
            width: 280,
            textScale: scale,
            child: Builder(
              builder: (context) {
                final l10n = context.l10n;
                return InlineBanner(
                  l10n.folderVaultStorageAccessWarning,
                  tone: AppBannerTone.warning,
                  trailing: TextButton(
                    onPressed: () {},
                    child: Text(
                      l10n.enableButtonLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                );
              },
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('SegmentedButton segments stay overflow-safe across locales', () {
    for (final locale in locales) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('locale=${locale.languageCode} textScale=$scale', (tester) async {
          await tester.pumpWidget(_harness(
            locale: locale,
            textScale: scale,
            child: Builder(
              builder: (context) {
                final l10n = context.l10n;
                return _segmentedButtonShape(l10n.modeDiceware, l10n.modeCustomPassword);
              },
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Label + trailing action row stays overflow-safe across locales', () {
    for (final locale in locales) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('locale=${locale.languageCode} textScale=$scale', (tester) async {
          await tester.pumpWidget(_harness(
            locale: locale,
            textScale: scale,
            child: Builder(
              builder: (context) {
                final l10n = context.l10n;
                return _labelWithTrailingActionShape(
                  l10n.splitDestinationFolderLabel,
                  'some_very_long_selected_file_name_example.container',
                  l10n.repairChangeTargetButton,
                );
              },
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Bottom nav bar keeps identical height across every locale', () {
    for (final locale in locales) {
      testWidgets('locale=${locale.languageCode} renders without overflow', (tester) async {
        await tester.pumpWidget(_harness(
          locale: locale,
          width: _phoneWidth,
          child: Builder(
            builder: (context) {
              final l10n = context.l10n;
              return _navBarShape([
                l10n.navBarVaultsLabel,
                l10n.navBarToolsLabel,
                l10n.settingsTooltip,
              ]);
            },
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('height is identical across all locales (no cross-locale layout shift)', (tester) async {
      final heights = <String, double>{};
      for (final locale in locales) {
        await tester.pumpWidget(_harness(
          locale: locale,
          width: _phoneWidth,
          child: Builder(
            builder: (context) {
              final l10n = context.l10n;
              return _navBarShape([
                l10n.navBarVaultsLabel,
                l10n.navBarToolsLabel,
                l10n.settingsTooltip,
              ]);
            },
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        heights[locale.languageCode] = tester.getSize(find.byKey(const Key('nav_bar'))).height;
      }

      final distinctHeights = heights.values.toSet();
      expect(
        distinctHeights.length,
        1,
        reason: 'bottom nav bar height differs across locales: $heights',
      );
    });
  });
}