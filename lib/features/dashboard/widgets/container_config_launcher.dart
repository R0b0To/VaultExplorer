import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/core/windowing/window_caption.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_sheet.dart';

/// Opens the settings of the vault [uri].
///
/// On Linux and Windows this is a native window of its own, centered over the
/// window it was opened from like the unlock window (on Windows; on Linux the
/// window manager places it). Opening the same vault's settings again brings
/// that window forward. Everywhere else, and wherever native windows turn out
/// to be unavailable, it is the full-screen page it has always been.
void openContainerConfig(
  BuildContext context, {
  required String uri,
  required String currentLabel,
}) {
  // The window outlives the page that asked for it, so nothing here may hold
  // on to this page's `ref`; the container is read directly instead.
  final providers = ProviderScope.containerOf(context, listen: false);
  final state = providers.read(vaultDashboardControllerProvider);
  final existing = state.records[uri];
  MountedContainer? mountedContainer;
  for (final m in state.mounted) {
    if (m.uri == uri) {
      mountedContainer = m;
      break;
    }
  }

  Widget buildScreen() => SkinAreaScope(
    area: SkinArea.dashboard,
    child: ContainerConfigScreen(
      uri: uri,
      currentLabel: currentLabel,
      existingRecord: existing,
      appSettings: state.appSettings,
      mountedContainer: mountedContainer,
      onSaved: (record) => providers
          .read(vaultDashboardControllerProvider.notifier)
          .updateContainerRecord(uri, record),
    ),
  );

  final l10n = context.l10n;
  // The window this was opened from: the new one is centered over it.
  final openedFrom = View.maybeOf(context)?.viewId;
  final baseTitle = uri.startsWith('usb:')
      ? l10n.usbVaultSettingsTitle
      : l10n.vaultSettingsTitle;
  final opened = SecondaryWindows.instance.open(
    key: 'config:$uri',
    title: currentLabel.isEmpty ? baseTitle : '$baseTitle – $currentLabel',
    builder: (_) => buildScreen(),
    onCreated: (entry) =>
        unawaited(centerWindowOver(entry.viewId, overViewId: openedFrom)),
  );
  if (opened) return;

  Navigator.push(context, MaterialPageRoute(builder: (_) => buildScreen()));
}
