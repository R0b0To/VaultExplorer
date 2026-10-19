import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/features/browser/widgets/archive_paste_options_sheet.dart';

Widget _buildTestApp({
  required bool isExtract,
  required String archiveName,
  required String destDirPath,
  ArchiveFormatType? format,
  required ValueChanged<ArchivePasteOptions?> onPopped,
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
            final res = await ArchivePasteOptionsSheet.show(
              context,
              isExtract: isExtract,
              archiveName: archiveName,
              destDirPath: destDirPath,
              format: format,
            );
            onPopped(res);
          },
          child: const Text('Open Paste Sheet'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Extract mode shows subfolder radio options and delete original',
      (tester) async {
    ArchivePasteOptions? result;
    await tester.pumpWidget(
      _buildTestApp(
        isExtract: true,
        archiveName: 'photos.zip',
        destDirPath: 'MyFolder',
        onPopped: (res) => result = res,
      ),
    );

    await tester.tap(find.text('Open Paste Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Extract Archive'), findsOneWidget);
    expect(find.text('Extract → photos/'), findsOneWidget);
    expect(find.text('Extract → MyFolder/'), findsOneWidget);
    expect(find.text('Delete original (photos.zip)'), findsOneWidget);
    expect(find.text('Split into volumes'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Extract'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.extractIntoSubfolder, isTrue);
    expect(result!.splitSizeBytes, 0);
  });

  testWidgets('Create paste mode with ZIP shows volume split options and returns preset',
      (tester) async {
    ArchivePasteOptions? result;
    await tester.pumpWidget(
      _buildTestApp(
        isExtract: false,
        archiveName: 'bundle.zip',
        destDirPath: 'DestDir',
        format: ArchiveFormatType.zip,
        onPopped: (res) => result = res,
      ),
    );

    await tester.tap(find.text('Open Paste Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Create Archive'), findsOneWidget);
    expect(find.text('Split into volumes'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('100 MB'), findsOneWidget);
    expect(find.text('500 MB'), findsOneWidget);

    // Pick 100 MB volume split
    await tester.tap(find.text('100 MB'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.splitSizeBytes, 100 * 1024 * 1024);
  });

  testWidgets('Create paste mode with TAR does not show volume split options',
      (tester) async {
    ArchivePasteOptions? result;
    await tester.pumpWidget(
      _buildTestApp(
        isExtract: false,
        archiveName: 'bundle.tar.gz',
        destDirPath: '',
        format: ArchiveFormatType.tarGz,
        onPopped: (res) => result = res,
      ),
    );

    await tester.tap(find.text('Open Paste Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Create Archive'), findsOneWidget);
    expect(find.text('Split into volumes'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.splitSizeBytes, 0);
  });
}