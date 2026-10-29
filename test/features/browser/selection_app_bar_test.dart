import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/widgets/selection_app_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/selection_app_bar_wide.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SelectionAppBar - video editor option', () {
    testWidgets('shows Edit video in overflow menu when showEditVideoOption is true', (tester) async {
      bool editedVideo = false;

      await tester.pumpWidget(
        _buildTestApp(
          SelectionAppBar(
            selectedCount: 1,
            selectionLabel: '15 MB',
            singleSelected: true,
            singleFileSelected: true,
            showEditVideoOption: true,
            onEditVideo: () => editedVideo = true,
            showEditImageOption: false,
            onEditImage: () {},
            onClose: () {},
            onSelectAll: () {},
            onRename: () {},
            onCopy: () {},
            onCut: () {},
            onExport: () {},
            onCompressSelection: () {},
            onExtractSelectedArchive: () {},
            onDelete: () {},
            onOpenWithApp: () {},
            onShare: () {},
            showPinOption: false,
            showUnpinOption: false,
            onPin: () {},
            onUnpin: () {},
            showBookmarkOption: false,
            showUnbookmarkOption: false,
            onBookmark: () {},
            onUnbookmark: () {},
            showEncryptOption: false,
            showDecryptOption: false,
            onEncrypt: () {},
            onDecrypt: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the overflow menu
      final moreButton = find.byIcon(Icons.more_vert_rounded);
      expect(moreButton, findsOneWidget);
      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      // Edit video option should be present with content_cut icon
      final editVideoFinder = find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'edit_video',
      );
      expect(editVideoFinder, findsOneWidget);
      expect(
        find.descendant(of: editVideoFinder, matching: find.byIcon(Icons.content_cut_rounded)),
        findsOneWidget,
      );

      // Tap Edit video
      await tester.tap(editVideoFinder);
      await tester.pumpAndSettle();

      expect(editedVideo, isTrue);
    });

    testWidgets('does not show Edit video in overflow menu when showEditVideoOption is false', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          SelectionAppBar(
            selectedCount: 1,
            selectionLabel: '15 MB',
            singleSelected: true,
            singleFileSelected: true,
            showEditVideoOption: false,
            onEditVideo: () {},
            showEditImageOption: false,
            onEditImage: () {},
            onClose: () {},
            onSelectAll: () {},
            onRename: () {},
            onCopy: () {},
            onCut: () {},
            onExport: () {},
            onCompressSelection: () {},
            onExtractSelectedArchive: () {},
            onDelete: () {},
            onOpenWithApp: () {},
            onShare: () {},
            showPinOption: false,
            showUnpinOption: false,
            onPin: () {},
            onUnpin: () {},
            showBookmarkOption: false,
            showUnbookmarkOption: false,
            onBookmark: () {},
            onUnbookmark: () {},
            showEncryptOption: false,
            showDecryptOption: false,
            onEncrypt: () {},
            onDecrypt: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final moreButton = find.byIcon(Icons.more_vert_rounded);
      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      final editVideoFinder = find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'edit_video',
      );
      expect(editVideoFinder, findsNothing);
    });

    testWidgets('disables Edit video when readOnly is true', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          SelectionAppBar(
            selectedCount: 1,
            selectionLabel: '15 MB',
            singleSelected: true,
            singleFileSelected: true,
            readOnly: true,
            showEditVideoOption: true,
            onEditVideo: () {},
            showEditImageOption: false,
            onEditImage: () {},
            onClose: () {},
            onSelectAll: () {},
            onRename: () {},
            onCopy: () {},
            onCut: () {},
            onExport: () {},
            onCompressSelection: () {},
            onExtractSelectedArchive: () {},
            onDelete: () {},
            onOpenWithApp: () {},
            onShare: () {},
            showPinOption: false,
            showUnpinOption: false,
            onPin: () {},
            onUnpin: () {},
            showBookmarkOption: false,
            showUnbookmarkOption: false,
            onBookmark: () {},
            onUnbookmark: () {},
            showEncryptOption: false,
            showDecryptOption: false,
            onEncrypt: () {},
            onDecrypt: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final moreButton = find.byIcon(Icons.more_vert_rounded);
      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      final editVideoItem = tester.widget<PopupMenuItem<String>>(
        find.byWidgetPredicate(
          (widget) => widget is PopupMenuItem<String> && widget.value == 'edit_video',
        ),
      );
      expect(editVideoItem.enabled, isFalse);
    });
  });

  group('SelectionAppBarWide - video editor option', () {
    testWidgets('shows Edit video in overflow menu when showEditVideoOption is true', (tester) async {
      bool editedVideo = false;

      await tester.pumpWidget(
        _buildTestApp(
          SelectionAppBarWide(
            selectedCount: 1,
            selectionLabel: '15 MB',
            singleFileSelected: true,
            singleFolderSelected: false,
            singleArchiveSelected: false,
            folderDocumentProviderMounted: false,
            readOnly: false,
            showPinOption: false,
            showUnpinOption: false,
            showBookmarkOption: false,
            showUnbookmarkOption: false,
            showEncryptOption: false,
            showDecryptOption: false,
            showActionBar: false,
            visibleActions: const [],
            actionBuilders: const {},
            showEditVideoOption: true,
            onEditVideo: () => editedVideo = true,
            showEditImageOption: false,
            onEditImage: () {},
            onClose: () {},
            onSelectAll: () {},
            onRename: () {},
            onCopy: () {},
            onCut: () {},
            onExport: () {},
            onCompressSelection: () {},
            onExtractSelectedArchive: () {},
            onDelete: () {},
            onOpenWithApp: () {},
            onShare: () {},
            onToggleDocumentProvider: () {},
            onPin: () {},
            onUnpin: () {},
            onBookmark: () {},
            onUnbookmark: () {},
            onEncrypt: () {},
            onDecrypt: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final moreButton = find.byIcon(Icons.more_vert_rounded);
      expect(moreButton, findsOneWidget);
      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      final editVideoFinder = find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'edit_video',
      );
      expect(editVideoFinder, findsOneWidget);
      expect(
        find.descendant(of: editVideoFinder, matching: find.byIcon(Icons.content_cut_rounded)),
        findsOneWidget,
      );

      await tester.tap(editVideoFinder);
      await tester.pumpAndSettle();

      expect(editedVideo, isTrue);
    });

    testWidgets('does not show Edit video in overflow menu when showEditVideoOption is false', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          SelectionAppBarWide(
            selectedCount: 1,
            selectionLabel: '15 MB',
            singleFileSelected: true,
            singleFolderSelected: false,
            singleArchiveSelected: false,
            folderDocumentProviderMounted: false,
            readOnly: false,
            showPinOption: false,
            showUnpinOption: false,
            showBookmarkOption: false,
            showUnbookmarkOption: false,
            showEncryptOption: false,
            showDecryptOption: false,
            showActionBar: false,
            visibleActions: const [],
            actionBuilders: const {},
            showEditVideoOption: false,
            onEditVideo: () {},
            showEditImageOption: false,
            onEditImage: () {},
            onClose: () {},
            onSelectAll: () {},
            onRename: () {},
            onCopy: () {},
            onCut: () {},
            onExport: () {},
            onCompressSelection: () {},
            onExtractSelectedArchive: () {},
            onDelete: () {},
            onOpenWithApp: () {},
            onShare: () {},
            onToggleDocumentProvider: () {},
            onPin: () {},
            onUnpin: () {},
            onBookmark: () {},
            onUnbookmark: () {},
            onEncrypt: () {},
            onDecrypt: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final moreButton = find.byIcon(Icons.more_vert_rounded);
      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      final editVideoFinder = find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'edit_video',
      );
      expect(editVideoFinder, findsNothing);
    });
  });

  group('Selection menu entries that depend on a callback', () {
    Widget narrowBar({
      VoidCallback? onGoToLocation,
      VoidCallback? onCopyPath,
    }) => _buildTestApp(
      SelectionAppBar(
        selectedCount: 1,
        selectionLabel: '15 MB',
        singleSelected: true,
        singleFileSelected: true,
        onGoToLocation: onGoToLocation,
        onCopyPath: onCopyPath,
        onEditVideo: () {},
        onEditImage: () {},
        onClose: () {},
        onSelectAll: () {},
        onRename: () {},
        onCopy: () {},
        onCut: () {},
        onExport: () {},
        onCompressSelection: () {},
        onExtractSelectedArchive: () {},
        onDelete: () {},
        onOpenWithApp: () {},
        onShare: () {},
        showPinOption: false,
        showUnpinOption: false,
        onPin: () {},
        onUnpin: () {},
        showBookmarkOption: false,
        showUnbookmarkOption: false,
        onBookmark: () {},
        onUnbookmark: () {},
        showEncryptOption: false,
        showDecryptOption: false,
        onEncrypt: () {},
        onDecrypt: () {},
      ),
    );

    Widget wideBar({
      VoidCallback? onGoToLocation,
      VoidCallback? onCopyPath,
    }) => _buildTestApp(
      SelectionAppBarWide(
        selectedCount: 1,
        selectionLabel: '15 MB',
        singleFileSelected: true,
        singleFolderSelected: false,
        singleArchiveSelected: false,
        folderDocumentProviderMounted: false,
        readOnly: false,
        showPinOption: false,
        showUnpinOption: false,
        showBookmarkOption: false,
        showUnbookmarkOption: false,
        showEncryptOption: false,
        showDecryptOption: false,
        showActionBar: false,
        visibleActions: const [],
        actionBuilders: const {},
        onGoToLocation: onGoToLocation,
        onCopyPath: onCopyPath,
        onEditVideo: () {},
        onEditImage: () {},
        onClose: () {},
        onSelectAll: () {},
        onRename: () {},
        onCopy: () {},
        onCut: () {},
        onExport: () {},
        onCompressSelection: () {},
        onExtractSelectedArchive: () {},
        onDelete: () {},
        onOpenWithApp: () {},
        onShare: () {},
        onToggleDocumentProvider: () {},
        onPin: () {},
        onUnpin: () {},
        onBookmark: () {},
        onUnbookmark: () {},
        onEncrypt: () {},
        onDecrypt: () {},
      ),
    );

    final bars =
        <
          String,
          Widget Function({VoidCallback? onGoToLocation, VoidCallback? onCopyPath})
        >{'SelectionAppBar': narrowBar, 'SelectionAppBarWide': wideBar};

    // (menu value, label, icon, builds the bar with only that callback set)
    final entries =
        <(String, String, IconData, Widget Function(Widget Function({VoidCallback? onGoToLocation, VoidCallback? onCopyPath}), VoidCallback?))>[
          (
            'go_to_location',
            'Go to location',
            Icons.folder_open_rounded,
            (bar, cb) => bar(onGoToLocation: cb),
          ),
          (
            'copy_path',
            'Copy path',
            Icons.link_rounded,
            (bar, cb) => bar(onCopyPath: cb),
          ),
        ];

    for (final bar in bars.entries) {
      for (final (value, label, icon, build) in entries) {
        final finder = find.byWidgetPredicate(
          (widget) => widget is PopupMenuItem<String> && widget.value == value,
        );

        testWidgets('${bar.key} offers "$label" and runs its callback when set', (
          tester,
        ) async {
          var ran = false;
          await tester.pumpWidget(build(bar.value, () => ran = true));
          await tester.pumpAndSettle();

          await tester.tap(find.byIcon(Icons.more_vert_rounded));
          await tester.pumpAndSettle();

          expect(finder, findsOneWidget);
          expect(
            find.descendant(of: finder, matching: find.byIcon(icon)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: finder, matching: find.text(label)),
            findsOneWidget,
          );

          await tester.tap(finder);
          await tester.pumpAndSettle();
          expect(ran, isTrue);
        });

        testWidgets('${bar.key} does not offer "$label" without a callback', (
          tester,
        ) async {
          await tester.pumpWidget(build(bar.value, null));
          await tester.pumpAndSettle();

          await tester.tap(find.byIcon(Icons.more_vert_rounded));
          await tester.pumpAndSettle();

          expect(finder, findsNothing);
        });
      }
    }
  });
}
