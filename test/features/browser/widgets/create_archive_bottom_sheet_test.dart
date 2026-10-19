import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/widgets/create_archive_bottom_sheet.dart';

Widget _buildTestApp({
  required MountedContainer container,
  required String currentDirPath,
  required List<RawEntry> existingEntries,
  required String suggestedName,
  List<RawEntry> selectedEntries = const [],
  int? freeSpace,
  required Future<void> Function(
    String destPathInContainer,
    ArchiveFormatType format,
    String? passphrase,
    bool encryptFilenames,
    ArchiveCompressionLevel compressionLevel,
    ArchiveCompressionMethod compressionMethod,
  ) onCreate,
}) {
  return ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              CreateArchiveBottomSheet.show(
                context,
                container: container,
                currentDirPath: currentDirPath,
                existingEntries: existingEntries,
                suggestedName: suggestedName,
                selectedEntries: selectedEntries,
                freeSpace: freeSpace,
                onCreate: onCreate,
              );
            },
            child: const Text('Open Sheet'),
          ),
        ),
      ),
    ),
  );
}

MountedContainer _mockContainer({
  int volId = 1,
  String displayName = 'Test Vault',
  int totalSpace = 1000000000,
  int freeSpace = 500000000,
}) {
  return MountedContainer(
    volId: volId,
    displayName: displayName,
    uri: '/storage/test',
    rootFiles: const [],
    mountedAt: DateTime(2026, 1, 1),
    totalSpace: totalSpace,
    freeSpace: freeSpace,
    readOnly: false,
    containerFormat: 'cryfs',
  );
}

// A getter, not a final: a fresh finder per use avoids stale cached matches.
Finder get _compressionPicker =>
    find.byType(DropdownButtonFormField<ArchiveCompressionLevel>);

Finder get _methodPicker =>
    find.byType(DropdownButtonFormField<ArchiveCompressionMethod>);

