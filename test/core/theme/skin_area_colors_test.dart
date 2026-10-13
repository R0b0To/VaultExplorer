import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_skin_tokens.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_colors.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';

void main() {
  final base = ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  );

  Map<SkinArea, SkinAreaColors> resolve([
    Color? Function(SkinArea, SkinToken)? overrideFor,
  ]) => resolveSkinAreaColors(
    scheme: base,
    appBar: base.surfaceContainerHigh,
    onAppBar: base.onSurface,
    fab: base.primaryContainer,
    onFab: base.onPrimaryContainer,
    overrideFor: overrideFor,
  );

  group('resolveSkinAreaColors', () {
    test('with no overrides every page is exactly the shared palette', () {
      final areas = resolve();
      for (final area in SkinArea.values) {
        final colors = areas[area]!;
        expect(colors.custom, isEmpty, reason: area.id);
        expect(
          applySkinAreaToScheme(base, colors),
          base,
          reason: '${area.id} must not change an uncustomized skin',
        );
      }
    });

    test('an override on one page never reaches another page', () {
      const red = Color(0xFFAA0000);
      final areas = resolve(
        (area, token) =>
            area == SkinArea.tools && token == SkinToken.card ? red : null,
      );
      expect(areas[SkinArea.tools]!.color(SkinToken.card), red);
      expect(areas[SkinArea.tools]!.isCustom(SkinToken.card), isTrue);
      for (final area in SkinArea.values.where((a) => a != SkinArea.tools)) {
        expect(
          areas[area]!.color(SkinToken.card),
          base.surfaceContainerHigh,
          reason: area.id,
        );
        expect(areas[area]!.isCustom(SkinToken.card), isFalse, reason: area.id);
      }
    });

    test('overrides for tokens a page does not expose are ignored', () {
      final areas = resolve((area, token) => const Color(0xFF00AA00));
      // Tools has no round add button; the dashboard has no outline color.
      expect(areas[SkinArea.tools]!.isCustom(SkinToken.fab), isFalse);
      expect(areas[SkinArea.dashboard]!.isCustom(SkinToken.outline), isFalse);
      expect(areas[SkinArea.dashboard]!.isCustom(SkinToken.fab), isTrue);
    });

    test('moving a page background re-derives its surface steps', () {
      const background = Color(0xFF101820);
      final areas = resolve(
        (area, token) =>
            area == SkinArea.files && token == SkinToken.background
            ? background
            : null,
      );
      final files = areas[SkinArea.files]!;
      final card = files.color(SkinToken.card);
      expect(files.surfaceLow, Color.lerp(background, card, 0.35));
      expect(files.surfaceMid, Color.lerp(background, card, 0.6));
      // The other pages keep the palette's own steps.
      expect(areas[SkinArea.tools]!.surfaceLow, base.surfaceContainerLow);
    });

    test('the side menu maps selection onto the secondary container', () {
      const pill = Color(0xFF445566);
      final areas = resolve(
        (area, token) =>
            area == SkinArea.drawer && token == SkinToken.selection
            ? pill
            : null,
      );
      final scheme = applySkinAreaToScheme(base, areas[SkinArea.drawer]!);
      expect(scheme.secondaryContainer, pill);
      expect(scheme.primaryContainer, base.primaryContainer);
    });

    test('other pages map selection onto the primary container', () {
      const pill = Color(0xFF445566);
      final areas = resolve(
        (area, token) =>
            area == SkinArea.settings && token == SkinToken.selection
            ? pill
            : null,
      );
      final scheme = applySkinAreaToScheme(base, areas[SkinArea.settings]!);
      expect(scheme.primaryContainer, pill);
      expect(scheme.secondaryContainer, base.secondaryContainer);
    });

    test('the active card is the card tinted toward the selection color', () {
      final areas = resolve();
      final dashboard = areas[SkinArea.dashboard]!;
      expect(
        dashboard.color(SkinToken.cardActive),
        Color.alphaBlend(
          base.primaryContainer.withValues(alpha: 0.35),
          base.surfaceContainerHigh,
        ),
      );
      const own = Color(0xFF334455);
      final custom = resolve(
        (area, token) =>
            area == SkinArea.dashboard && token == SkinToken.cardActive
            ? own
            : null,
      );
      expect(custom[SkinArea.dashboard]!.color(SkinToken.cardActive), own);
    });
  });

  group('CustomAppSkin page colors', () {
    test('survive a JSON round trip and clear back to inheriting', () {
      final skin = const CustomAppSkin()
          .withAreaColor(
            SkinArea.tools,
            SkinToken.card,
            const Color(0xFF112233),
            dark: true,
          )
          .withAreaColor(
            SkinArea.files,
            SkinToken.accent,
            const Color(0xFF445566),
            dark: false,
          );
      final restored = CustomAppSkin.fromJson(
        jsonDecode(jsonEncode(skin.toJson())),
      );
      expect(
        restored.areaColorOrNull(SkinArea.tools, SkinToken.card, dark: true),
        const Color(0xFF112233),
      );
      expect(
        restored.areaColorOrNull(SkinArea.tools, SkinToken.card, dark: false),
        isNull,
      );
      expect(
        restored.areaColorOrNull(SkinArea.files, SkinToken.accent, dark: false),
        const Color(0xFF445566),
      );

      final cleared = restored.withAreaColor(
        SkinArea.tools,
        SkinToken.card,
        null,
        dark: true,
      );
      expect(cleared.darkAreaColors.containsKey(SkinArea.tools.id), isFalse);
    });

    test('withoutAreaColors resets one page only', () {
      final skin = const CustomAppSkin()
          .withAreaColor(
            SkinArea.tools,
            SkinToken.card,
            const Color(0xFF112233),
            dark: true,
          )
          .withAreaColor(
            SkinArea.files,
            SkinToken.card,
            const Color(0xFF445566),
            dark: true,
          );
      final reset = skin.withoutAreaColors(SkinArea.tools, dark: true);
      expect(
        reset.areaColorOrNull(SkinArea.tools, SkinToken.card, dark: true),
        isNull,
      );
      expect(
        reset.areaColorOrNull(SkinArea.files, SkinToken.card, dark: true),
        const Color(0xFF445566),
      );
    });

    test('old vault-card colors move onto the Dashboard page', () {
      final restored = CustomAppSkin.fromJson({
        'lightComponentColors': {
          'vaultCardBackground': 0xFF111111,
          'mountedVaultCardBackground': 0xFF222222,
          'appBarBackground': 0xFF333333,
        },
      });
      expect(
        restored.areaColorOrNull(
          SkinArea.dashboard,
          SkinToken.card,
          dark: false,
        ),
        const Color(0xFF111111),
      );
      expect(
        restored.areaColorOrNull(
          SkinArea.dashboard,
          SkinToken.cardActive,
          dark: false,
        ),
        const Color(0xFF222222),
      );
      // The shared top-bar color stays shared.
      expect(restored.lightComponentColors.keys, ['appBarBackground']);
    });

    test('unknown pages and tokens in a file are dropped', () {
      final restored = CustomAppSkin.fromJson({
        'lightAreaColors': {
          'tools': {'card': 0xFF111111, 'notAToken': 0xFF222222},
          'notAPage': {'card': 0xFF333333},
        },
      });
      expect(restored.lightAreaColors.keys, ['tools']);
      expect(restored.lightAreaColors['tools']!.keys, ['card']);
    });
  });

  group('SkinAreaScope', () {
    const red = Color(0xFFCC0000);
    final skin = const CustomAppSkin().withAreaColor(
      SkinArea.files,
      SkinToken.background,
      red,
      dark: true,
    );
    final theme = buildDarkTheme(
      appSkin: AppSkinPreset.custom,
      customAppSkin: skin,
    );

    Future<Map<String, Color>> surfaces(
      WidgetTester tester,
      Widget Function(Widget Function(String) probe) build,
    ) async {
      final seen = <String, Color>{};
      Widget probe(String name) => Builder(
        builder: (context) {
          seen[name] = Theme.of(context).colorScheme.surface;
          return const SizedBox.shrink();
        },
      );
      await tester.pumpWidget(MaterialApp(theme: theme, home: build(probe)));
      return seen;
    }

    testWidgets('gives each page only its own colors', (tester) async {
      final seen = await surfaces(
        tester,
        (probe) => Column(
          children: [
            SkinAreaScope(area: SkinArea.files, child: probe('files')),
            SkinAreaScope(area: SkinArea.tools, child: probe('tools')),
            probe('shared'),
          ],
        ),
      );
      expect(seen['files'], red);
      expect(seen['tools'], theme.colorScheme.surface);
      expect(seen['shared'], theme.colorScheme.surface);
    });

    testWidgets('a nested page starts from the shared theme again', (
      tester,
    ) async {
      final seen = await surfaces(
        tester,
        (probe) => SkinAreaScope(
          area: SkinArea.files,
          child: SkinAreaScope(area: SkinArea.tools, child: probe('nested')),
        ),
      );
      expect(seen['nested'], theme.colorScheme.surface);
    });

    testWidgets('reports which page it is inside', (tester) async {
      SkinAreaColors? inside;
      SkinAreaColors? outside;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Column(
            children: [
              SkinAreaScope(
                area: SkinArea.files,
                child: Builder(
                  builder: (context) {
                    inside = SkinAreaScope.maybeColorsOf(context);
                    return const SizedBox.shrink();
                  },
                ),
              ),
              Builder(
                builder: (context) {
                  outside = SkinAreaScope.maybeColorsOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      );
      expect(inside?.area, SkinArea.files);
      expect(outside, isNull);
    });

    testWidgets('leaves a plain theme untouched', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          home: const SkinAreaScope(
            area: SkinArea.tools,
            child: SizedBox(key: Key('child')),
          ),
        ),
      );
      expect(find.byKey(const Key('child')), findsOneWidget);
    });

    test('the theme carries every page', () {
      final tokens = theme.extension<AppSkinTokens>()!;
      for (final area in SkinArea.values) {
        expect(tokens.areaColors(area).area, area);
      }
      expect(tokens.areaColors(SkinArea.files).color(SkinToken.background), red);
    });
  });
}
