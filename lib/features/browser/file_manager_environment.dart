import 'dart:ui' show Size;

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
class FileManagerEnvironment {
  FileManagerEnvironment._();

  static final FileManagerEnvironment instance = FileManagerEnvironment._();

  MountedContainer? Function(int volId)? _resolveContainer;
  List<MountedContainer> Function()? _mountedContainers;
  MountedContainer? Function()? _primaryLocalContainer;
  bool Function(MountedContainer container, String? initialPath)? _openWindow;
  bool Function(String? title)? _openVaultsWindow;
  bool Function(BrowserTabState tab, String? initialPath, Size? windowSize)?
  _openTabWindow;

  void attach({
    required MountedContainer? Function(int volId) resolveContainer,
    required List<MountedContainer> Function() mountedContainers,
    required MountedContainer? Function() primaryLocalContainer,
    required bool Function(MountedContainer container, String? initialPath)
    openWindow,
    required bool Function(String? title) openVaultsWindow,
    bool Function(BrowserTabState tab, String? initialPath, Size? windowSize)?
    openTabWindow,
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

  /// Opens [tab]'s location in a new window, for a tab that was dragged out of
  /// its window. [initialPath] is where in its container the tab is (null for
  /// the root, and for tabs that are not folders), and [windowSize] the size
  /// of the window it came from, which the new one takes so that it looks like
  /// the same window. The window appears under the mouse cursor where the
  /// platform lets the app place it.
  ///
  /// Moving the tab is up to the caller: this only opens the window. Returns
  /// false when that is not possible, and then the tab should stay where it is.
  bool openTabWindow(
    BrowserTabState tab, {
    String? initialPath,
    Size? windowSize,
  }) => canOpenTabWindow && _openTabWindow!(tab, initialPath, windowSize);

  MountedContainer? resolveContainer(int volId) =>
      _resolveContainer?.call(volId);

  List<MountedContainer> mountedContainers() =>
      _mountedContainers?.call() ?? const <MountedContainer>[];

  MountedContainer? primaryLocalContainer() => _primaryLocalContainer?.call();
}
