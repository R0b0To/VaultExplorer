import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/controllers/library_controller.dart';
import 'package:vaultexplorer/features/library/index/library_scanner.dart';
import 'package:vaultexplorer/features/library/widgets/music_scope_sheet.dart';

MountedContainer _testContainer() => MountedContainer(
      uri: 'vault://test',
      displayName: 'Test Vault',
      volId: 1,
      rootFiles: const [],
      mountedAt: DateTime(2026),
      totalSpace: 1000000,
      freeSpace: 500000,
    );

LibraryFileAccess _fakeAccess(Map<String, List<String>> tree) {
  return LibraryFileAccess(
    list: (dirPath) async {
      final names = tree[dirPath];
      if (names == null) return null;
      return [
        for (final name in names)
          LibraryFsEntry(
            name: name,
            isDir: !name.contains('.'),
            sizeBytes: 100,
            modifiedSecs: 1000,
          ),
      ];
    },
    read: (_, _, _) async => null,
  );
}

Widget _buildTestApp({
  required LibraryFileAccess access,
  required List<String> initialFolders,
  required bool turningOn,
  required bool preferChoosing,
  bool initialDontAskAgain = false,
  required ValueChanged<ScopeSheetResult?> onResult,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final res = await showMusicScopeSheet(
              context,
              container: _testContainer(),
              access: access,
              initialFolders: initialFolders,
              turningOn: turningOn,
              preferChoosing: preferChoosing,
              initialDontAskAgain: initialDontAskAgain,
            );
            onResult(res);
          },
          child: const Text('Open Sheet'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('selecting Everything in this location confirms empty roots',
      (tester) async {
    ScopeSheetResult? result;
    final access = _fakeAccess({'': ['Music', 'Podcasts']});

    await tester.pumpWidget(
      _buildTestApp(
        access: access,
        initialFolders: const ['Music'],
        turningOn: true,
        preferChoosing: false,
        onResult: (res) => result = res,
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Music mode'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text('Everything in this location'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.folders, isEmpty);
    expect(result!.dontAskAgain, isFalse);
  });

  testWidgets('hold to select multiple folders in music folder picker works',
      (tester) async {
    ScopeSheetResult? result;
    final access = _fakeAccess({
      '': ['Albums', 'Audiobooks', 'Singles'],
    });

    await tester.pumpWidget(
      _buildTestApp(
        access: access,
        initialFolders: const [],
        turningOn: true,
        preferChoosing: true,
        onResult: (res) => result = res,
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a folder'));
    await tester.pumpAndSettle();

    // Long press on Albums
    await tester.longPress(find.text('Albums'));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);

    // Tap Audiobooks
    await tester.tap(find.text('Audiobooks'));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.text('Add (2)'), findsOneWidget);

    await tester.tap(find.text('Add (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Audiobooks'), findsOneWidget);

    await tester.tap(find.text("Don't ask again"));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.folders, containsAll(['Albums', 'Audiobooks']));
    expect(result!.dontAskAgain, isTrue);
  });

  testWidgets('tapping folder icon selects folder without shifting text',
      (tester) async {
    final access = _fakeAccess({
      '': ['Albums', 'Podcasts'],
    });

    await tester.pumpWidget(
      _buildTestApp(
        access: access,
        initialFolders: const [],
        turningOn: true,
        preferChoosing: true,
        onResult: (_) {},
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a folder'));
    await tester.pumpAndSettle();

    final albumsTopLeftBefore = tester.getTopLeft(find.text('Albums'));

    final firstIcon = find.byType(Icon).first;
    await tester.tap(firstIcon);
    await tester.pumpAndSettle();

    final albumsTopLeftAfter = tester.getTopLeft(find.text('Albums'));
    expect(albumsTopLeftAfter, equals(albumsTopLeftBefore));

    expect(find.text('1'), findsOneWidget);
    expect(find.text('Add (1)'), findsOneWidget);
  });
}
