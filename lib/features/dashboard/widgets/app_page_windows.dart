import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/file_manager_environment.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';

/// Opens the app's Tools page in a native window of its own (Linux and
/// Windows). Asking again brings the open window forward.
///
/// Returns false when native windows are not available (Android, a
/// `VE_MULTI_WINDOW=0` run, or an embedder that refused); the caller then
/// shows Tools the way it always has.
bool openToolsWindow(BuildContext context) {
  final title = context.l10n.navBarToolsLabel;
  return SecondaryWindows.instance.open(
    key: 'app:tools',
    title: title,
    size: const Size(1100, 760),
    constraints: const BoxConstraints(minWidth: 480, minHeight: 420),
    builder: (_) => const SkinAreaScope(
      area: SkinArea.tools,
      child: _ToolsWindowPage(),
    ),
  );
}

/// Opens the app's Settings page in a native window of its own (Linux and
/// Windows). Asking again brings the open window forward.
///
/// Returns false when native windows are not available; the caller then shows
/// Settings the way it always has.
bool openSettingsWindow(BuildContext context) {
  final title = context.l10n.settingsMenuItem;
  return SecondaryWindows.instance.open(
    key: 'app:settings',
    title: title,
    size: const Size(1000, 760),
    constraints: const BoxConstraints(minWidth: 480, minHeight: 420),
    builder: (_) => const SkinAreaScope(
      area: SkinArea.settings,
      child: AppSettingsScreen(),
    ),
  );
}

/// Tools inside its own window. The window outlives the page that opened it,
/// so it keeps its own view of the mounted vaults (kept current from the
/// dashboard controller) instead of a snapshot or the main shell's notifier.
class _ToolsWindowPage extends ConsumerStatefulWidget {
  const _ToolsWindowPage();

  @override
  ConsumerState<_ToolsWindowPage> createState() => _ToolsWindowPageState();
}

class _ToolsWindowPageState extends ConsumerState<_ToolsWindowPage> {
  late final ValueNotifier<List<MountedContainer>> _mounted = ValueNotifier(
    List.unmodifiable(ref.read(vaultDashboardControllerProvider).mounted),
  );
  late final ValueNotifier<MountedContainer?> _localStorage = ValueNotifier(
    FileManagerEnvironment.instance.primaryLocalContainer(),
  );

  @override
  void dispose() {
    _mounted.dispose();
    _localStorage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<MountedContainer>>(
      vaultDashboardControllerProvider.select((state) => state.mounted),
      (_, mounted) => _mounted.value = List.unmodifiable(mounted),
    );
    final env = FileManagerEnvironment.instance;
    return ToolsScreen(
      mountedContainers: _mounted,
      localStorageContainer: _localStorage,
      // "Show in file browser" opens a file manager window on the vault; it
      // is hidden when that is not possible.
      onOpenInBrowser: env.canOpenWindow
          ? (container) => env.openWindow(container)
          : null,
    );
  }
}
