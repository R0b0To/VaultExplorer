import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_sheet.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';

class AppNavigationDrawer extends ConsumerWidget {
  final int? currentVolId;
  final MountedContainer? primaryLocalContainer;
  final int selectedTabIndex;
  final ValueChanged<int>? onSelectTab;
  final ValueChanged<MountedContainer>? onSelectContainer;
  final ValueChanged<VaultListItem>? onUnlockVault;
  final ValueChanged<VaultListItem>? onEditVault;
  final ValueChanged<VaultListItem>? onDeleteVault;
  final VoidCallback? onAddVault;

  const AppNavigationDrawer({
    super.key,
    this.currentVolId,
    this.primaryLocalContainer,
    this.selectedTabIndex = 0,
    this.onSelectTab,
    this.onSelectContainer,
    this.onUnlockVault,
    this.onEditVault,
    this.onDeleteVault,
    this.onAddVault,
  });

  void _navigateToTab(BuildContext context, int tabIndex) {
    Navigator.pop(context); // Close drawer
    // If inside a vault/storage browser, pop it to return to MainShell
    if (currentVolId != null && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    onSelectTab?.call(tabIndex);
  }

  void _promptRename(BuildContext context, WidgetRef ref, ExternalStorageLocation loc) {
    final ctrl = TextEditingController(text: loc.displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.renameStorageLocationTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.displayNameTitle),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isNotEmpty) {
                ref.read(externalStorageLocationsProvider.notifier).renameLocation(loc.id, text);
              }
              Navigator.pop(ctx);
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }

 void _confirmRemove(BuildContext context, WidgetRef ref, ExternalStorageLocation loc) {
    final isCurrent = currentVolId != null && currentVolId == loc.volId;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.removeStorageLocationTitle),
        content: Text(context.l10n.removeStorageLocationConfirm(loc.displayName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(externalStorageLocationsProvider.notifier).removeLocation(loc.id);
              if (isCurrent && context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
                onSelectTab?.call(0);
              }
            },
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
  }

