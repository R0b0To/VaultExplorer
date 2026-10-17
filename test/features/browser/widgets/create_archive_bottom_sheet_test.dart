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
        onCreate: (a, b, c, d, e) async {},
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
        onCreate: (a, b, c, d, e) async {},
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Recommendation banner should appear
    expect(find.textContaining('Pre-compressed media files detected'), findsOneWidget);
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
        onCreate: (a, b, c, d, e) async {},
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
        onCreate: (a, b, c, d, e) async {},
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

  testWidgets('Advanced options accordion expands and submits correct parameters',
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
        onCreate: (path, fmt, pass, encFilenames, lvl) async {
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

    // Tap Advanced Options to expand accordion
    await tester.tap(find.text('Advanced Options'));
    await tester.pumpAndSettle();

    // Advanced controls should now be visible
    expect(find.text('Compression Level'), findsOneWidget);
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
        onCreate: (a, b, c, d, e) async {},
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
}
