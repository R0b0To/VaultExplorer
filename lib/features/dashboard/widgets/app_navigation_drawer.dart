import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/path_clipboard.dart';
import 'package:vaultexplorer/core/utils/storage_uri_path.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/widgets/file_name_label.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/drawer_bookmarks_section.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/settings/long_file_name_display_provider.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';

class AppNavigationDrawer extends ConsumerWidget {
  final int? currentVolId;
  final MountedContainer? primaryLocalContainer;
  final VoidCallback? onOpenLocalStorage;
  final int selectedTabIndex;
  final ValueChanged<int>? onSelectTab;
  final ValueChanged<MountedContainer>? onSelectContainer;
  final ValueChanged<VaultListItem>? onUnlockVault;
  final ValueChanged<VaultListItem>? onEditVault;
  final ValueChanged<VaultListItem>? onDeleteVault;
  final VoidCallback? onAddVault;

  /// Set only while the file manager is open with tabs: the long-press menus
  /// of vaults and storages then offer "Open in new tab".
  final ValueChanged<MountedContainer>? onOpenInNewTab;
  final bool keepBrowserTabsOnNavigate;

  const AppNavigationDrawer({
    super.key,
    this.currentVolId,
    this.primaryLocalContainer,
    this.onOpenLocalStorage,
    this.selectedTabIndex = 0,
    this.onSelectTab,
    this.onSelectContainer,
    this.onUnlockVault,
    this.onEditVault,
    this.onDeleteVault,
    this.onAddVault,
    this.onOpenInNewTab,
    this.keepBrowserTabsOnNavigate = false,
  });

