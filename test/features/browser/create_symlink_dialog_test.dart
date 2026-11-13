import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/volume_filesystem_registry.dart';
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
    VolumeFilesystemRegistry.clearForTesting();
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
    MountedContainer? container,
  }) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => BrowserDialogs.showCreateSymlink(
              context,
              container: container ?? cryptomatorContainer(),
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
    testWidgets('shows the title, both fields and the in-vault resolution helper text', (tester) async {
      await openDialog(tester);
      expect(find.text('New symbolic link'), findsOneWidget);
      expect(find.text('Link name'), findsOneWidget);
      expect(find.text('Points to'), findsOneWidget);
      expect(find.textContaining('Relative targets are resolved inside this vault'), findsOneWidget);
      expect(createEnabled(tester), isFalse);
    });

    testWidgets('native disk-image targets must be relative and stay inside the container', (tester) async {
      await openDialog(
        tester,
        container: cryptomatorContainer(format: 'luks2'),
        dir: 'folder',
      );
      expect(find.textContaining('Use a relative path inside this container'), findsOneWidget);
      await tester.enterText(nameField(), 'ln');

      await tester.enterText(targetField(), '/absolute');
      await tester.pump();
      expect(find.text('Target must be a relative path that stays inside this container.'), findsOneWidget);
      expect(createEnabled(tester), isFalse);

      await tester.enterText(targetField(), '../../escape');
      await tester.pump();
      expect(createEnabled(tester), isFalse);

      await tester.enterText(targetField(), '../inside');
      await tester.pump();
      expect(createEnabled(tester), isTrue);
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

  group('Where the link really lives (folder links on the way)', () {
    String targetText(WidgetTester tester) =>
        tester.widget<TextField>(targetField()).controller!.text;

    testWidgets('a native-filesystem target is checked against the physical folder, not the displayed path', (tester) async {
      // "up" is a folder link back to the root, so "up/b/c" reads 3 deep but is really "b/c": 2 deep.
      fileIo.physical['up/b/c'] = 'b/c';
      await openDialog(tester, dir: 'up/b/c', container: cryptomatorContainer(format: 'luks'));
      await tester.enterText(nameField(), 'ln');
      await tester.enterText(targetField(), '../../../x');          // fine by the displayed path, leaves the volume for real
      await tester.pump();
      expect(find.text('Target must be a relative path that stays inside this container.'), findsOneWidget);
      expect(createEnabled(tester), isFalse);

      await tester.enterText(targetField(), '../../x');             // lands exactly on the root
      await tester.pump();
      expect(find.text('Target must be a relative path that stays inside this container.'), findsNothing);
      expect(createEnabled(tester), isTrue);
    });

    testWidgets('and the other way round: a deeper real folder allows what the displayed path would refuse', (tester) async {
      fileIo.physical['short'] = 'one/two/three';                   // reads 1 deep, is 3 deep
      await openDialog(tester, dir: 'short', container: cryptomatorContainer(format: 'luks'));
      await tester.enterText(nameField(), 'ln');
      await tester.enterText(targetField(), '../../../x');
      await tester.pump();
      expect(createEnabled(tester), isTrue);
    });

    testWidgets('if the folder cannot be resolved, validation falls back to the displayed path', (tester) async {
      fileIo.physical['a/b'] = null;
      await openDialog(tester, dir: 'a/b', container: cryptomatorContainer(format: 'luks'));
      await tester.enterText(nameField(), 'ln');
      await tester.enterText(targetField(), '../../../x');
      await tester.pump();
      expect(find.text('Target must be a relative path that stays inside this container.'), findsOneWidget);
    });

    testWidgets('the picker builds the relative target from the physical folder and the physical target', (tester) async {
      fileIo.physical['a-link/sub'] = 'deep/er/sub';                 // reads 2 deep, is 3 deep
      fileIo.browserListings[''] = ['F|3|0|x.txt'];
      await openDialog(tester, dir: 'a-link/sub');
      await tester.tap(find.byTooltip('Browse vault'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('x.txt'));
      await tester.pumpAndSettle();

      expect(targetText(tester), '../../../x.txt');                   // not "../../x.txt", which the displayed path would give
      expect(fileIo.physicalCalls, contains(('x.txt', false)));      // the picked entry keeps its own last name
      expect(fileIo.physicalCalls, contains(('a-link/sub', true)));  // the folder itself is fully resolved
    });

    testWidgets('a pick below a folder link is resolved through that link', (tester) async {
      fileIo.physical['docs-link/notes.txt|nofollow'] = 'docs/notes.txt';
      fileIo.browserListings[''] = ['LD|0|0|docs-link'];
      fileIo.browserListings['docs-link'] = ['F|3|0|notes.txt'];
      await openDialog(tester, dir: 'work');
      await tester.tap(find.byTooltip('Browse vault'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('docs-link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('notes.txt'));
      await tester.pumpAndSettle();

      expect(targetText(tester), '../docs/notes.txt');
    });

    testWidgets('a pick that cannot be resolved safely is refused with a message and fills nothing', (tester) async {
      fileIo.physical['x.txt|nofollow'] = null;
      fileIo.browserListings[''] = ['F|3|0|x.txt'];
      await openDialog(tester, dir: 'a');
      await tester.tap(find.byTooltip('Browse vault'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('x.txt'));
      await tester.pumpAndSettle();

      expect(find.text("Can't build a relative target from here. Type the target instead."), findsOneWidget);
      expect(targetText(tester), '');
    });

    testWidgets('picking from the vault root gives a plain relative name', (tester) async {
      fileIo.browserListings[''] = ['D|0|0|docs'];
      fileIo.browserListings['docs'] = ['F|3|0|a.txt'];
      await openDialog(tester);
      await tester.tap(find.byTooltip('Browse vault'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('docs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('a.txt'));
      await tester.pumpAndSettle();
      expect(targetText(tester), 'docs/a.txt');
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

    testWidgets('unsupported formats and unknown native filesystems do not', (tester) async {
      for (final format in ['veracrypt', 'gocryptfs', 'cryfs', 'luks1', 'bitlocker', 'plain']) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(menu(cryptomatorContainer(format: format)));
        await openMenu(tester);
        expect(find.text('New Folder'), findsOneWidget, reason: 'menu opened for $format');
        expect(find.text('New symbolic link'), findsNothing, reason: format);
      }
    });

    testWidgets('LUKS and VeraCrypt offer links on ext and NTFS', (tester) async {
      for (final format in ['luks1', 'luks2', 'veracrypt']) {
        for (final fs in [FilesystemType.ext, FilesystemType.ntfs]) {
          VolumeFilesystemRegistry.record(7, fs);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(menu(cryptomatorContainer(format: format)));
          await openMenu(tester);
          expect(find.text('New symbolic link'), findsOneWidget, reason: '$format / $fs');
        }
      }
    });

    testWidgets('plain storage (import/secure-item actions hidden) does not', (tester) async {
      await tester.pumpWidget(menu(cryptomatorContainer(), hideImport: true));
      await openMenu(tester);
      expect(find.text('New Folder'), findsOneWidget);
      expect(find.text('New symbolic link'), findsNothing);
    });

    testWidgets('a read-only vault has no add menu at all', (tester) async {
      await tester.pumpWidget(menu(cryptomatorContainer(readOnly: true), readOnly: true));
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.text('New symbolic link'), findsNothing);
    });
  });
}
