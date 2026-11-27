import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/dashboard_layout_mode.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

/// The glyph of each dashboard layout, shared by the picker button, its menu
/// and the settings page.
extension DashboardLayoutModeIcon on DashboardLayoutMode {
  IconData get icon => switch (this) {
        DashboardLayoutMode.cards => Icons.view_agenda_outlined,
        DashboardLayoutMode.grid => Icons.grid_view_rounded,
        DashboardLayoutMode.list => Icons.view_list_rounded,
        DashboardLayoutMode.details => Icons.table_rows_outlined,
      };
}

List<Widget> buildDashboardLayoutMenuItems(
  BuildContext context,
  WidgetRef ref,
) {
  final current = ref.read(appSettingsControllerProvider).settings.dashboardLayoutMode;
  final cs = Theme.of(context).colorScheme;
  return [
    for (final mode in DashboardLayoutMode.values)
      MenuItemButton(
        leadingIcon: Icon(
          mode.icon,
          size: 20,
          color: mode == current ? cs.primary : cs.onSurfaceVariant,
        ),
        trailingIcon: mode == current
            ? Icon(Icons.check_rounded, size: 18, color: cs.primary)
            : null,
        onPressed: () => unawaited(
          ref
              .read(appSettingsControllerProvider.notifier)
              .updateSettings((s) => s.copyWith(dashboardLayoutMode: mode)),
        ),
        child: Text(
          mode.getLocalizedLabel(context.l10n),
          style: mode == current
              ? TextStyle(color: cs.primary, fontWeight: FontWeight.w600)
              : null,
        ),
      ),
  ];
}

/// The "View" button of the Vaults page: a menu to switch between cards, grid,
/// list and details, like the View menu of a file manager's drives page. Its
/// icon shows the layout in use. The choice is the app-wide
/// [AppSettings.dashboardLayoutMode].
class DashboardLayoutButton extends ConsumerWidget {
  const DashboardLayoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      appSettingsControllerProvider.select(
        (s) => s.settings.dashboardLayoutMode,
      ),
    );
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<DashboardLayoutMode>(
      icon: Icon(current.icon),
      tooltip: context.l10n.dashboardLayoutLabel,
      initialValue: current,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (mode) => unawaited(
        ref
            .read(appSettingsControllerProvider.notifier)
            .updateSettings((s) => s.copyWith(dashboardLayoutMode: mode)),
      ),
      itemBuilder: (ctx) => [
        for (final mode in DashboardLayoutMode.values)
          PopupMenuItem<DashboardLayoutMode>(
            value: mode,
            child: Row(
              children: [
                Icon(
                  mode.icon,
                  size: 20,
                  color: mode == current ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    mode.getLocalizedLabel(ctx.l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mode == current
                        ? TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
                ),
                if (mode == current) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.check_rounded, size: 18, color: cs.primary),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
