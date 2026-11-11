import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/widgets/vault_listing_notices.dart';

import 'symlink_test_support.dart';

void main() {
  late FakeSymlinkFileIo fileIo;
  late FakeOperationService opService;

  setUp(() {
    fileIo = FakeSymlinkFileIo();
    opService = FakeOperationService();
  });

  Widget app(MountedContainer container, {String dir = ''}) => ProviderScope(
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
      home: Scaffold(
        body: VaultListingNotices(
          container: container,
          dirPath: dir,
          listingToken: const Object(),
        ),
      ),
    ),
  );

  Future<void> openDetails(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.link).first);
    await tester.pumpAndSettle();
  }

  group('refresh', () {
    testWidgets('shows nothing for a folder without links', (tester) async {
      await tester.pumpWidget(app(cryptomatorContainer()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.link), findsNothing);
    });

    testWidgets('a content change in this volume brings a new link into view', (tester) async {
      await tester.pumpWidget(app(cryptomatorContainer()));
      await tester.pumpAndSettle();

      fileIo.links = [link('fresh')];
      opService.notifyVolumeContentChanged(7);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets('a change in another volume does not reload', (tester) async {
      await tester.pumpWidget(app(cryptomatorContainer()));
      await tester.pumpAndSettle();
      final before = fileIo.listCalls;

      opService.notifyVolumeContentChanged(99);
      await tester.pumpAndSettle();

      expect(fileIo.listCalls, before);
    });

    testWidgets('a non-Cryptomator container is not reloaded by changes', (tester) async {
      await tester.pumpWidget(app(cryptomatorContainer(format: 'veracrypt')));
      await tester.pumpAndSettle();
      final before = fileIo.listCalls;

      opService.notifyVolumeContentChanged(7);
      await tester.pumpAndSettle();

      expect(fileIo.listCalls, before);
    });

    testWidgets('the listener is removed when the notice goes away', (tester) async {
      await tester.pumpWidget(app(cryptomatorContainer()));
      await tester.pumpAndSettle();
      expect(opService.listeners, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      expect(opService.listeners, isEmpty);
    });
  });

  group('details sheet management', () {
    testWidgets('tap-to-copy stays and there is no open/follow action', (tester) async {
      fileIo.links = [link('ln')];
      await tester.pumpWidget(app(cryptomatorContainer()));
      await tester.pumpAndSettle();
      await openDetails(tester);

      expect(find.text('target-of-ln'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsNothing);
      expect(find.byIcon(Icons.launch), findsNothing);
    });

    testWidgets('Delete asks first, removes only the link, announces the change and closes the sheet', (tester) async {
      fileIo.links = [link('ln')];
      await tester.pumpWidget(app(cryptomatorContainer()));
      await tester.pumpAndSettle();
      await openDetails(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Delete symbolic link?'), findsOneWidget);
      expect(fileIo.deleted, isEmpty); // nothing happens before the confirmation

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(fileIo.deleted, ['ln']);
      expect(opService.notified, contains(7));
      expect(find.text('Delete symbolic link?'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing); // sheet closed: nothing left to show
      expect(find.byIcon(Icons.link), findsNothing); // and the banner is gone
    });

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      fileIo.links = [link('ln')];
      await tester.pumpWidget(app(cryptomatorContainer()));
      await tester.pumpAndSettle();
      await openDetails(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(fileIo.deleted, isEmpty);
      expect(opService.notified, isEmpty);
    });

    testWidgets('a failed delete is reported and the link stays', (tester) async {
      fileIo.links = [link('ln')];
      fileIo.deleteResult = false;
      await tester.pumpWidget(app(cryptomatorContainer()));
      await tester.pumpAndSettle();
      await openDetails(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't delete"), findsOneWidget);
      expect(opService.notified, isEmpty);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('Rename moves the link within its folder and refreshes the list', (tester) async {
      fileIo.links = [link('old')];
      await tester.pumpWidget(app(cryptomatorContainer(), dir: 'docs'));
      await tester.pumpAndSettle();
      await openDetails(tester);

      await tester.tap(find.byIcon(Icons.drive_file_rename_outline));
      await tester.pumpAndSettle();
      expect(find.text('Rename symbolic link'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'new name');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(fileIo.renamed, [('docs/old', 'docs/new name')]);
      expect(opService.notified, contains(7));
      expect(find.text('new name'), findsOneWidget);
      expect(find.text('old'), findsNothing);
    });

    testWidgets('Rename refuses the name of another link and an unchanged name', (tester) async {
      fileIo.links = [link('a'), link('b')];
      await tester.pumpWidget(app(cryptomatorContainer()));
      await tester.pumpAndSettle();
      await openDetails(tester);

      await tester.tap(find.byIcon(Icons.drive_file_rename_outline).first);
      await tester.pumpAndSettle();
      TextButton renameButton() => tester.widget<TextButton>(find.widgetWithText(TextButton, 'Rename'));

      expect(renameButton().onPressed, isNull); // unchanged name
      await tester.enterText(find.byType(TextField), 'b');
      await tester.pump();
      expect(find.text('A file, folder or link with this name already exists'), findsOneWidget);
      expect(renameButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'c');
      await tester.pump();
      expect(renameButton().onPressed, isNotNull);
    });

    testWidgets('a failed rename is reported', (tester) async {
      fileIo.links = [link('old')];
      fileIo.renameResult = false;
      await tester.pumpWidget(app(cryptomatorContainer()));
      await tester.pumpAndSettle();
      await openDetails(tester);

      await tester.tap(find.byIcon(Icons.drive_file_rename_outline));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't rename"), findsOneWidget);
      expect(opService.notified, isEmpty);
    });

    testWidgets('a read-only vault gets no Delete or Rename', (tester) async {
      fileIo.links = [link('ln')];
      await tester.pumpWidget(app(cryptomatorContainer(readOnly: true)));
      await tester.pumpAndSettle();
      await openDetails(tester);

      expect(find.text('target-of-ln'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.drive_file_rename_outline), findsNothing);
    });
  });
}
