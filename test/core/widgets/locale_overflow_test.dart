import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';

/// Regression coverage for text-length differences across VaultExplorer's
/// five supported locales (en/de/es/it/uk).
///
/// Translations of the same string can be 2-4x longer than the English
/// source (see e.g. `modeDiceware`/`modeCustomPassword`, or DE
/// "Zusammenführen" for `splitJoinModeJoin`). This file pumps the app's
/// tightest fixed-size UI shapes under every locale, at a narrow phone
/// width, and asserts that:
///   1. no overflow/layout exception is thrown ([tester.takeException]
///      returns null), and
///   2. where the shape is meant to have a fixed height (the bottom nav
///      bar), that height is IDENTICAL across every locale — i.e. no
///      language causes a layout shift the others don't.
///
/// [InlineBanner] is tested directly since it's a shared, importable
/// widget (see lib/core/widgets/feedback/inline_banner.dart).
///
/// The other shapes under test (SegmentedButton segments, and the
/// "Expanded label + trailing action button" row used by the splitter,
/// hash verifier, and repair screens) live as private classes inside
/// their own screen files and can't be imported here, so this file
/// rebuilds their exact shape locally, using the real longest strings
/// pulled live from [AppLocalizations]. If a future change removes the
/// maxLines/overflow/Flexible guards from one of those production
/// shapes, keep the mirrored copy here in sync so this test keeps
/// catching the regression.

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
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
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
                // modeDiceware / modeCustomPassword are the app's longest
                // SegmentedButton segment labels (up to ~29 chars in es).
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