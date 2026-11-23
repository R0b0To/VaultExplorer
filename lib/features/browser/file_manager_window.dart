import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/core/windowing/view_focus.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/browser_tabs_host.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/file_manager_environment.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

int _fileManagerWindowSerial = 0;

/// Opens [container] at [initialPath] in a new window of its own.
///
/// Each call opens another window, with its own tabs, its own location and
/// its own selection; the vaults, the clipboard, transfers and settings are
/// the app's, shared with every other window. Returns false when native
/// windows are not available, so the caller can open a tab instead. Menus go
/// through `FileManagerEnvironment.openWindow`, which ends up here.
bool openFileManagerWindow({
  required MountedContainer container,
  String? initialPath,
}) {
  return SecondaryWindows.instance.open(
    key: 'files:${++_fileManagerWindowSerial}',
    title: container.displayName,
    size: const Size(1100, 760),
    constraints: const BoxConstraints(minWidth: 560, minHeight: 400),
    builder: (_) =>
        FileManagerWindow(container: container, initialPath: initialPath),
  );
}

/// The content of a file manager window: the same tabbed file browser as the
/// main window, minus the dashboard and the sidebar, with a tab workspace of
/// its own.
///
/// Closing its last tab closes the window.
class FileManagerWindow extends ConsumerStatefulWidget {
  const FileManagerWindow({
    super.key,
    required this.container,
    this.initialPath,
  });

  final MountedContainer container;
  final String? initialPath;

  @override
  ConsumerState<FileManagerWindow> createState() => _FileManagerWindowState();
}

class _FileManagerWindowState extends ConsumerState<FileManagerWindow> {
  /// A workspace of its own: tabs are keyed by this, so nothing here is shared
  /// with the main window's tabs even though the providers are.
  late final BrowserTabsConfig _workspace = BrowserTabsConfig.create(
    initialContainer: widget.container,
    initialPath: widget.initialPath,
  );

  final FileManagerEnvironment _env = FileManagerEnvironment.instance;

  BrowserTabs get _actions =>
      ref.read(browserTabsProvider(_workspace).notifier);
  BrowserTabsState get _state => ref.read(browserTabsProvider(_workspace));
  bool get _tabsEnabled =>
      ref.read(appSettingsControllerProvider).settings.useBrowserTabs;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleShortcutKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleShortcutKey);
    super.dispose();
  }

  MountedContainer? _resolveContainer(int volId) {
    final resolved = _env.resolveContainer(volId);
    if (resolved != null) return resolved;
    return volId == widget.container.volId ? widget.container : null;
  }

  /// Ctrl+W and Ctrl+Tab, as in the main window. They are global key
  /// handlers, so they only answer while this window holds the focus.
  bool _handleShortcutKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    if (!keyboardFocusIsInViewOf(context)) return false;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    if (keyboard.isControlPressed && !keyboard.isAltPressed) {
      if (key == LogicalKeyboardKey.keyW) {
        _closeActiveTab();
        return true;
      }
    }
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.tab) {
      if (!_tabsEnabled) return false;
      _cycleTab(keyboard.isShiftPressed ? -1 : 1);
      return true;
    }
    return false;
  }

  void _closeActiveTab() {
    final state = _state;
    final activeTabId = state.activeTabId;
    if (!_tabsEnabled || state.tabs.length < 2 || activeTabId == null) {
      // The last tab goes with its window.
      SecondaryWindowScope.maybeOf(context)?.close();
      return;
    }
    _actions.closeTab(activeTabId);
  }

  void _cycleTab(int step) {
    final state = _state;
    if (state.tabs.length < 2 || state.activeIndex < 0) return;
    final count = state.tabs.length;
    _actions.activateIndex((state.activeIndex + step + count) % count);
  }

  /// Keeps the title bar showing where this window is, for the taskbar and
  /// the window switcher.
  void _syncTitle(WidgetRef ref, SecondaryWindowEntry? entry) {
    if (entry == null) return;
    final active = ref.watch(
      browserTabsProvider(_workspace).select((state) => state.activeTab),
    );
    final container = active?.container;
    if (active == null || container == null) return;
    final leaf = ref.watch(
      fileBrowserNavigationProvider(
        active.tabId,
      ).select((nav) => nav.pathStack.isEmpty ? '' : nav.pathStack.last.label),
    );
    final name = container.displayName;
    final title = leaf.isEmpty || leaf == name ? name : '$name – $leaf';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) entry.setTitle(title);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = SecondaryWindowScope.maybeOf(context);
    return Consumer(
      // The shell is passed as the child so that a title change only reruns
      // the builder below, not the whole file browser.
      child: SkinAreaScope(
        area: SkinArea.files,
        child: BrowserTabsShell(
          key: ValueKey<int>(_workspace.sessionId),
          restoredWorkspace: _workspace,
          resolveContainer: _resolveContainer,
          mountedContainers: _env.mountedContainers,
          primaryLocalContainer: _env.primaryLocalContainer,
          closeRouteWhenEmpty: false,
          onEmpty: entry?.close,
        ),
      ),
      builder: (context, ref, child) {
        _syncTitle(ref, entry);
        return child!;
      },
    );
  }
}
