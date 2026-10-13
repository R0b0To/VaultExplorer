import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_in_place_layout_editor.dart';

Widget _buildTestApp({
  required MediaViewerToolbarConfig toolbarConfig,
  required ValueChanged<MediaViewerToolbarConfig> onConfigChanged,
  VoidCallback? onDone,
  VoidCallback? onOpenSettings,
  VoidCallback? onResetToDefaults,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MediaViewerInPlaceLayoutEditor(
        toolbarConfig: toolbarConfig,
        isImage: false,
        isAudio: false,
        isPlaylistMode: true,
        onConfigChanged: onConfigChanged,
        onDone: onDone ?? () {},
        onOpenSettings: onOpenSettings ?? () {},
        onResetToDefaults: onResetToDefaults ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('renders Top Dock, Bottom Dock, and Panel with tabs',
      (tester) async {
    const config = MediaViewerToolbarConfig(
      topBarActions: [MediaViewerAction.bookmark],
      bottomBarActions: [MediaViewerAction.playPause, MediaViewerAction.mute],
      moreMenuActions: [MediaViewerAction.fileInfo, MediaViewerAction.editVideo],
      advancedSettingsActions: [MediaViewerAction.rotate90],
      hiddenActions: {MediaViewerAction.decoder},
    );

    await tester.pumpWidget(
      _buildTestApp(
        toolbarConfig: config,
        onConfigChanged: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Top Bar'), findsOneWidget);
    expect(find.textContaining('Bottom Dock'), findsOneWidget);

    // Tabs in panel
    expect(find.text('More Menu'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
  });

  testWidgets('tapping dock action opens menu to move or hide action',
      (tester) async {
    const config = MediaViewerToolbarConfig(
      topBarActions: [MediaViewerAction.bookmark],
      bottomBarActions: [MediaViewerAction.playPause],
    );

    MediaViewerToolbarConfig? updated;

    await tester.pumpWidget(
      _buildTestApp(
        toolbarConfig: config,
        onConfigChanged: (cfg) => updated = cfg,
      ),
    );
    await tester.pumpAndSettle();

    // Tap bookmark in Top Dock
    final bookmarkItem = find.byTooltip('Bookmark');
    expect(bookmarkItem, findsOneWidget);

    await tester.tap(bookmarkItem);
    await tester.pumpAndSettle();

    // Menu options
    expect(find.text('Add to Bottom Dock'), findsOneWidget);
    expect(find.text('Hide Action'), findsOneWidget);

    // Choose Hide Action
    await tester.tap(find.text('Hide Action'));
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(updated!.topBarActions.contains(MediaViewerAction.bookmark), isFalse);
    expect(updated!.hiddenActions.contains(MediaViewerAction.bookmark), isTrue);
  });

  testWidgets('switches between More, Advanced, and Hidden tabs in panel',
      (tester) async {
    const config = MediaViewerToolbarConfig(
      topBarActions: [MediaViewerAction.bookmark],
      bottomBarActions: [MediaViewerAction.playPause],
      moreMenuActions: [MediaViewerAction.fileInfo],
      advancedSettingsActions: [MediaViewerAction.rotate90],
      hiddenActions: {MediaViewerAction.decoder},
    );

    await tester.pumpWidget(
      _buildTestApp(
        toolbarConfig: config,
        onConfigChanged: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    // Initially on More Menu tab -> fileInfo should be visible
    expect(find.text('File info'), findsOneWidget);
    expect(find.text('Rotate 90°'), findsNothing);

    // Switch to Advanced tab
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    expect(find.text('Rotate 90°'), findsOneWidget);
    expect(find.text('File info'), findsNothing);

    // Switch to Hidden tab
    await tester.tap(find.text('Hidden'));
    await tester.pumpAndSettle();

    expect(find.text('Video decoder'), findsOneWidget);
  });
}