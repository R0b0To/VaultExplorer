import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/widgets/add_item_menu_button.dart';

import 'symlink_test_support.dart';

void main() {
  late FakeSymlinkFileIo fileIo;
  late FakeOperationService opService;

  setUp(() {
    fileIo = FakeSymlinkFileIo();
    opService = FakeOperationService();
  });

  Widget app(Widget home) => ProviderScope(
    overrides: [
      vaultFileIoApiProvider.overrideWith((ref) => fileIo),
      fileOperationServiceProvider.overrideWithValue(opService),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: home),
    ),
  );

  Future<void> openDialog(
    WidgetTester tester, {
    String dir = '',
    List<RawEntry> entries = const [],
  }) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => BrowserDialogs.showCreateSymlink(
              context,
              container: cryptomatorContainer(),
              currentDirPath: dir,
              existingEntries: entries,
              onSuccess: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder nameField() => find.byType(TextField).at(0);
  Finder targetField() => find.byType(TextField).at(1);
  Finder createButton() => find.widgetWithText(TextButton, 'Create');
  bool createEnabled(WidgetTester tester) => tester.widget<TextButton>(createButton()).onPressed != null;

  group('New symbolic link dialog', () {
    testWidgets('shows the title, both fields and the "never followed" helper text', (tester) async {
      await openDialog(tester);
      expect(find.text('New symbolic link'), findsOneWidget);
      expect(find.text('Link name'), findsOneWidget);
      expect(find.text('Points to'), findsOneWidget);
      expect(find.textContaining('never followed or opened here'), findsOneWidget);
      expect(createEnabled(tester), isFalse);
    });

    testWidgets('needs both a name and a target', (tester) async {
      await openDialog(tester);
      await tester.enterText(nameField(), 'ln');
      await tester.pump();
      expect(createEnabled(tester), isFalse);
      expect(find.textContaining("can't contain a null"), findsNothing); // empty is not an error line

      await tester.enterText(targetField(), '../target');
      await tester.pump();
      expect(createEnabled(tester), isTrue);

      await tester.enterText(nameField(), '');
      await tester.pump();
      expect(createEnabled(tester), isFalse);
    });

    testWidgets('a NUL in the target is refused with its own message', (tester) async {
      await openDialog(tester);
      await tester.enterText(nameField(), 'ln');
      await tester.enterText(targetField(), 'a\u0000b');
      await tester.pump();
      expect(find.text("Target can't contain a null character"), findsOneWidget);
      expect(createEnabled(tester), isFalse);
    });

    testWidgets('over 32767 bytes of multibyte text is too long, 32766 is fine', (tester) async {
      await openDialog(tester);
      await tester.enterText(nameField(), 'ln');
      await tester.enterText(targetField(), 'é' * 16384); // 32768 bytes
      await tester.pump();
      expect(find.text('Target is too long (maximum 32,767 bytes)'), findsOneWidget);
      expect(createEnabled(tester), isFalse);

      await tester.enterText(targetField(), 'é' * 16383); // 32766 bytes
      await tester.pump();
      expect(find.text('Target is too long (maximum 32,767 bytes)'), findsNothing);
      expect(createEnabled(tester), isTrue);
    });

    testWidgets('a name already used by a link in this folder is refused', (tester) async {
      fileIo.links = [link('taken')];
      await openDialog(tester);
      await tester.enterText(nameField(), 'taken');
      await tester.enterText(targetField(), 'x');
      await tester.pump();
      expect(find.text('A file, folder or link with this name already exists'), findsOneWidget);
      expect(createEnabled(tester), isFalse);

      await tester.enterText(nameField(), 'free');
      await tester.pump();
      expect(find.text('A file, folder or link with this name already exists'), findsNothing);
      expect(createEnabled(tester), isTrue);
    });

    testWidgets('a name already used by a file is refused too', (tester) async {
      await openDialog(
        tester,
        entries: const [RawEntry(name: 'a.txt', isDir: false, sizeBytes: 1, modifiedSecs: 0)],
      );
      await tester.enterText(nameField(), 'a.txt');
      await tester.enterText(targetField(), 'x');
      await tester.pump();
      expect(createEnabled(tester), isFalse);
    });

    testWidgets('creating sends the path and the target as written, then announces the change', (tester) async {
      await openDialog(tester, dir: 'docs/sub');
      await tester.enterText(nameField(), 'ünï link');
      await tester.enterText(targetField(), '../Ziel ☃/x');
      await tester.pump();
      await tester.tap(createButton());
      await tester.pumpAndSettle();

      expect(fileIo.created, [('docs/sub/ünï link', '../Ziel ☃/x')]);
      expect(opService.notified, [7]);
      expect(find.text('New symbolic link'), findsNothing); // dialog closed
    });

    testWidgets('a refusal from the engine is reported and nothing is announced', (tester) async {
      fileIo.createResult = false;
      await openDialog(tester);
      await tester.enterText(nameField(), 'ln');
      await tester.enterText(targetField(), 'x');
      await tester.pump();
      await tester.tap(createButton());
      await tester.pumpAndSettle();

      expect(fileIo.created.length, 1);
      expect(opService.notified, isEmpty);
      expect(find.textContaining("Couldn't create"), findsOneWidget);
    });

    testWidgets('a read-only container never opens the dialog', (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => BrowserDialogs.showCreateSymlink(
                context,
                container: cryptomatorContainer(readOnly: true),
                currentDirPath: '',
                existingEntries: const [],
                onSuccess: () {},
                readOnly: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('New symbolic link'), findsNothing);
    });
  });

  group('Add menu gating', () {
    Widget menu(MountedContainer container, {bool readOnly = false, bool hideImport = false}) => app(
      AddItemMenuButton(
        isReadOnly: readOnly,
        hasArchiveContext: false,
        container: container,
        currentDirPath: '',
        currentItems: const [],
        onSetStatus: (message, {bool error = false}) {},
        onExtractArchive: () async {},
        onSignalActivity: () {},
        onCaptureFromCamera: () async {},
        onRecordAudio: () async {},
        onImportFilesFromDevice: () async {},
        onImportFolderFromDevice: () async {},
        onAddVaultItem: (_) async {},
        hideImportAndSecureItemActions: hideImport,
      ),
    );

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
    }

    testWidgets('a Cryptomator vault offers "New symbolic link"', (tester) async {
      await tester.pumpWidget(menu(cryptomatorContainer()));
      await openMenu(tester);
      expect(find.text('New symbolic link'), findsOneWidget);
      expect(find.byIcon(Icons.add_link), findsOneWidget);
    });

    testWidgets('other vault formats do not', (tester) async {
      for (final format in ['veracrypt', 'gocryptfs', 'cryfs', 'luks']) {
        await tester.pumpWidget(const SizedBox()); // fresh state: the previous menu was left open
        await tester.pumpWidget(menu(cryptomatorContainer(format: format)));
        await openMenu(tester);
        expect(find.text('New folder'), findsOneWidget, reason: 'menu opened for $format');
        expect(find.text('New symbolic link'), findsNothing, reason: format);
      }
    });

    testWidgets('plain storage (import/secure-item actions hidden) does not', (tester) async {
      await tester.pumpWidget(menu(cryptomatorContainer(), hideImport: true));
      await openMenu(tester);
      expect(find.text('New folder'), findsOneWidget);
      expect(find.text('New symbolic link'), findsNothing);
    });

    testWidgets('a read-only vault has no add menu at all', (tester) async {
      await tester.pumpWidget(menu(cryptomatorContainer(readOnly: true), readOnly: true));
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.text('New symbolic link'), findsNothing);
    });
  });
}