  void _navigateToTab(BuildContext context, int tabIndex) {
    Navigator.pop(context); // Close drawer
    // If inside a vault/storage browser, pop it to return to MainShell
    if (!keepBrowserTabsOnNavigate &&
        currentVolId != null &&
        Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    onSelectTab?.call(tabIndex);
  }

  void _promptRename(
    BuildContext context,
    WidgetRef ref,
    ExternalStorageLocation loc,
  ) {
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isNotEmpty) {
                ref
                    .read(externalStorageLocationsProvider.notifier)
                    .renameLocation(loc.id, text);
              }
              Navigator.pop(ctx);
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ExternalStorageLocation loc,
  ) {
    final isCurrent = currentVolId != null && currentVolId == loc.volId;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.removeStorageLocationTitle),
        content: Text(
          context.l10n.removeStorageLocationConfirm(loc.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(externalStorageLocationsProvider.notifier)
                  .removeLocation(loc.id);
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
    if (lower.contains('cloud') ||
        lower.contains('drive') ||
        lower.contains('nextcloud') ||
        lower.contains('owncloud')) {
      return Icons.cloud_outlined;
    }
    if (lower.contains('primary') || lower.contains('emulated')) {
      return Icons.folder_special_rounded;
    }
    return Icons.sd_card_rounded;
  }

  /// Closes the drawer, so the confirmation snackbar is not hidden behind it,
  /// and copies [path] to the clipboard.
  void _copyPathAndClose(BuildContext context, String path) {
    Navigator.pop(context);
    unawaited(copyPathToClipboard(context, path));
  }

  void _showLocationContextMenu(
    BuildContext context,
    WidgetRef ref,
    ExternalStorageLocation loc,
    Offset tapPosition,
  ) {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        if (onOpenInNewTab != null)
          PopupMenuItem(
            value: 'new_tab',
            child: Row(
              children: [
                Icon(Icons.tab_rounded, size: 20, color: cs.onSurface),
                const SizedBox(width: 12),
                Text(context.l10n.browserTabOpenInNewTab),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'copy_path',
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 20, color: cs.onSurface),
              const SizedBox(width: 12),
              Text(context.l10n.copyPathAction),
            ],
          ),
        ),
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
      if (action == 'new_tab') {
        _openLocationInNewTab(context, ref, loc);
      } else if (action == 'copy_path') {
        if (!context.mounted) return;
        _copyPathAndClose(
          context,
          readablePathFromUri(loc.path.isNotEmpty ? loc.path : loc.resolvedUri),
        );
      } else if (action == 'rename') {
        _promptRename(context, ref, loc);
      } else if (action == 'remove') {
        _confirmRemove(context, ref, loc);
      }
    });
  }

  Future<void> _openLocationInNewTab(
    BuildContext context,
    WidgetRef ref,
    ExternalStorageLocation loc,
  ) async {
    final accessible = await ref
        .read(externalStorageLocationsProvider.notifier)
        .isAccessible(loc);
    if (!context.mounted) return;
    Navigator.pop(context); // close the drawer
    if (!accessible) {
      showAppSnackBar(
        context,
        message: context.l10n.storageLocationUnavailable(loc.displayName),
        tone: AppBannerTone.warning,
      );
      return;
    }
    onOpenInNewTab?.call(
      buildExternalStorageContainer(
        rootPath: loc.resolvedUri,
        displayName: loc.displayName,
        volId: loc.volId,
      ),
    );
  }

  /// Long-press menu for the device storage entry: "Open in new tab" (only
  /// while the browser is hosted in tabs) and "Copy path".
  void _showLocalStorageMenu(
    BuildContext context,
    Offset tapPosition,
    MountedContainer container,
  ) {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        if (onOpenInNewTab != null)
          PopupMenuItem(
            value: 'new_tab',
            child: Row(
              children: [
                Icon(Icons.tab_rounded, size: 20, color: cs.onSurface),
                const SizedBox(width: 12),
                Text(context.l10n.browserTabOpenInNewTab),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'copy_path',
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 20, color: cs.onSurface),
              const SizedBox(width: 12),
              Text(context.l10n.copyPathAction),
            ],
          ),
        ),
      ],
    ).then((action) {
      if (!context.mounted) return;
      if (action == 'new_tab') {
        Navigator.pop(context); // close the drawer
        onOpenInNewTab?.call(container);
      } else if (action == 'copy_path') {
        _copyPathAndClose(context, readablePathFromUri(container.uri));
      }
    });
  }

  Future<void> _lockSingleVault(
    BuildContext context,
    WidgetRef ref,
    MountedContainer container,
  ) async {
    final controller = ref.read(vaultDashboardControllerProvider.notifier);
    if (!controller.acquireLockGuard(container.volId)) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.operationInProgressWaitMessage,
          tone: AppBannerTone.warning,
        );
      }
      return;
    }
    try {
      final locked = await ref
          .read(vaultLifecycleApiProvider)
          .lockContainer(container.uri);
      if (!locked) throw StateError('Container lock did not complete');
      VeLog.i(
        'AppNavigationDrawer',
        '_lockSingleVault: native lockContainer succeeded for volId=${container.volId}',
      );
      controller.onContainerLocked(container.volId);
    } catch (e) {
      VeLog.e(
        'AppNavigationDrawer',
        '_lockSingleVault: native lockContainer threw for volId=${container.volId}',
        e,
      );
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.lockFailedMessage(e.runtimeType.toString()),
          tone: AppBannerTone.warning,
        );
      }
    } finally {
      controller.releaseLockGuard(container.volId);
    }
  }

  Future<void> _lockAllVaults(
    BuildContext context,
    WidgetRef ref,
    List<MountedContainer> mounted,
  ) async {
    final willLeaveCurrentScreen =
        currentVolId != null && mounted.any((c) => c.volId == currentVolId);
    final controller = ref.read(vaultDashboardControllerProvider.notifier);
    final currentVaultGuardAcquired =
        willLeaveCurrentScreen && controller.acquireLockGuard(currentVolId!);
    if (currentVaultGuardAcquired) {
      Navigator.pop(context);
    }
    var currentVaultGuardHeld = currentVaultGuardAcquired;
    var skippedBusyVault = false;
    try {
      for (final c in mounted) {
        final guardAlreadyHeld =
            c.volId == currentVolId && currentVaultGuardHeld;
        if (!guardAlreadyHeld && !controller.acquireLockGuard(c.volId)) {
          skippedBusyVault = true;
          continue;
        }
        try {
          final locked = await ref
              .read(vaultLifecycleApiProvider)
              .lockContainer(c.uri);
          if (locked) {
            controller.onContainerLocked(c.volId);
          } else {
            skippedBusyVault = true;
          }
        } catch (_) {
          skippedBusyVault = true;
        } finally {
          controller.releaseLockGuard(c.volId);
          if (guardAlreadyHeld) currentVaultGuardHeld = false;
        }
      }
    } finally {
      if (currentVaultGuardHeld) {
        controller.releaseLockGuard(currentVolId!);
      }
    }
    if (skippedBusyVault && context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.operationInProgressWaitMessage,
        tone: AppBannerTone.warning,
      );
    }
  }

  void _handleEditVault(
    BuildContext context,
    WidgetRef ref,
    VaultListItem item,
  ) {
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
        builder: (_) => SkinAreaScope(
          area: SkinArea.dashboard,
          child: ContainerConfigScreen(
            uri: item.uri,
            currentLabel: item.name,
            existingRecord: existing,
            appSettings: state.appSettings,
            mountedContainer: mountedC,
            onSaved: (record) => ref
                .read(vaultDashboardControllerProvider.notifier)
                .updateContainerRecord(item.uri, record),
          ),
        ),
      ),
    );
  }

  void _handleDeleteVault(
    BuildContext context,
    WidgetRef ref,
    VaultListItem item,
  ) {
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
    ref
        .read(vaultDashboardControllerProvider.notifier)
        .handleSwipeToRemove(item.uri, (item as LockedVaultItem).record);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The side menu has its own colors; build its content inside that scope so
    // it never picks up the page it happens to be opened from.
    return SkinAreaScope(
      area: SkinArea.drawer,
      child: Consumer(
        builder: (context, ref, _) => _buildDrawerContent(context, ref),
      ),
    );
  }

  Widget _buildDrawerContent(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dashboardState = ref.watch(vaultDashboardControllerProvider);
    final displayItems = ref
        .read(vaultDashboardControllerProvider.notifier)
        .getDisplayItems();
    final externalStorages = ref.watch(externalStorageLocationsProvider);
    final showStorageLocations = ref.watch(
      appSettingsControllerProvider.select(
        (s) => s.settings.showStorageLocationsInDrawer,
      ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                children: [
                  // 1. Dashboard (Home)
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    selected: isDashboard,
                    selectedTileColor: cs.secondaryContainer.withValues(
                      alpha: 0.5,
                    ),
                    leading: Icon(
                      Icons.dashboard_rounded,
                      color: isDashboard ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(
                      context.l10n.dashboardNavLabel,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: isDashboard
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                    onTap: () => _navigateToTab(context, 0),
                  ),

                  // 2. Encrypted Vaults Section (Swipeable Rows with Lock Button)
                  if (displayItems.isNotEmpty || onAddVault != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 2, 2),
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
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                size: 20,
                                color: cs.onSurfaceVariant,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: EdgeInsets.zero,
                              onSelected: (action) {
                                if (action == 'lock_all') {
                                  _lockAllVaults(
                                    context,
                                    ref,
                                    dashboardState.mounted,
                                  );
                                }
                              },
                              itemBuilder: (ctx) => [
                                PopupMenuItem<String>(
                                  value: 'lock_all',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.lock_outline_rounded,
                                        size: 20,
                                        color: cs.error,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        context.l10n.lockAllVaultsTitle,
                                        style: TextStyle(color: cs.error),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    for (final item in displayItems) ...[
                      (() {
                        final isMounted = item.isMounted;
                        final volId = item is MountedVaultItem
                            ? item.container.volId
                            : null;
                        final isCurrent =
                            volId != null && volId == currentVolId;

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
                                // A tabbed browser stays mounted behind
                                // the unlock flow so its locations and
                                // per-tab state survive the visit.
                                if (currentVolId != null &&
                                    onOpenInNewTab == null &&
                                    Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                }
                                if (!keepBrowserTabsOnNavigate) {
                                  onSelectTab?.call(0);
                                }
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  onUnlockVault?.call(item);
                                });
                              }
                            },
                            onOpenInNewTab:
                                (isMounted && onOpenInNewTab != null)
                                ? () {
                                    Navigator.pop(context); // close the drawer
                                    onOpenInNewTab!(
                                      (item as MountedVaultItem).container,
                                    );
                                  }
                                : null,
                            onLock: isMounted
                                ? () async {
                                    final container =
                                        (item as MountedVaultItem).container;
                                    if (isCurrent) {
                                      Navigator.pop(context);
                                    }
                                    await _lockSingleVault(
                                      context,
                                      ref,
                                      container,
                                    );
                                  }
                                : null,
                            onCopyPath: () => _copyPathAndClose(
                              context,
                              readablePathFromUri(item.uri),
                            ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
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
                          if (currentVolId != null &&
                              Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                          onSelectTab?.call(0);
                          onAddVault!();
                        },
                      ),
                  ],

                  // Bookmarks of unlocked vaults and available storage
                  // locations; empty (and invisible) when there are none.
                  DrawerBookmarksSection(
                    vaults: [
                      for (final item in displayItems)
                        if (item is MountedVaultItem) item.container,
                    ],
                    storageLocations: [
                      ?primary,
                      for (final loc in externalStorages)
                        buildExternalStorageContainer(
                          rootPath: loc.resolvedUri,
                          displayName: loc.displayName,
                          volId: loc.volId,
                        ),
                    ],
                    currentVolId: currentVolId,
                    onSelectContainer: onSelectContainer,
                    onOpenInNewTab: onOpenInNewTab,
                    onOpenLocalStorage: onOpenLocalStorage,
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 1),
                    child: Divider(),
                  ),

                  if (showStorageLocations) ...[
                    Builder(
                      builder: (tileContext) => ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        selected: currentVolId == kDecoyLocalVolId,
                        selectedTileColor: cs.secondaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        leading: Icon(
                          Icons.phone_android_rounded,
                          color: currentVolId == kDecoyLocalVolId
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        title: Text(
                          context.l10n.localStorageCardTitle,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: currentVolId == kDecoyLocalVolId
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                        onLongPress: primary != null
                            ? () {
                                final box =
                                    tileContext.findRenderObject()
                                        as RenderBox?;
                                final pos = box != null
                                    ? box.localToGlobal(
                                        box.size.center(Offset.zero),
                                      )
                                    : Offset.zero;
                                _showLocalStorageMenu(context, pos, primary);
                              }
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          if (currentVolId == kDecoyLocalVolId) return;
                          if (onOpenLocalStorage != null) {
                            onOpenLocalStorage!();
                          } else if (primary != null) {
                            onSelectContainer?.call(primary);
                          }
                        },
                      ),
                    ),

                    for (final loc in externalStorages) ...[
                      Builder(
                        builder: (tileContext) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onSecondaryTapDown: (details) =>
                                _showLocationContextMenu(
                                  context,
                                  ref,
                                  loc,
                                  details.globalPosition,
                                ),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                              selected: currentVolId == loc.volId,
                              selectedTileColor: cs.secondaryContainer
                                  .withValues(alpha: 0.5),
                              leading: Icon(
                                _iconForStorage(loc.path),
                                color: currentVolId == loc.volId
                                    ? cs.primary
                                    : cs.secondary,
                              ),
                              title: Text(
                                loc.displayName,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: currentVolId == loc.volId
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onLongPress: () {
                                final box =
                                    tileContext.findRenderObject()
                                        as RenderBox?;
                                final pos = box != null
                                    ? box.localToGlobal(
                                        box.size.center(Offset.zero),
                                      )
                                    : Offset.zero;
                                _showLocationContextMenu(
                                  context,
                                  ref,
                                  loc,
                                  pos,
                                );
                              },
                              onTap: () async {
                                if (currentVolId == loc.volId) {
                                  Navigator.pop(context);
                                  return;
                                }
                                final isAccessible = await ref
                                    .read(
                                      externalStorageLocationsProvider.notifier,
                                    )
                                    .isAccessible(loc);
                                if (!context.mounted) return;
                                if (!isAccessible) {
                                  Navigator.pop(context);
                                  showAppSnackBar(
                                    context,
                                    message: context.l10n
                                        .storageLocationUnavailable(
                                          loc.displayName,
                                        ),
                                    tone: AppBannerTone.warning,
                                  );
                                  return;
                                }
                                Navigator.pop(context);
                                onSelectContainer?.call(
                                  buildExternalStorageContainer(
                                    rootPath: loc.resolvedUri,
                                    displayName: loc.displayName,
                                    volId: loc.volId,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],

                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      leading: Icon(Icons.add, color: cs.primary),
                      title: Text(
                        context.l10n.addStorageLocationTitle,
                        style: textTheme.bodyMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () async {
                        final notifier = ref.read(
                          externalStorageLocationsProvider.notifier,
                        );
                        ExternalStorageLocation? loc;
                        try {
                          loc = await ref
                              .read(sessionLockControllerProvider)
                              .withLockSuppression(
                                () => notifier.promptAndAddLocation(),
                              );
                        } on SelfReferentialStorageException {
                          if (!context.mounted) return;
                          showAppSnackBar(
                            context,
                            message:
                                context.l10n.storageLocationSelfReferenceError,
                            tone: AppBannerTone.warning,
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        if (loc != null) {
                          Navigator.pop(context);
                          onSelectContainer?.call(
                            buildExternalStorageContainer(
                              rootPath: loc.resolvedUri,
                              displayName: loc.displayName,
                              volId: loc.volId,
                            ),
                          );
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    selected: isTools,
                    selectedTileColor: cs.secondaryContainer.withValues(
                      alpha: 0.5,
                    ),
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
                          builder: (_) => SkinAreaScope(
                            area: SkinArea.tools,
                            child: ToolsScreen(
                              mountedContainers: ValueNotifier(
                                dashboardState.mounted,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // 5. App & Security Settings
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    selected: isSettings,
                    selectedTileColor: cs.secondaryContainer.withValues(
                      alpha: 0.5,
                    ),
                    leading: Icon(
                      Icons.settings,
                      color: isSettings ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(
                      context.l10n.settingsMenuItem,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: isSettings
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SkinAreaScope(
                            area: SkinArea.settings,
                            child: const AppSettingsScreen(),
                          ),
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

class _DrawerVaultRow extends ConsumerWidget {
  final VaultListItem item;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onLock;
  final VoidCallback? onOpenInNewTab;
  final VoidCallback onCopyPath;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DrawerVaultRow({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onTap,
    this.onOpenInNewTab,
    required this.onCopyPath,
    required this.onLock,
    required this.onEdit,
    required this.onDelete,
  });

  void _showContextMenu(BuildContext context, Offset tapPosition) {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(context).colorScheme;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        if (onOpenInNewTab != null)
          PopupMenuItem(
            value: 'new_tab',
            child: Row(
              children: [
                Icon(Icons.tab_rounded, size: 20, color: cs.onSurface),
                const SizedBox(width: 12),
                Text(context.l10n.browserTabOpenInNewTab),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'copy_path',
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 20, color: cs.onSurface),
              const SizedBox(width: 12),
              Text(context.l10n.copyPathAction),
            ],
          ),
        ),
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
      if (action == 'new_tab') onOpenInNewTab?.call();
      if (action == 'copy_path') onCopyPath();
      if (action == 'edit') onEdit();
      if (action == 'lock') onLock?.call();
      if (action == 'delete') onDelete();
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final nameMode = ref.watch(longFileNameDisplayModeProvider);
    final isMounted = item.isMounted;
    final isUsb = item.uri.startsWith('usb:');
    final format = switch (item) {
      MountedVaultItem(:final container) => container.format,
      LockedVaultItem(:final record) => record.format,
    };

    final tileColor = isCurrent
        ? Color.alphaBlend(
            cs.secondaryContainer.withValues(alpha: 0.6),
            cs.surfaceContainerHigh,
          )
        : cs.surfaceContainerHigh;

    return Material(
      color: tileColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Builder(
        builder: (tileContext) {
          return ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            contentPadding: const EdgeInsets.only(left: 12, right: 6),
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isCurrent
                    ? cs.primaryContainer
                    : (isMounted
                          ? cs.primaryContainer.withValues(alpha: 0.7)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: isUsb
                  ? Icon(
                      Icons.usb_rounded,
                      size: 18,
                      color: isMounted
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    )
                  : ContainerFormatIcon(
                      format: format,
                      size: 18,
                      color: isMounted
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
            ),
            title: FileNameLabel(
              text: item.name,
              mode: nameMode,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: isCurrent
                    ? FontWeight.bold
                    : (isMounted ? FontWeight.w600 : FontWeight.normal),
                color: isMounted ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
            trailing: onLock != null
                ? IconButton(
                    icon: Icon(
                      Icons.lock_outline_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    tooltip: context.l10n.lockVaultTooltip,
                    visualDensity: VisualDensity.compact,
                    onPressed: onLock,
                  )
                : null,
            onLongPress: () {
              final box = tileContext.findRenderObject() as RenderBox?;
              final pos = box != null
                  ? box.localToGlobal(box.size.center(Offset.zero))
                  : Offset.zero;
              _showContextMenu(context, pos);
            },
            onTap: onTap,
          );
        },
      ),
    );
  }
}