 IconData _iconForStorage(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('cloud') || lower.contains('drive') || lower.contains('nextcloud') || lower.contains('owncloud')) {
      return Icons.cloud_outlined;
    }
    if (lower.contains('primary') || lower.contains('emulated')) {
      return Icons.folder_special_rounded;
    }
    return Icons.sd_card_rounded;
  }

  void _showLocationContextMenu(BuildContext context, WidgetRef ref, ExternalStorageLocation loc, Offset tapPosition) {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20, color: cs.onSurface),
              const SizedBox(width: 12),
              Text(context.l10n.rename),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: cs.error),
              const SizedBox(width: 12),
              Text(context.l10n.remove, style: TextStyle(color: cs.error)),
            ],
          ),
        ),
      ],
    ).then((action) {
      if (action == 'rename') {
        _promptRename(context, ref, loc);
      } else if (action == 'remove') {
        _confirmRemove(context, ref, loc);
      }
    });
  }

  Future<void> _lockSingleVault(BuildContext context, WidgetRef ref, MountedContainer container) async {
    try {
      await ref.read(vaultLifecycleApiProvider).lockContainer(container.uri);
      VeLog.i('AppNavigationDrawer', '_lockSingleVault: native lockContainer succeeded for volId=${container.volId}');
      ref.read(vaultDashboardControllerProvider.notifier).onContainerLocked(container.volId);
    } catch (e) {
      VeLog.e('AppNavigationDrawer', '_lockSingleVault: native lockContainer threw for volId=${container.volId}', e);
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.lockFailedMessage(e.runtimeType.toString()),
          tone: AppBannerTone.warning,
        );
      }
    }
  }

  void _handleEditVault(BuildContext context, WidgetRef ref, VaultListItem item) {
    if (onEditVault != null) {
      onEditVault!(item);
      return;
    }
    final state = ref.read(vaultDashboardControllerProvider);
    final existing = state.records[item.uri];
    MountedContainer? mountedC;
    for (final m in state.mounted) {
      if (m.uri == item.uri) {
        mountedC = m;
        break;
      }
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContainerConfigScreen(
          uri: item.uri,
          currentLabel: item.name,
          existingRecord: existing,
          appSettings: state.appSettings,
          mountedContainer: mountedC,
          onSaved: (record) =>
              ref.read(vaultDashboardControllerProvider.notifier).updateContainerRecord(item.uri, record),
        ),
      ),
    );
  }

  void _handleDeleteVault(BuildContext context, WidgetRef ref, VaultListItem item) {
    if (onDeleteVault != null) {
      onDeleteVault!(item);
      return;
    }
    if (item.isMounted) {
      showAppSnackBar(
        context,
        message: context.l10n.lockBeforeRemovingWarning,
        tone: AppBannerTone.warning,
      );
      return;
    }
    ref.read(vaultDashboardControllerProvider.notifier).handleSwipeToRemove(
          item.uri,
          (item as LockedVaultItem).record,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dashboardState = ref.watch(vaultDashboardControllerProvider);
    final displayItems = ref.read(vaultDashboardControllerProvider.notifier).getDisplayItems();
    final externalStorages = ref.watch(externalStorageLocationsProvider);
    final showStorageLocations = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.showStorageLocationsInDrawer),
    );
    final primary = primaryLocalContainer;

    final isDashboard = currentVolId == null && selectedTabIndex == 0;
    final isTools = currentVolId == null && selectedTabIndex == 1;
    final isSettings = currentVolId == null && selectedTabIndex == 2;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  // 1. Dashboard (Home)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    selected: isDashboard,
                    selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                    leading: Icon(
                      Icons.dashboard_rounded,
                      color: isDashboard ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(
                      context.l10n.dashboardNavLabel,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: isDashboard ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    onTap: () => _navigateToTab(context, 0),
                  ),

                          // 2. Encrypted Vaults Section (Swipeable Rows with Lock Button)
                          if (displayItems.isNotEmpty || onAddVault != null) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
                              child: Row(
                                children: [
                                  Text(
                                    context.l10n.vaultsSectionTitle.toUpperCase(),
                                    style: textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (dashboardState.mounted.isNotEmpty)
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: cs.error,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(Icons.lock_rounded, size: 14),
                                      label: Text(
                                        context.l10n.lockAllVaultsTitle,
                                        style: textTheme.labelSmall?.copyWith(
                                          color: cs.error,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onPressed: () {
                                        // Only close the drawer if the vault currently being
                                        // browsed is one of the ones about to be locked -- that
                                        // screen will pop itself in response, and closing the
                                        // drawer first keeps that pop from being swallowed by
                                        // the drawer's own local history entry. Otherwise (e.g.
                                        // locking from the Dashboard, or locking vaults other
                                        // than the one on screen) the drawer should stay open so
                                        // the list can simply refresh to show them as locked.
                                        final willLeaveCurrentScreen = currentVolId != null &&
                                            dashboardState.mounted.any((c) => c.volId == currentVolId);
                                        if (willLeaveCurrentScreen) {
                                          Navigator.pop(context);
                                        }
                                        for (final c in dashboardState.mounted) {
                                          ref.read(vaultLifecycleApiProvider).lockContainer(c.uri);
                                          ref.read(vaultDashboardControllerProvider.notifier).onContainerLocked(c.volId);
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                            for (final item in displayItems) ...[
                              (() {
                                final isMounted = item.isMounted;
                                final volId = item is MountedVaultItem ? item.container.volId : null;
                                final isCurrent = volId != null && volId == currentVolId;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: _DrawerVaultRow(
                                    key: ValueKey('drawer_vault_${item.uri}'),
                                    item: item,
                                    isCurrent: isCurrent,
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (isCurrent) return;
                                      if (item is MountedVaultItem) {
                                        onSelectContainer?.call(item.container);
                                      } else {
                                        if (currentVolId != null && Navigator.of(context).canPop()) {
                                          Navigator.of(context).pop();
                                        }
                                        onSelectTab?.call(0);
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          onUnlockVault?.call(item);
                                        });
                                      }
                                    },
                                    onLock: isMounted
                                        ? () async {
                                            final container = (item as MountedVaultItem).container;
                                            if (isCurrent) {
                                              Navigator.pop(context);
                                            }
                                            await _lockSingleVault(context, ref, container);
                                          }
                                        : null,
                                    onEdit: () {
                                      Navigator.pop(context);
                                      _handleEditVault(context, ref, item);
                                    },
                                    onDelete: () {
                                      Navigator.pop(context);
                                      _handleDeleteVault(context, ref, item);
                                    },
                                  ),
                                );
                              })(),
                            ],
                            if (onAddVault != null)
                              ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                leading: Icon(Icons.add, color: cs.primary),
                                title: Text(
                                  context.l10n.addAVaultTitle,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  if (currentVolId != null && Navigator.of(context).canPop()) {
                                    Navigator.of(context).pop();
                                  }
                                  onSelectTab?.call(0);
                                  onAddVault!();
                                },
                              ),
                          ],

                           const Padding(
                            padding: EdgeInsets.symmetric(vertical: 1),
                            child: Divider(),
                          ),

                          if (showStorageLocations) ...[
                              if (primary != null)
                              ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                selected: currentVolId == kDecoyLocalVolId,
                                selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                                leading: Icon(
                                  Icons.phone_android_rounded,
                                  color: currentVolId == kDecoyLocalVolId ? cs.primary : cs.onSurfaceVariant,
                                ),
                                title: Text(
                                  context.l10n.localStorageCardTitle,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: currentVolId == kDecoyLocalVolId ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  if (currentVolId == kDecoyLocalVolId) return;
                                  onSelectContainer?.call(primary);
                                },
                              ),

                            for (final loc in externalStorages) ...[
                              Builder(
                                builder: (tileContext) {
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onSecondaryTapDown: (details) =>
                                        _showLocationContextMenu(context, ref, loc, details.globalPosition),
                                    child: ListTile(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                      selected: currentVolId == loc.volId,
                                      selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                                      leading: Icon(
                                        _iconForStorage(loc.path),
                                        color: currentVolId == loc.volId ? cs.primary : cs.secondary,
                                      ),
                                      title: Text(
                                        loc.displayName,
                                        style: textTheme.bodyMedium?.copyWith(
                                          fontWeight: currentVolId == loc.volId ? FontWeight.bold : FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onLongPress: () {
                                        final box = tileContext.findRenderObject() as RenderBox?;
                                        final pos = box != null
                                            ? box.localToGlobal(box.size.center(Offset.zero))
                                            : Offset.zero;
                                        _showLocationContextMenu(context, ref, loc, pos);
                                      },
                                  onTap: () async {
                                        if (currentVolId == loc.volId) {
                                          Navigator.pop(context);
                                          return;
                                        }
                                        final isAccessible = await ref
                                            .read(externalStorageLocationsProvider.notifier)
                                            .isAccessible(loc);
                                        if (!context.mounted) return;
                                        if (!isAccessible) {
                                          Navigator.pop(context);
                                          showAppSnackBar(
                                            context,
                                            message: context.l10n.storageLocationUnavailable(loc.displayName),
                                            tone: AppBannerTone.warning,
                                          );
                                          return;
                                        }
                                        Navigator.pop(context);
                                        onSelectContainer?.call(buildExternalStorageContainer(
                                          rootPath: loc.resolvedUri,
                                          displayName: loc.displayName,
                                          volId: loc.volId,
                                        ));
                                      },
                                    ),
                                  );
                                },
                              ),
                            ],

                            ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                              leading: Icon(Icons.add, color: cs.primary),
                              title: Text(
                                context.l10n.addStorageLocationTitle,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                           onTap: () async {
                                final notifier = ref.read(externalStorageLocationsProvider.notifier);
                                final loc = await ref.read(sessionLockControllerProvider).withLockSuppression(
                                  () => notifier.promptAndAddLocation(),
                                );
                                if (!context.mounted) return;
                                if (loc != null) {
                                  Navigator.pop(context);
                                  onSelectContainer?.call(buildExternalStorageContainer(
                                    rootPath: loc.resolvedUri,
                                    displayName: loc.displayName,
                                    volId: loc.volId,
                                  ));
                                }
                              },
                            ),
                          ],

                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 1),
                            child: Divider(),
                          ),

                           // 4. Tools Destination
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    selected: isTools,
                    selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                    leading: Icon(
                      Icons.build_rounded,
                      color: isTools ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(
                      context.l10n.navBarToolsLabel,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: isTools ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ToolsScreen(
                            mountedContainers: ValueNotifier(dashboardState.mounted),
                          ),
                        ),
                      );
                    },
                  ),

                  // 5A. File Manager Settings
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    leading: Icon(Icons.tune_rounded, color: cs.onSurfaceVariant),
                    title: Text(context.l10n.fileManagerSettingsTitle),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FileManagerToolbarSettingsScreen(),
                        ),
                      );
                    },
                  ),

                  // 5B. App & Security Settings
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    selected: isSettings,
                    selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                    leading: Icon(
                      Icons.settings,
                      color: isSettings ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(
                      context.l10n.settingsMenuItem,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: isSettings ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AppSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerVaultRow extends StatelessWidget {
  final VaultListItem item;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onLock;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DrawerVaultRow({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onTap,
    required this.onLock,
    required this.onEdit,
    required this.onDelete,
  });

  void _showContextMenu(BuildContext context, Offset tapPosition) {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 20, color: cs.onSurface),
              const SizedBox(width: 12),
              Text(context.l10n.edit),
            ],
          ),
        ),
        if (onLock != null)
          PopupMenuItem(
            value: 'lock',
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 20, color: cs.onSurface),
                const SizedBox(width: 12),
                Text(context.l10n.lockVaultTooltip),
              ],
            ),
          )
        else
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded, size: 20, color: cs.error),
                const SizedBox(width: 12),
                Text(context.l10n.remove, style: TextStyle(color: cs.error)),
              ],
            ),
          ),
      ],
    ).then((action) {
      if (action == 'edit') onEdit();
      if (action == 'lock') onLock?.call();
      if (action == 'delete') onDelete();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMounted = item.isMounted;
    final isUsb = item.uri.startsWith('usb:');
    final format = switch (item) {
      MountedVaultItem(:final container) => container.format,
      LockedVaultItem(:final record) => record.format,
    };

    final tileColor = isCurrent
        ? Color.alphaBlend(cs.secondaryContainer.withValues(alpha: 0.6), cs.surfaceContainerHigh)
        : cs.surfaceContainerHigh;

    return Material(
      color: tileColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Builder(
        builder: (tileContext) {
          return ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            contentPadding: const EdgeInsets.only(left: 12, right: 6),
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isCurrent
                    ? cs.primaryContainer
                    : (isMounted ? cs.primaryContainer.withValues(alpha: 0.7) : cs.surfaceContainerHighest.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: isUsb
                  ? Icon(
                      Icons.usb_rounded,
                      size: 18,
                      color: isMounted ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    )
                  : ContainerFormatIcon(
                      format: format,
                      size: 18,
                      color: isMounted ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
            ),
            title: Text(
              item.name,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: isCurrent ? FontWeight.bold : (isMounted ? FontWeight.w600 : FontWeight.normal),
                color: isMounted ? cs.onSurface : cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: onLock != null
                ? IconButton(
                    icon: Icon(Icons.lock_outline_rounded, size: 20, color: cs.onSurfaceVariant),
                    tooltip: context.l10n.lockVaultTooltip,
                    visualDensity: VisualDensity.compact,
                    onPressed: onLock,
                  )
                : null,
            onLongPress: () {
              final box = tileContext.findRenderObject() as RenderBox?;
              final pos = box != null ? box.localToGlobal(box.size.center(Offset.zero)) : Offset.zero;
              _showContextMenu(context, pos);
            },
            onTap: onTap,
          );
        },
      ),
    );
  }
}