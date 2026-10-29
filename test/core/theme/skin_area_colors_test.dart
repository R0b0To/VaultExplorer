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

    test('every token resolves to a color on every page', () {
      for (final colors in resolve().values) {
        expect(colors.colors.keys.toSet(), SkinToken.values.toSet());
      }
    });

    test('token ids are unique and live under their own group', () {
      final ids = SkinToken.values.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final token in SkinToken.values) {
        expect(token.id.startsWith('${token.group.id}.'), isTrue, reason: token.id);
      }
    });

    test('an override on one page never reaches another page', () {
      const red = Color(0xFFAA0000);
      final areas = resolve(
        (area, token) =>
            area == SkinArea.tools && token == SkinToken.surfaceCard
            ? red
            : null,
      );
      expect(areas[SkinArea.tools]!.color(SkinToken.surfaceCard), red);
      expect(areas[SkinArea.tools]!.isCustom(SkinToken.surfaceCard), isTrue);
      for (final area in SkinArea.values.where((a) => a != SkinArea.tools)) {
        expect(
          areas[area]!.color(SkinToken.surfaceCard),
          base.surfaceContainerHigh,
          reason: area.id,
        );
        expect(
          areas[area]!.isCustom(SkinToken.surfaceCard),
          isFalse,
          reason: area.id,
        );
      }
    });

    test('overrides for tokens a page does not expose are ignored', () {
      final areas = resolve((area, token) => const Color(0xFF00AA00));
      // Tools has no round add button; the side menu has no input fields.
      expect(areas[SkinArea.tools]!.isCustom(SkinToken.floatingFab), isFalse);
      expect(areas[SkinArea.drawer]!.isCustom(SkinToken.surfaceField), isFalse);
      expect(areas[SkinArea.dashboard]!.isCustom(SkinToken.floatingFab), isTrue);
    });

    // The point of the split: tokens that start out the same color are still
    // independent. Moving one must not move any other.
    test('moving one token leaves every other token unchanged', () {
      const probe = Color(0xFF123456);
      final untouched = resolve()[SkinArea.dashboard]!;
      for (final moved in SkinArea.dashboard.tokens) {
        // The active card is the one documented derived default.
        final areas = resolve(
          (area, token) =>
              area == SkinArea.dashboard && token == moved ? probe : null,
        );
        final colors = areas[SkinArea.dashboard]!;
        expect(colors.color(moved), probe, reason: moved.id);
        for (final other in SkinToken.values) {
          if (other == moved) continue;
          if (other == SkinToken.surfaceCardActive &&
              (moved == SkinToken.surfaceCard ||
                  moved == SkinToken.selectionFill)) {
            continue;
          }
          expect(
            colors.color(other),
            untouched.color(other),
            reason: 'editing ${moved.id} must not change ${other.id}',
          );
        }
      }
    });

    test('the card color no longer drives fields, buttons, chips or dialogs', () {
      const red = Color(0xFFAA0000);
      final theme = buildSkinAreaTheme(
        ThemeData(colorScheme: base),
        resolve(
          (area, token) =>
              area == SkinArea.files && token == SkinToken.surfaceCard
              ? red
              : null,
        )[SkinArea.files]!,
      );
      expect(theme.dialogTheme.backgroundColor, base.surfaceContainerHigh);
      expect(theme.chipTheme.backgroundColor, base.surfaceContainerHigh);
      expect(theme.inputDecorationTheme.fillColor, base.surfaceContainerHigh);
    });

    test('menus, dialogs and sheets are three separate tokens', () {
      const own = Color(0xFF334455);
      final colors = resolve(
        (area, token) =>
            area == SkinArea.files && token == SkinToken.overlayDialog
            ? own
            : null,
      )[SkinArea.files]!;
      expect(colors.color(SkinToken.overlayDialog), own);
      expect(colors.color(SkinToken.overlayMenu), base.surfaceContainer);
      expect(colors.color(SkinToken.overlaySheet), base.surfaceContainerLow);
    });

    test('the side menu maps selection onto the secondary container', () {
      const pill = Color(0xFF445566);
      final areas = resolve(
        (area, token) =>
            area == SkinArea.drawer && token == SkinToken.selectionFill
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
            area == SkinArea.settings && token == SkinToken.selectionFill
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
        dashboard.color(SkinToken.surfaceCardActive),
        Color.alphaBlend(
          base.primaryContainer.withValues(alpha: 0.35),
          base.surfaceContainerHigh,
        ),
      );
      const own = Color(0xFF334455);
      final custom = resolve(
        (area, token) =>
            area == SkinArea.dashboard && token == SkinToken.surfaceCardActive
            ? own
            : null,
      );
      expect(
        custom[SkinArea.dashboard]!.color(SkinToken.surfaceCardActive),
        own,
      );
    });
  });

  group('legacy skins', () {
    test('an old key fans out to every token it used to drive', () {
      final restored = CustomAppSkin.fromJson({
        'lightAreaColors': {
          'tools': {'card': 0xFF111111, 'accent': 0xFF222222},
        },
      });
      Color? c(SkinToken t) =>
          restored.areaColorOrNull(SkinArea.tools, t, dark: false);
      for (final t in [
        SkinToken.surfaceCard,
        SkinToken.surfaceField,
        SkinToken.actionTonal,
        SkinToken.choiceBackground,
        SkinToken.overlayDialog,
      ]) {
        expect(c(t), const Color(0xFF111111), reason: t.id);
      }
      for (final t in [
        SkinToken.actionPrimary,
        SkinToken.actionText,
        SkinToken.controlActive,
        SkinToken.borderFocus,
      ]) {
        expect(c(t), const Color(0xFF222222), reason: t.id);
      }
    });

    test('the old overlay key wins over the old card key for dialogs', () {
      final restored = CustomAppSkin.fromJson({
        'lightAreaColors': {
          'tools': {'card': 0xFF111111, 'overlay': 0xFF333333},
        },
      });
      expect(
        restored.areaColorOrNull(SkinArea.tools, SkinToken.overlayDialog, dark: false),
        const Color(0xFF333333),
      );
      expect(
        restored.areaColorOrNull(SkinArea.tools, SkinToken.overlayMenu, dark: false),
        const Color(0xFF333333),
      );
      expect(
        restored.areaColorOrNull(SkinArea.tools, SkinToken.surfaceCard, dark: false),
        const Color(0xFF111111),
      );
    });

    test('a key in the current vocabulary beats the old key', () {
      final restored = CustomAppSkin.fromJson({
        'lightAreaColors': {
          'tools': {'card': 0xFF111111, 'surface.field': 0xFF999999},
        },
      });
      expect(
        restored.areaColorOrNull(SkinArea.tools, SkinToken.surfaceField, dark: false),
        const Color(0xFF999999),
      );
      expect(
        restored.areaColorOrNull(SkinArea.tools, SkinToken.surfaceCard, dark: false),
        const Color(0xFF111111),
      );
    });

    test('every old key maps to at least one current token', () {
      for (final key in SkinToken.legacyIdsInApplyOrder) {
        expect(SkinToken.fromLegacyId(key), isNotEmpty, reason: key);
      }
    });
  });

  group('CustomAppSkin page colors', () {
    test('survive a JSON round trip and clear back to inheriting', () {
      final skin = const CustomAppSkin()
          .withAreaColor(
            SkinArea.tools,
            SkinToken.surfaceCard,
            const Color(0xFF112233),
            dark: true,
          )
          .withAreaColor(
            SkinArea.files,
            SkinToken.actionPrimary,
            const Color(0xFF445566),
            dark: false,
          );
      final restored = CustomAppSkin.fromJson(
        jsonDecode(jsonEncode(skin.toJson())),
      );
      expect(
        restored.areaColorOrNull(SkinArea.tools, SkinToken.surfaceCard, dark: true),
        const Color(0xFF112233),
      );
      expect(
        restored.areaColorOrNull(SkinArea.tools, SkinToken.surfaceCard, dark: false),
        isNull,
      );
      expect(
        restored.areaColorOrNull(SkinArea.files, SkinToken.actionPrimary, dark: false),
        const Color(0xFF445566),
      );

      final cleared = restored.withAreaColor(
        SkinArea.tools,
        SkinToken.surfaceCard,
        null,
        dark: true,
      );
      expect(cleared.darkAreaColors.containsKey(SkinArea.tools.id), isFalse);
    });

    test('withoutAreaColors resets one page only', () {
      final skin = const CustomAppSkin()
          .withAreaColor(
            SkinArea.tools,
            SkinToken.surfaceCard,
            const Color(0xFF112233),
            dark: true,
          )
          .withAreaColor(
            SkinArea.files,
            SkinToken.surfaceCard,
            const Color(0xFF445566),
            dark: true,
          );
      final reset = skin.withoutAreaColors(SkinArea.tools, dark: true);
      expect(
        reset.areaColorOrNull(SkinArea.tools, SkinToken.surfaceCard, dark: true),
        isNull,
      );
      expect(
        reset.areaColorOrNull(SkinArea.files, SkinToken.surfaceCard, dark: true),
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
          SkinToken.surfaceCard,
          dark: false,
        ),
        const Color(0xFF111111),
      );
      expect(
        restored.areaColorOrNull(
          SkinArea.dashboard,
          SkinToken.surfaceCardActive,
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
      expect(restored.lightAreaColors['tools']!.keys, contains('surface.card'));
      expect(restored.lightAreaColors['tools']!.keys, isNot(contains('notAToken')));
    });
  });

  group('SkinAreaScope', () {
    const red = Color(0xFFCC0000);
    final skin = const CustomAppSkin().withAreaColor(
      SkinArea.files,
      SkinToken.surfacePage,
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
      expect(tokens.areaColors(SkinArea.files).color(SkinToken.surfacePage), red);
    });
  });
}
