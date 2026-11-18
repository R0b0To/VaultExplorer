import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_scope_sheet.dart';
import 'package:vaultexplorer/features/library/controllers/library_controller.dart';
import 'package:vaultexplorer/features/library/index/library_scanner.dart';

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
            final res = await showGalleryScopeSheet(
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
    final access = _fakeAccess({'': ['DCIM', 'Pictures']});

    await tester.pumpWidget(
      _buildTestApp(
        access: access,
        initialFolders: const ['DCIM'],
        turningOn: true,
        preferChoosing: false,
        onResult: (res) => result = res,
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Gallery folders'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    // Switch to "Everything in this location"
    await tester.tap(find.text('Everything in this location'));
    await tester.pumpAndSettle();

    // Tap Start
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.folders, isEmpty);
    expect(result!.dontAskAgain, isFalse);
  });

  testWidgets('cancel dismisses without applying', (tester) async {
    ScopeSheetResult? result = const ScopeSheetResult(folders: ['sentinel']);
    final access = _fakeAccess({'': ['DCIM']});

    await tester.pumpWidget(
      _buildTestApp(
        access: access,
        initialFolders: const [],
        turningOn: false,
        preferChoosing: true,
        onResult: (res) => result = res,
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('removing and adding folders via picker works', (tester) async {
    ScopeSheetResult? result;
    final access = _fakeAccess({
      '': ['DCIM', 'Pictures'],
      'DCIM': ['Camera'],
      'DCIM/Camera': [],
    });

    await tester.pumpWidget(
      _buildTestApp(
        access: access,
        initialFolders: const ['Pictures'],
        turningOn: false,
        preferChoosing: true,
        onResult: (res) => result = res,
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Pictures'), findsOneWidget);

    // Remove Pictures
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Pictures'), findsNothing);
    expect(find.text('No folders chosen yet'), findsOneWidget);

    // Tap Add a folder
    await tester.tap(find.text('Add a folder'));
    await tester.pumpAndSettle();

    // Inside folder picker at root
    expect(find.text('DCIM'), findsOneWidget);
    await tester.tap(find.text('DCIM'));
    await tester.pumpAndSettle();

    // Inside DCIM
    expect(find.text('Camera'), findsOneWidget);
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    // Inside DCIM/Camera, tap Add this folder
    expect(find.text('Add this folder'), findsOneWidget);
    await tester.tap(find.text('Add this folder'));
    await tester.pumpAndSettle();

    // Back in sheet with DCIM/Camera selected
    expect(find.text('DCIM/Camera'), findsOneWidget);

    // Tap Save
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.folders, equals(['DCIM/Camera']));
  });

  testWidgets('hold to select multiple folders adds all selected folders',
      (tester) async {
    ScopeSheetResult? result;
    final access = _fakeAccess({
      '': ['DCIM', 'Pictures', 'Screenshots'],
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

    // Tap Add a folder
    await tester.tap(find.text('Add a folder'));
    await tester.pumpAndSettle();

    // Long press on DCIM to enter multi-select
    await tester.longPress(find.text('DCIM'));
    await tester.pumpAndSettle();

    // DCIM is selected, 1 in title
    expect(find.text('1'), findsOneWidget);

    // Tap Pictures to also select it
    await tester.tap(find.text('Pictures'));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);

    // Bottom button displays Add (2)
    expect(find.text('Add (2)'), findsOneWidget);
    await tester.tap(find.text('Add (2)'));
    await tester.pumpAndSettle();

    // Back in sheet, both DCIM and Pictures are present
    expect(find.text('DCIM'), findsOneWidget);
    expect(find.text('Pictures'), findsOneWidget);

    // Tap Start
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.folders, containsAll(['DCIM', 'Pictures']));
    expect(result!.folders.length, 2);
  });

  testWidgets('dontAskAgain checkbox returns checked state', (tester) async {
    ScopeSheetResult? result;
    final access = _fakeAccess({
      '': ['DCIM'],
    });

    await tester.pumpWidget(
      _buildTestApp(
        access: access,
        initialFolders: const ['DCIM'],
        turningOn: true,
        preferChoosing: false,
        onResult: (res) => result = res,
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text("Don't ask again"), findsOneWidget);
    // Tap the checkbox / row
    await tester.tap(find.text("Don't ask again"));
    await tester.pumpAndSettle();

    // Tap Start
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.dontAskAgain, isTrue);
    expect(result!.folders, equals(['DCIM']));
  });

  testWidgets('tapping folder icon selects folder without shifting text',
      (tester) async {
    final access = _fakeAccess({
      '': ['DCIM', 'Pictures'],
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

    // Verify position of DCIM text before selection
    final dcimTopLeftBefore = tester.getTopLeft(find.text('DCIM'));

    // Tap the folder icon of DCIM
    final firstIcon = find.byType(Icon).first;
    await tester.tap(firstIcon);
    await tester.pumpAndSettle();

    // Verify DCIM text position did NOT shift
    final dcimTopLeftAfter = tester.getTopLeft(find.text('DCIM'));
    expect(dcimTopLeftAfter, equals(dcimTopLeftBefore));

    // Multi-select active with 1 item
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Add (1)'), findsOneWidget);
  });
}
