import 'package:vaultexplorer/core/windowing/desktop_windowing.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// What a file manager window needs to know about the rest of the app, handed
/// over by the main shell.
///
/// The shell is the one place that can answer "which container has this
/// volume id?" and "where is this device's local storage?", because those
/// answers live in its widgets. A file manager window, which has no dashboard
/// of its own, asks through here instead. The shell [attach]es while it is on
/// screen; without it every answer is empty, which makes the window show what
/// it was opened with and nothing more.
///
/// It is also how menus anywhere in the app ask for a location to be opened
/// in a new window ([canOpenWindow], [openWindow]) without importing the
/// window itself.
class FileManagerEnvironment {
  FileManagerEnvironment._();

  static final FileManagerEnvironment instance = FileManagerEnvironment._();

  MountedContainer? Function(int volId)? _resolveContainer;
  List<MountedContainer> Function()? _mountedContainers;
  MountedContainer? Function()? _primaryLocalContainer;
  bool Function(MountedContainer container, String? initialPath)? _openWindow;
  bool Function(String? title)? _openVaultsWindow;

  void attach({
    required MountedContainer? Function(int volId) resolveContainer,
    required List<MountedContainer> Function() mountedContainers,
    required MountedContainer? Function() primaryLocalContainer,
    required bool Function(MountedContainer container, String? initialPath)
    openWindow,
    required bool Function(String? title) openVaultsWindow,
  }) {
    _resolveContainer = resolveContainer;
    _mountedContainers = mountedContainers;
    _primaryLocalContainer = primaryLocalContainer;
    _openWindow = openWindow;
    _openVaultsWindow = openVaultsWindow;
  }

  void detach() {
    _resolveContainer = null;
    _mountedContainers = null;
    _primaryLocalContainer = null;
    _openWindow = null;
    _openVaultsWindow = null;
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

  MountedContainer? resolveContainer(int volId) =>
      _resolveContainer?.call(volId);

  List<MountedContainer> mountedContainers() =>
      _mountedContainers?.call() ?? const <MountedContainer>[];

  MountedContainer? primaryLocalContainer() => _primaryLocalContainer?.call();
}
