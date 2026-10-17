import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_index.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_matcher.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_models.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_target.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_text.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

ResolvedSettingsEntry _entry(
  String id,
  String title, {
  List<String> keywords = const [],
  List<String> details = const [],
  List<String> breadcrumb = const ['Security & Privacy'],
}) {
  return ResolvedSettingsEntry.create(
    entry: SettingsSearchEntry(
      id: id,
      destination: SettingsDestination.security,
      title: (_) => title,
    ),
    title: title,
    breadcrumb: breadcrumb,
    keywords: keywords,
    details: details,
  );
}

List<String> _ids(List<ResolvedSettingsEntry> results) =>
    [for (final r in results) r.id];

void main() {
  group('normalizeSearchText', () {
    test('lower-cases, folds diacritics and drops punctuation', () {
      expect(normalizeSearchText('  Café  Über-Größe! '), 'cafe uber grosse');
    });

    test('keeps non-Latin scripts intact', () {
      expect(normalizeSearchText('设置 搜索'), '设置 搜索');
      expect(normalizeSearchText('Налаштування'), 'налаштування');
    });
  });

  group('searchSettingsIndex', () {
    final index = [
      _entry('block', 'Block screenshots',
          keywords: ['screen capture', 'recent apps'],
          details: ['Hide vault contents from screenshots and screen recording']),
      _entry('timeout', 'Auto-lock timeout',
          keywords: ['idle'], breadcrumb: ['Security & Privacy', 'App lock']),
      _entry('lock_containers', 'Auto-lock containers',
          details: ['Lock open vaults when the screen locks']),
      _entry('theme', 'App theme',
          keywords: ['dark mode'], breadcrumb: ['Appearance']),
    ];

    test('a blank query matches nothing', () {
      expect(searchSettingsIndex('', index), isEmpty);
      expect(searchSettingsIndex('   ', index), isEmpty);
    });

    test('finds by title prefix, case- and punctuation-insensitively', () {
      expect(_ids(searchSettingsIndex('AUTO lock', index)).first, anyOf('timeout', 'lock_containers'));
      expect(_ids(searchSettingsIndex('screenshot', index)), contains('block'));
    });

    test('every word must match', () {
      expect(_ids(searchSettingsIndex('auto timeout', index)), ['timeout']);
      expect(searchSettingsIndex('auto banana', index), isEmpty);
    });

    test('finds by keyword, breadcrumb and detail text', () {
      expect(_ids(searchSettingsIndex('dark mode', index)), ['theme']);
      expect(_ids(searchSettingsIndex('appearance', index)), ['theme']);
      expect(_ids(searchSettingsIndex('open vaults', index)), ['lock_containers']);
    });

    test('title matches outrank detail matches', () {
      final results = searchSettingsIndex('screen', index);
      // "Block screenshots" has it in the title; the other hits are keywords or details.
      expect(_ids(results).first, 'block');
    });

    test('tolerates a typo in longer words', () {
      expect(_ids(searchSettingsIndex('screnshots', index)), contains('block'));
      expect(searchSettingsIndex('xyzzy', index), isEmpty);
    });

    test('exact title ranks first', () {
      final results = searchSettingsIndex('app theme', index);
      expect(_ids(results).first, 'theme');
    });

    test('respects the limit', () {
      expect(searchSettingsIndex('a', index, limit: 2).length, lessThanOrEqualTo(2));
    });
  });

  group('settings search registry', () {
    final l10n = AppLocalizationsEn();
    final resolved = resolveSettingsSearchIndex(l10n, androidSdkInt: 36);

    test('entry ids are unique', () {
      final ids = [for (final e in kSettingsSearchEntries) e.id];
      expect(ids.toSet().length, ids.length);
    });

    test('every entry resolves to non-empty text and a breadcrumb', () {
      for (final r in resolved) {
        expect(r.title.trim(), isNotEmpty, reason: r.id);
        expect(r.breadcrumb, isNotEmpty, reason: r.id);
        if (r.section != null) expect(r.section!.trim(), isNotEmpty, reason: r.id);
      }
    });

    test('every entry is found by searching its own title', () {
      for (final r in resolved) {
        final hits = searchSettingsIndex(r.title, resolved, limit: 200);
        expect(_ids(hits), contains(r.id), reason: '"${r.title}" (${r.id})');
      }
    });

    test('entries gated by Android version are hidden below it', () {
      final old = resolveSettingsSearchIndex(l10n, androidSdkInt: 30);
      expect(_ids(old), isNot(contains('appearance.material_you')));
      expect(_ids(resolved), contains('appearance.material_you'));
    });

    test('screen-only entries do not scroll to a row', () {
      final emergency = resolved.firstWhere((r) => r.id == 'emergency.screen');
      expect(emergency.scrollTo, isFalse);
      expect(emergency.destination, SettingsDestination.emergency);
    });
  });

  group('SettingsSearchTargetScope', () {
    Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

    Widget longList({String sectionOneTitle = 'Section A'}) => ListView(
          children: [
            Text(sectionOneTitle),
            const ListTile(title: Text('Timeout'), subtitle: Text('in A')),
            for (var i = 0; i < 60; i++) ListTile(title: Text('Filler $i')),
            const Text('Section B'),
            const ListTile(title: Text('Timeout'), subtitle: Text('in B')),
            for (var i = 60; i < 80; i++) ListTile(title: Text('Filler $i')),
          ],
        );

    testWidgets('shows the child untouched when there is no target',
        (tester) async {
      await tester.pumpWidget(
        app(SettingsSearchTargetScope(target: null, child: longList())),
      );
      expect(find.text('Section A'), findsOneWidget);
      expect(find.text('in A'), findsOneWidget);
    });

    testWidgets('scrolls a lazily built row into view', (tester) async {
      await tester.pumpWidget(
        app(
          SettingsSearchTargetScope(
            target: const SettingsSearchTarget(text: 'Filler 70'),
            child: longList(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Filler 70'), findsOneWidget);
      final rect = tester.getRect(find.text('Filler 70'));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(screen.height));
    });

    testWidgets('uses the section header to pick between duplicate titles',
        (tester) async {
      await tester.pumpWidget(
        app(
          SettingsSearchTargetScope(
            target: const SettingsSearchTarget(
              text: 'Timeout',
              section: 'Section B',
            ),
            child: longList(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('in B'), findsOneWidget);
      final rect = tester.getRect(find.text('in B'));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(screen.height));
    });

    testWidgets('falls back and explains when the row is not shown',
        (tester) async {
      await tester.pumpWidget(
        app(
          SettingsSearchTargetScope(
            target: const SettingsSearchTarget(
              text: 'Does not exist',
              fallback: 'Filler 40',
              unavailableMessage: 'Turn something on first',
            ),
            child: longList(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Filler 40'), findsOneWidget);
      expect(find.text('Turn something on first'), findsOneWidget);
    });
  });
}
