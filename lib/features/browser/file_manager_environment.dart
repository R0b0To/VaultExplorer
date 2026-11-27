import 'dart:ui' show Size, VoidCallback;

import 'package:vaultexplorer/core/windowing/desktop_windowing.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart'
    show BrowserTabState;

/// What a file manager window needs to know about the rest of the app, handed
/// over by the main shell.
///
/// The shell is the one place that can answer "which container has this
/// volume id?" and "where is this device's local storage?", because those
/// answers live in its widgets. A file manager window, which has no dashboard
/// of its own, asks through here instead. The shell [attach]es while it is on
/// screen (or `DesktopSessionKeeper`, when the main window has been closed and
/// file manager windows keep the app running); without either, every answer is
/// empty, which makes the window show what it was opened with and nothing more.
///
/// It is also how menus anywhere in the app ask for a location to be opened
/// in a new window ([canOpenWindow], [openWindow]), and how the tab strip hands
/// a tab that was dragged out of its window to a window of its own
/// ([canOpenTabWindow], [openTabWindow]), without importing the window itself.
/// A request for a window of its own for a tab that was dragged out of its
/// window (see [FileManagerEnvironment.openTabWindow]).
class TabWindowRequest {
  const TabWindowRequest({
    required this.tab,
    this.initialPath,
    this.windowSize,
    this.placeAtCursor = false,
    this.onFirstFrame,
  });

  final BrowserTabState tab;

  /// Where in its container the tab is (null for the root, and for tabs that
  /// are not folders).
  final String? initialPath;

  /// The size of the window the tab came from, which the new one takes so that
  /// it reads as the same window.
  final Size? windowSize;

  /// Put the window under the mouse cursor when it opens, where the platform
  /// lets the app do that. Not wanted by a drag that moves the window itself.
  final bool placeAtCursor;

  /// Called once the window has drawn its first frame: it is on screen from
  /// then on, and [OpenedTabWindow.tabLeft] is exact.
  final VoidCallback? onFirstFrame;
}

/// A window opened for a tab that was dragged out of its own.
class OpenedTabWindow {
  OpenedTabWindow({
    required this.viewId,
    required this.close,
    required this.tabLeft,
  });

  /// The window's view, which is how the platform runner knows it.
  final int viewId;

  /// Closes the window.
  final void Function() close;

  /// Where the window's first tab starts, in logical pixels from the left edge
  /// of its content: a guess until the window has been drawn, exact after.
  double tabLeft;
}

class FileManagerEnvironment {
  FileManagerEnvironment._();

  static final FileManagerEnvironment instance = FileManagerEnvironment._();

  MountedContainer? Function(int volId)? _resolveContainer;
  List<MountedContainer> Function()? _mountedContainers;
  MountedContainer? Function()? _primaryLocalContainer;
  bool Function(MountedContainer container, String? initialPath)? _openWindow;
  bool Function(String? title)? _openVaultsWindow;
  OpenedTabWindow? Function(TabWindowRequest request)? _openTabWindow;

  void attach({
    required MountedContainer? Function(int volId) resolveContainer,
    required List<MountedContainer> Function() mountedContainers,
    required MountedContainer? Function() primaryLocalContainer,
    required bool Function(MountedContainer container, String? initialPath)
    openWindow,
    required bool Function(String? title) openVaultsWindow,
    OpenedTabWindow? Function(TabWindowRequest request)? openTabWindow,
  }) {
    _resolveContainer = resolveContainer;
    _mountedContainers = mountedContainers;
    _primaryLocalContainer = primaryLocalContainer;
    _openWindow = openWindow;
    _openVaultsWindow = openVaultsWindow;
    _openTabWindow = openTabWindow;
  }

  void detach() {
    _resolveContainer = null;
    _mountedContainers = null;
    _primaryLocalContainer = null;
    _openWindow = null;
    _openVaultsWindow = null;
    _openTabWindow = null;
  }

  /// Whether "open in new window" should be offered: a desktop platform with
  /// native windows, and a main shell to hand the window its surroundings.
  bool get canOpenWindow =>
      _openWindow != null && DesktopWindowing.isSupportedPlatform;

  /// Opens [container] at [initialPath] in a new file manager window. Returns
  /// false when that is not possible, so the caller can open a tab instead.
  bool openWindow(MountedContainer container, {String? initialPath}) =>
      canOpenWindow && _openWindow!(container, initialPath);

  /// Opens the Vaults page (the dashboard) in a new window of its own, titled
  /// [title]. Returns false when that is not possible, so the caller can open
  /// a tab instead.
  bool openVaultsWindow({String? title}) =>
      canOpenWindow && (_openVaultsWindow?.call(title) ?? false);

  /// Whether a tab can be handed to a window of its own: the same conditions
  /// as [canOpenWindow], and a shell that knows how.
  bool get canOpenTabWindow =>
      _openTabWindow != null && DesktopWindowing.isSupportedPlatform;

  /// Opens a window for a tab that was dragged out of its own window, on the
  /// tab's location. Moving the tab is up to the caller: this only opens the
  /// window. Null when that is not possible, and then the tab should stay where
  /// it is.
  OpenedTabWindow? openTabWindow(TabWindowRequest request) =>
      canOpenTabWindow ? _openTabWindow!(request) : null;

  MountedContainer? resolveContainer(int volId) =>
      _resolveContainer?.call(volId);

  List<MountedContainer> mountedContainers() =>
      _mountedContainers?.call() ?? const <MountedContainer>[];

  MountedContainer? primaryLocalContainer() => _primaryLocalContainer?.call();
}
