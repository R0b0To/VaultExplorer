import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_content_view.dart';

export 'controllers/file_browser_navigation_controller.dart' show PathSegment;
export 'widgets/directory_content_view.dart' show DirectoryContentView;

/// Standalone entry point for decoy and other routes without BrowserTabsHost.
/// This wrapper owns the standalone Scaffold and hosts a chrome-free viewport.
class FileBrowserScreen extends StatefulWidget {
  final MountedContainer container;
  final MountedContainer? Function(int volId)? resolveContainer;
  final ThumbnailCacheMode? thumbnailCacheMode;
  final ThumbnailQuality? thumbnailQuality;
  final VoidCallback? onUserActivity;
  final bool showBackButton;
  final Widget Function(Widget title)? wrapAppBarTitle;
  final VoidCallback? onOpenStorageSwitcher;
  final Widget? drawer;
  final ValueChanged<bool>? onDrawerChanged;
  final String? initialPath;

  const FileBrowserScreen({
    super.key,
    required this.container,
    this.thumbnailCacheMode,
    this.thumbnailQuality,
    this.onUserActivity,
    this.resolveContainer,
    this.showBackButton = true,
    this.wrapAppBarTitle,
    this.onOpenStorageSwitcher,
    this.drawer,
    this.onDrawerChanged,
    this.initialPath,
  });

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final ValueNotifier<PreferredSizeWidget?> _appBar = ValueNotifier(null);
  final ValueNotifier<Widget?> _floatingAction = ValueNotifier(null);
  final ValueNotifier<Widget?> _bottomBar = ValueNotifier(null);

  @override
  void dispose() {
    _appBar.dispose();
    _floatingAction.dispose();
    _bottomBar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = Scaffold(
      appBar: _StandaloneBrowserAppBar(
        appBarListenable: _appBar,
        fallback: const SizedBox(height: kToolbarHeight),
      ),
      body: DirectoryContentView(
        container: widget.container,
        thumbnailCacheMode: widget.thumbnailCacheMode,
        thumbnailQuality: widget.thumbnailQuality,
        onUserActivity: widget.onUserActivity,
        resolveContainer: widget.resolveContainer,
        showBackButton: widget.showBackButton,
        wrapAppBarTitle: widget.wrapAppBarTitle,
        onOpenStorageSwitcher: widget.onOpenStorageSwitcher,
        initialPath: widget.initialPath,
        onAppBarChanged: (appBar) => _appBar.value = appBar,
        onFloatingActionChanged: (action) => _floatingAction.value = action,
        onBottomBarChanged: (bottomBar) => _bottomBar.value = bottomBar,
      ),
      floatingActionButton: ValueListenableBuilder<Widget?>(
        valueListenable: _floatingAction,
        builder: (context, action, _) => action ?? const SizedBox.shrink(),
      ),
      bottomNavigationBar: ValueListenableBuilder<Widget?>(
        valueListenable: _bottomBar,
        builder: (context, bottomBar, _) =>
            bottomBar ?? const SizedBox.shrink(),
      ),
    );
    if (widget.drawer == null) return screen;
    return FullScreenDragDrawer(
      drawer: widget.drawer,
      onDrawerChanged: widget.onDrawerChanged,
      child: screen,
    );
  }
}

class _StandaloneBrowserAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _StandaloneBrowserAppBar({
    required this.appBarListenable,
    required this.fallback,
  });

  final ValueListenable<PreferredSizeWidget?> appBarListenable;
  final Widget fallback;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: kToolbarHeight,
    child: ValueListenableBuilder<PreferredSizeWidget?>(
      valueListenable: appBarListenable,
      builder: (context, appBar, _) => appBar ?? fallback,
    ),
  );
}