/// Opens the sheet (suggested name is a .zip) and switches it to [extension].
Future<void> _openAndSwitchFormat(WidgetTester tester, String extension) async {
  await tester.tap(find.text('Open Sheet'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('.zip'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(extension));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Create'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Create'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Renders bottom sheet with decoupled name and extension pill',
      (tester) async {
    final container = _mockContainer();
    final selected = [
      RawEntry(
        name: 'doc1.pdf',
        isDir: false,
        sizeBytes: 1024 * 1024,
        modifiedSecs: 1700000000,
      ),
      RawEntry(
        name: 'doc2.pdf',
        isDir: false,
        sizeBytes: 2 * 1024 * 1024,
        modifiedSecs: 1700000000,
      ),
    ];

    await tester.pumpWidget(
      _buildTestApp(
        container: container,
        currentDirPath: '',
        existingEntries: [],
        suggestedName: 'documents.zip',
        selectedEntries: selected,
        freeSpace: 100 * 1024 * 1024,
        onCreate: (a, b, c, d, e, f) async {},
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Verify Title & Subtitle with items count and total size
    expect(find.text('Create Archive'), findsOneWidget);
    expect(find.textContaining('Compressing 2 items (3 MB)'), findsOneWidget);

    // Verify name field only contains the stem, not the extension, and does not autofocus
    final textField = tester.widget<TextField>(find.byType(TextField).first);
    expect(textField.controller?.text, 'documents');
    expect(textField.autofocus, false);

    // Verify extension pill displays .zip
    expect(find.text('.zip'), findsOneWidget);

    // Labels live inside the inputs; there are no separate section headings.
    expect(find.widgetWithText(TextField, 'Archive Name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password (Optional)'), findsOneWidget);
    expect(
      find.widgetWithText(
        DropdownButtonFormField<ArchiveCompressionLevel>,
        'Compression Level',
      ),
      findsOneWidget,
    );
    expect(find.text('Security'), findsNothing);
  });

  testWidgets('Smart media recommendation triggers for media files',
      (tester) async {
    final container = _mockContainer();
    final selected = [
      RawEntry(
        name: 'video.mp4',
        isDir: false,
        sizeBytes: 50 * 1024 * 1024,
        modifiedSecs: 1700000000,
      ),
      RawEntry(
        name: 'song.m4a',
        isDir: false,
        sizeBytes: 10 * 1024 * 1024,
        modifiedSecs: 1700000000,
      ),
    ];

     await tester.pumpWidget(
      _buildTestApp(
        container: container,
        currentDirPath: '',
        existingEntries: [],
        suggestedName: 'media.zip',
        selectedEntries: selected,
        freeSpace: 200 * 1024 * 1024,
        onCreate: (a, b, c, d, e, f) async {},
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

   // Store compression level should be auto-selected for pre-compressed media
    expect(find.text('Store (0) — No compression'), findsOneWidget);
  });

  testWidgets('Password confirmation and strength validation work',
      (tester) async {
    final container = _mockContainer();

      await tester.pumpWidget(
      _buildTestApp(
        container: container,
        currentDirPath: '',
        existingEntries: [],
        suggestedName: 'backup.zip',
        selectedEntries: [],
        freeSpace: 100 * 1024 * 1024,
        onCreate: (a, b, c, d, e, f) async {},
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Password field should exist
    final passwordFinder = find.widgetWithText(TextField, 'Password (Optional)');
    expect(passwordFinder, findsOneWidget);

    // Enter a password
    await tester.enterText(passwordFinder, 'hunter2');
    await tester.pumpAndSettle();

    // Strength meter and Confirm Password field should appear
    expect(find.text('Fair'), findsOneWidget);
    final confirmFinder = find.widgetWithText(TextField, 'Confirm Password');
    expect(confirmFinder, findsOneWidget);

    // Mismatched confirm password should show error
    await tester.enterText(confirmFinder, 'wrong');
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);

    // Create button should be disabled
    final createBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'));
    expect(createBtn.onPressed, isNull);

    // Matching password clears error
    await tester.enterText(confirmFinder, 'hunter2');
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsNothing);
  });

  testWidgets('Insufficient space disables Create button and shows warning banner',
      (tester) async {
    final container = _mockContainer();
    final selected = [
      RawEntry(
        name: 'huge_file.dat',
        isDir: false,
        sizeBytes: 500 * 1024 * 1024, // 500 MB
        modifiedSecs: 1700000000,
      ),
    ];

     await tester.pumpWidget(
      _buildTestApp(
        container: container,
        currentDirPath: '',
        existingEntries: [],
        suggestedName: 'test.zip',
        selectedEntries: selected,
        freeSpace: 100 * 1024 * 1024, // Only 100 MB free
        onCreate: (a, b, c, d, e, f) async {},
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Warning banner should be displayed
    expect(find.textContaining('Not enough free space'), findsOneWidget);

    // Create button should be disabled
    final createBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'));
    expect(createBtn.onPressed, isNull);
  });

  testWidgets('Compression picker is shown by default for ZIP, with no advanced toggle',
      (tester) async {
    final container = _mockContainer();
    String? createdPath;
    ArchiveFormatType? createdFormat;
    String? createdPassphrase;
    bool? createdEncryptFilenames;
    ArchiveCompressionLevel? createdLvl;

    await tester.pumpWidget(
      _buildTestApp(
        container: container,
        currentDirPath: 'my_folder',
        existingEntries: [],
        suggestedName: 'archive.zip',
        selectedEntries: [],
        freeSpace: 1000 * 1024 * 1024,
        onCreate: (path, fmt, pass, encFilenames, lvl, method) async {
          createdPath = path;
          createdFormat = fmt;
          createdPassphrase = pass;
          createdEncryptFilenames = encFilenames;
          createdLvl = lvl;
        },
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // The toggle is gone and the picker is visible without any tap.
    expect(find.text('Advanced Options'), findsNothing);
    expect(_compressionPicker, findsOneWidget);
    // Split into volumes, Exclude system files, and Delete original files should NOT be present in this sheet
    expect(find.text('Split into volumes'), findsNothing);
    expect(find.text('Exclude system files'), findsNothing);
    expect(find.text('Delete original files after archiving'), findsNothing);

    // Submit Create
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(createdPath, 'my_folder/archive.zip');
    expect(createdFormat, ArchiveFormatType.zip);
    expect(createdPassphrase, isNull);
    expect(createdEncryptFilenames, false);
    expect(createdLvl, ArchiveCompressionLevel.normal);
  });

  testWidgets('Picked compression level is submitted', (tester) async {
    ArchiveCompressionLevel? createdLvl;

    await tester.pumpWidget(
      _buildTestApp(
        container: _mockContainer(),
        currentDirPath: '',
        existingEntries: [],
        suggestedName: 'archive.zip',
        selectedEntries: [],
        freeSpace: 1000 * 1024 * 1024,
         onCreate: (path, fmt, pass, encFilenames, lvl, method) async {
          createdLvl = lvl;
        },
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(_compressionPicker);
    await tester.pumpAndSettle();
    // `.last`: the open menu repeats the selected item's text.
    await tester.tap(find.text('Ultra (9) — Smallest size').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(createdLvl, ArchiveCompressionLevel.ultra);
  });

  testWidgets('Compression picker only shows for formats that compress',
      (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        container: _mockContainer(),
        currentDirPath: '',
        existingEntries: [],
        suggestedName: 'archive.zip',
        selectedEntries: [],
        freeSpace: 1000 * 1024 * 1024,
        onCreate: (a, b, c, d, e, f) async {},
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

   // Every format offered in the picker, in menu order, with whether it
        // should show the compression level.
        const expectations = <(String, bool)>[
          ('.zip', true),
          ('.7z', true),
          ('.tar', false),
          ('.tar.gz', true),
          ('.tar.xz', true),
          ('.tar.zst', true),
        ];

    var currentExt = '.zip';
    for (final (ext, shown) in expectations) {
      if (ext != currentExt) {
        await tester.tap(find.text(currentExt)); // opens the format menu
        await tester.pumpAndSettle();
        await tester.tap(find.text(ext).last); // the menu item
        await tester.pumpAndSettle();
        currentExt = ext;
      }
      expect(
        _compressionPicker,
        shown ? findsOneWidget : findsNothing,
        reason: 'compression picker visibility for $ext',
      );
    }
  });

  test('supportsCompressionLevel matches what the engine can compress', () {
    const notCompressed = {
      ArchiveFormatType.tar,
      ArchiveFormatType.iso,
      ArchiveFormatType.cpio,
    };
    for (final f in ArchiveFormatType.values) {
      expect(
        f.supportsCompressionLevel,
        !notCompressed.contains(f),
        reason: f.displayLabel,
      );
    }
  });

  testWidgets('Encrypt file names is hidden for ZIP and shown for 7-Zip',
      (tester) async {
    final container = _mockContainer();

    await tester.pumpWidget(
      _buildTestApp(
        container: container,
        currentDirPath: '',
        existingEntries: [],
        suggestedName: 'archive.zip',
        selectedEntries: [],
        freeSpace: 100 * 1024 * 1024,
        onCreate: (a, b, c, d, e, f) async {},
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Default format is ZIP -> Encrypt file names must NOT be shown
    expect(find.text('Encrypt file names'), findsNothing);

    // Switch format to 7-Zip
    await tester.tap(find.text('.zip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('.7z'));
    await tester.pumpAndSettle();

    // Now format is 7-Zip -> Encrypt file names MUST be shown
    expect(find.text('Encrypt file names'), findsOneWidget);
  });

  group('Compression method', () {
    Widget app(
      void Function(ArchiveFormatType, ArchiveCompressionLevel,
              ArchiveCompressionMethod)
          onCreated,
    ) =>
        _buildTestApp(
          container: _mockContainer(),
          currentDirPath: '',
          existingEntries: [],
          suggestedName: 'archive.zip',
          selectedEntries: [],
          freeSpace: 1000 * 1024 * 1024,
          onCreate: (path, fmt, pass, encFilenames, lvl, method) async {
            onCreated(fmt, lvl, method);
          },
        );

    testWidgets('7-Zip offers LZMA2 (preselected), LZMA and Deflate',
        (tester) async {
      ArchiveCompressionMethod? created;
      await tester.pumpWidget(app((_, __, m) => created = m));
      await _openAndSwitchFormat(tester, '.7z');

      expect(_methodPicker, findsOneWidget);
      expect(
        find.widgetWithText(
          DropdownButtonFormField<ArchiveCompressionMethod>,
          'Compression method',
        ),
        findsOneWidget,
      );
      expect(find.text('LZMA2'), findsOneWidget);

      await tester.tap(_methodPicker);
      await tester.pumpAndSettle();
      expect(find.text('LZMA2'), findsWidgets);
      expect(find.text('LZMA'), findsOneWidget);
      expect(find.text('Deflate'), findsOneWidget);
      await tester.tap(find.text('LZMA2').last);
      await tester.pumpAndSettle();

      await _submit(tester);
      expect(created, ArchiveCompressionMethod.lzma2);
    });

   testWidgets('The picked method is submitted',
        (tester) async {
      ArchiveCompressionMethod? created;
      await tester.pumpWidget(app((_, __, m) => created = m));
      await _openAndSwitchFormat(tester, '.7z');

      await tester.tap(_methodPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('LZMA').last);
      await tester.pumpAndSettle();
      await _submit(tester);
      expect(created, ArchiveCompressionMethod.lzma);
    });

    testWidgets('Deflate can be picked', (tester) async {
      ArchiveCompressionMethod? created;
      await tester.pumpWidget(app((_, __, m) => created = m));
      await _openAndSwitchFormat(tester, '.7z');

      await tester.tap(_methodPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deflate').last);
      await tester.pumpAndSettle();
      await _submit(tester);
      expect(created, ArchiveCompressionMethod.deflate);
    });

   testWidgets('ZIP has no picker, and `auto` is sent',
        (tester) async {
      ArchiveFormatType? fmt;
      ArchiveCompressionMethod? created;
      await tester.pumpWidget(app((f, _, m) {
        fmt = f;
        created = m;
      }));
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(_methodPicker, findsNothing);
      expect(find.textContaining('ZIP always compresses with Deflate.'),
          findsNothing);

      await _submit(tester);
      expect(fmt, ArchiveFormatType.zip);
      expect(created, ArchiveCompressionMethod.auto);
    });

     testWidgets('TAR.XZ is LZMA2 and has nothing to point at',
        (tester) async {
      ArchiveCompressionMethod? created;
      await tester.pumpWidget(app((_, __, m) => created = m));
      await _openAndSwitchFormat(tester, '.tar.xz');

      expect(_methodPicker, findsNothing);
      expect(find.textContaining('TAR.XZ always compresses with LZMA2.'),
          findsNothing);
      await _submit(tester);
      expect(created, ArchiveCompressionMethod.auto);
    });

    testWidgets('Plain TAR does not compress, so there is no method row',
        (tester) async {
      await tester.pumpWidget(app((_, __, ___) {}));
      await _openAndSwitchFormat(tester, '.tar');

      expect(_methodPicker, findsNothing);
      expect(find.textContaining('always compresses with'), findsNothing);
      expect(find.textContaining('no method to choose'), findsNothing);
    });

      testWidgets('Store has no codec: 7z method picker is hidden',
        (tester) async {
      ArchiveCompressionLevel? lvl;
      ArchiveCompressionMethod? created;
      await tester.pumpWidget(app((_, l, m) {
        lvl = l;
        created = m;
      }));
      await _openAndSwitchFormat(tester, '.7z');

      // Pick LZMA first, so it's clear Store overrides a real choice.
      await tester.tap(_methodPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('LZMA').last);
      await tester.pumpAndSettle();

      await tester.tap(_compressionPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Store (0) — No compression').last);
      await tester.pumpAndSettle();

      expect(_methodPicker, findsNothing);
      expect(find.text("Store doesn't compress, so there is no method to choose."),
          findsNothing);

      await _submit(tester);
      expect(lvl, ArchiveCompressionLevel.store);
      expect(created, ArchiveCompressionMethod.auto);
    });

    testWidgets('Leaving Store brings the picker back with the earlier pick',
        (tester) async {
      ArchiveCompressionMethod? created;
      await tester.pumpWidget(app((_, __, m) => created = m));
      await _openAndSwitchFormat(tester, '.7z');

      await tester.tap(_methodPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deflate').last);
      await tester.pumpAndSettle();

      await tester.tap(_compressionPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Store (0) — No compression').last);
      await tester.pumpAndSettle();
      expect(_methodPicker, findsNothing);

      await tester.tap(_compressionPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Normal (5) — Balanced').last);
      await tester.pumpAndSettle();

      expect(_methodPicker, findsOneWidget);
      await _submit(tester);
      expect(created, ArchiveCompressionMethod.deflate);
    });

    testWidgets('A 7z pick does not leak into ZIP', (tester) async {
      ArchiveFormatType? fmt;
      ArchiveCompressionMethod? created;
      await tester.pumpWidget(app((f, _, m) {
        fmt = f;
        created = m;
      }));
      await _openAndSwitchFormat(tester, '.7z');
      await tester.tap(_methodPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('LZMA').last);
      await tester.pumpAndSettle();

      // Back to ZIP: ZIP can only write Deflate, so it must not get LZMA.
      await tester.tap(find.text('.7z'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('.zip').last);
      await tester.pumpAndSettle();

      await _submit(tester);
      expect(fmt, ArchiveFormatType.zip);
      expect(created, ArchiveCompressionMethod.auto);
    });
  });

  group('Compression method support rules', () {
    test('only 7z lets the user choose, LZMA2 first', () {
      for (final f in ArchiveFormatType.values) {
        final methods = f.selectableCompressionMethods;
        if (f == ArchiveFormatType.sevenZip) {
          expect(methods, [
            ArchiveCompressionMethod.lzma2,
            ArchiveCompressionMethod.lzma,
            ArchiveCompressionMethod.deflate,
          ]);
        } else {
          expect(methods, isEmpty, reason: f.displayLabel);
        }
        expect(methods.contains(ArchiveCompressionMethod.auto), isFalse);
      }
    });

    test('every compressing format without a choice names its one codec', () {
      for (final f in ArchiveFormatType.values) {
        final fixed = f.fixedCompressionLabel;
        final tied = f.supportsCompressionLevel &&
            f.selectableCompressionMethods.isEmpty;
        expect(fixed != null, tied, reason: f.displayLabel);
      }
      expect(ArchiveFormatType.zip.fixedCompressionLabel, 'Deflate');
      expect(ArchiveFormatType.tarGz.fixedCompressionLabel, 'Deflate');
      expect(ArchiveFormatType.tarXz.fixedCompressionLabel, 'LZMA2');
      expect(ArchiveFormatType.tarLzma.fixedCompressionLabel, 'LZMA');
      expect(ArchiveFormatType.tarBz2.fixedCompressionLabel, 'BZip2');
      expect(ArchiveFormatType.tarZstd.fixedCompressionLabel, 'Zstandard');
    });

    test('codes match the native engine (archive_engine.h)', () {
      expect(ArchiveCompressionMethod.auto.code, 0);
      expect(ArchiveCompressionMethod.deflate.code, 1);
      expect(ArchiveCompressionMethod.lzma.code, 2);
      expect(ArchiveCompressionMethod.lzma2.code, 3);
    });
  });
}
