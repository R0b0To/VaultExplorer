import 'package:vaultexplorer/core/utils/local_storage_name.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/authenticator/authenticator_screen.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/widgets/file_name_label.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_launcher.dart';
import 'package:vaultexplorer/features/dashboard/widgets/drawer_bookmarks_section.dart';
import 'package:vaultexplorer/features/dashboard/widgets/drawer_categories_section.dart';
import 'package:vaultexplorer/features/dashboard/widgets/drawer_group.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/dashboard/widgets/lock_all_vaults.dart';
import 'package:vaultexplorer/features/dashboard/widgets/lock_flush_prompt.dart';
import 'package:vaultexplorer/features/settings/long_file_name_display_provider.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';
import 'package:vaultexplorer/core/widgets/menus/context_menu_region.dart';

/// Prompts for All Files Access when a raw-path volume (SD card / USB) is
/// selected without permission granted.
Future<bool> _ensureAllFilesAccess(BuildContext context, WidgetRef ref) async {
  final lifecycle = ref.read(vaultLifecycleApiProvider);
  if (await lifecycle.hasAllFilesAccess()) return true;
  if (!context.mounted) return false;
  final shouldRequest = await showAppConfirmDialog(
    context,
    title: context.l10n.localStoragePermissionTitle,
    message: context.l10n.filesPermissionMessage,
    confirmLabel: context.l10n.localStorageGrantAccess,
  );
  if (shouldRequest) {
    await lifecycle.requestAllFilesAccess(openSettings: true);
  }
  return false;
}

/// Whether the drawer's Vaults group shows its vault rows. Kept in a provider
/// so it survives the drawer being rebuilt or reopened (not across restarts).
class _VaultsExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final _vaultsExpandedProvider =
    NotifierProvider<_VaultsExpandedNotifier, bool>(_VaultsExpandedNotifier.new);

class AppNavigationDrawer extends ConsumerWidget {
  final int? currentVolId;
  final MountedContainer? primaryLocalContainer;
  final ValueListenable<MountedContainer?>? localStorageNotifier;
  final VoidCallback? onOpenLocalStorage;
  /// Opens an external raw-path storage (SD card / USB volume) through the
  /// all-files-access permission flow, mirroring [onOpenLocalStorage] for
  /// the primary internal storage. When null, external tiles fall back to
  /// [onSelectContainer] (direct open, no permission prompt).
  final ValueChanged<MountedContainer>? onOpenExternalStorage;
  final int selectedTabIndex;
  final ValueChanged<int>? onSelectTab;
  final ValueChanged<MountedContainer>? onSelectContainer;
  final ValueChanged<VaultListItem>? onUnlockVault;
  final ValueChanged<VaultListItem>? onEditVault;
  final ValueChanged<VaultListItem>? onDeleteVault;
  final VoidCallback? onAddVault;

  /// What the "Vaults" header does where the menu has no tab bar of its own to
  /// switch (a file manager window): shows the Vaults page there. When null
  /// the header goes through [onSelectTab] like Tools and Settings do.
  final VoidCallback? onOpenVaults;

  /// Set only while the file manager is open with tabs: the long-press menus
  /// of vaults and storages then offer "Open in new tab".
  final ValueChanged<MountedContainer>? onOpenInNewTab;
  final ValueChanged<FileCategory>? onOpenCategory;
  final bool keepBrowserTabsOnNavigate;

  /// True when this menu is shown as a permanent sidebar beside the content
  /// (tablet landscape / desktop) instead of inside a modal drawer. There is
  /// then no drawer to close, Tools and Settings open in the content area
  /// next to the sidebar, and the menu draws as a plain panel.
  final bool docked;

  const AppNavigationDrawer({
    super.key,
    this.currentVolId,
    this.primaryLocalContainer,
    this.localStorageNotifier,
    this.onOpenLocalStorage,
    this.onOpenExternalStorage,
    this.selectedTabIndex = 0,
    this.onSelectTab,
    this.onSelectContainer,
    this.onUnlockVault,
    this.onEditVault,
    this.onDeleteVault,
    this.onAddVault,
    this.onOpenVaults,
    this.onOpenInNewTab,
    this.onOpenCategory,
    this.keepBrowserTabsOnNavigate = false,
    this.docked = false,
  });

  /// Closes the modal drawer. A docked sidebar has nothing to close, and a
  /// bare `Navigator.pop` there would pop the real route underneath it.
  void _closeDrawer(BuildContext context) {
    if (docked) return;
    Navigator.pop(context);
  }

  void _navigateToTab(BuildContext context, int tabIndex) {
    _closeDrawer(context); // Close drawer
    // If inside a vault/storage browser, pop it to return to MainShell
    if (!docked &&
        !keepBrowserTabsOnNavigate &&
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
    return PlatformFeatures.externalStorageIcon;
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
        // System-discovered volumes (SD card, USB) are neither renameable
        // nor removable: they're re-derived from StorageManager on every
        // refresh, so rename/remove would either no-op or come back.
        if (!loc.isSystemVolume)
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
        if (!loc.isSystemVolume)
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
      if (!context.mounted) return;
      if (action == 'new_tab') {
        _openLocationInNewTab(context, ref, loc);
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
    // SAF locations carry their own persisted grant; only raw
    // paths (auto-discovered SD card / USB) need file access.
    if (!loc.resolvedUri.startsWith('content://') &&
        !await _ensureAllFilesAccess(context, ref)) {
      return;
    }
    if (!context.mounted) return;
    final accessible = await ref
        .read(externalStorageLocationsProvider.notifier)
        .isAccessible(loc);
    if (!context.mounted) return;
    _closeDrawer(context); // close the drawer
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

  /// Long-press menu for entries that have no menu of their own (device
  /// storage): just "Open in new tab".
  void _showOpenInNewTabMenu(
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
      ],
    ).then((action) {
      if (action != 'new_tab' || !context.mounted) return;
      _closeDrawer(context); // close the drawer
      onOpenInNewTab?.call(container);
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
      final result = await lockWithFlushPrompt(
        context: context,
        lifecycle: ref.read(vaultLifecycleApiProvider),
        uri: container.uri,
        displayName: container.displayName,
      );
      // The device refused the write-back and the person chose to keep the
      // container open: nothing failed, so there is no error to report.
      if (result == LockResult.flushRefused) return;
      if (result != LockResult.locked) {
        throw StateError('Container lock did not complete');
      }
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
  ) => lockAllVaults(
    context,
    ref,
    mounted,
    currentVolId: currentVolId,
    onLeavingCurrentVault: () => _closeDrawer(context),
  );

  void _handleEditVault(
    BuildContext context,
    WidgetRef ref,
    VaultListItem item,
  ) {
    if (onEditVault != null) {
      onEditVault!(item);
      return;
    }
    openContainerConfig(context, uri: item.uri, currentLabel: item.name);
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
    final navigator = Navigator.of(context);
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
    final enableAuthenticator = ref.watch(
      appSettingsControllerProvider.select(
        (s) => s.settings.enableAuthenticator,
      ),
    );
    final primary = primaryLocalContainer;
    final vaultsExpanded = ref.watch(_vaultsExpandedProvider);

    final isDashboard = currentVolId == null && selectedTabIndex == 0;
    final isTools = currentVolId == null && selectedTabIndex == 1;
    final isSettings = currentVolId == null && selectedTabIndex == 2;

    void openTools() {
      if (docked && onSelectTab != null) {
        // Docked: Tools opens in the content area, so the sidebar stays
        // visible beside it.
        onSelectTab!(1);
        return;
      }
      _closeDrawer(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(
            area: SkinArea.tools,
            child: ToolsScreen(
              mountedContainers: ValueNotifier(dashboardState.mounted),
              localStorageContainer: localStorageNotifier,
              onOpenInBrowser: onSelectContainer == null
                  ? null
                  : (container) {
                      if (navigator.canPop()) navigator.pop();
                      onSelectContainer!(container);
                    },
            ),
          ),
        ),
      );
    }

    void openSettings() {
      if (docked && onSelectTab != null) {
        onSelectTab!(2);
        return;
      }
      _closeDrawer(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(
            area: SkinArea.settings,
            child: const AppSettingsScreen(),
          ),
        ),
      );
    }

    return _DrawerShell(
      docked: docked,
      // In landscape the system puts a cutout / nav bar inset on one side
      // (which one flips with the rotation). The modal drawer paints its own
      // background under it, so padding the content by that inset only
      // leaves an empty strip and squeezes the titles: ignore both sides.
      // A docked sidebar sits at the window edge, so it keeps its left inset.
      child: SafeArea(
        left: docked,
        right: false,
        // ListTile adds its own SafeArea, so without this every row would
        // still reserve the inset and shrink the titles.
        child: MediaQuery.removePadding(
          context: context,
          removeLeft: !docked,
          removeRight: true,
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
                  // Encrypted vaults (swipeable rows with lock button). The
                  // "Vaults" header doubles as the Dashboard shortcut, like
                  // "This PC" above the list of drives.
                  DrawerGroup(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              dense: true,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              selected: isDashboard,
                              selectedTileColor: cs.secondaryContainer
                                  .withValues(alpha: 0.5),
                              leading: Icon(
                                Icons.shield_rounded,
                                color: isDashboard
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                              title: Text(
                                context.l10n.vaultsSectionTitle,
                                style: textTheme.bodyLarge?.copyWith(
                                  fontWeight: isDashboard
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                              ),
                              onTap: () {
                                final openVaults = onOpenVaults;
                                if (openVaults == null) {
                                  _navigateToTab(context, 0);
                                } else {
                                  _closeDrawer(context);
                                  openVaults();
                                }
                              },
                              // Expand / collapse inside the pill, so the
                              // card's outer edges stay on the same rail as
                              // the cards below.
                              trailing: IconButton(
                                tooltip: vaultsExpanded
                                    ? MaterialLocalizations.of(
                                        context,
                                      ).expandedIconTapHint
                                    : MaterialLocalizations.of(
                                        context,
                                      ).collapsedIconTapHint,
                                visualDensity: VisualDensity.compact,
                                iconSize: 20,
                                icon: AnimatedRotation(
                                  turns: vaultsExpanded ? 0.25 : 0,
                                  duration: const Duration(milliseconds: 150),
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                onPressed: () => ref
                                    .read(_vaultsExpandedProvider.notifier)
                                    .toggle(),
                              ),
                            ),
                          ),
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
                    if (vaultsExpanded)
                    for (final item in displayItems) ...[
                      (() {
                        final isMounted = item.isMounted;
                        final volId = item is MountedVaultItem
                            ? item.container.volId
                            : null;
                        final isCurrent =
                            volId != null && volId == currentVolId;

                        return Padding(
                          padding: const EdgeInsets.only(left: 6, bottom: 4),
                          child: _DrawerVaultRow(
                            key: ValueKey('drawer_vault_${item.uri}'),
                            item: item,
                            isCurrent: isCurrent,
                            onTap: () {
                              _closeDrawer(context);
                              if (isCurrent) return;
                              if (item is MountedVaultItem) {
                                onSelectContainer?.call(item.container);
                              } else {
                                // A tabbed browser stays mounted behind
                                // the unlock flow so its locations and
                                // per-tab state survive the visit.
                                if (!docked &&
                                    currentVolId != null &&
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
                                    _closeDrawer(context); // close the drawer
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
                                      _closeDrawer(context);
                                    }
                                    await _lockSingleVault(
                                      context,
                                      ref,
                                      container,
                                    );
                                  }
                                : null,
                            onEdit: () {
                              _closeDrawer(context);
                              _handleEditVault(context, ref, item);
                            },
                            onDelete: () {
                              _closeDrawer(context);
                              _handleDeleteVault(context, ref, item);
                            },
                          ),
                        );
                      })(),
                    ],
                    if (vaultsExpanded && onAddVault != null)
                      ListTile(
                        contentPadding: const EdgeInsets.only(left: 22, right: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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
                          _closeDrawer(context);
                          if (!docked &&
                              currentVolId != null &&
                              Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                          onSelectTab?.call(0);
                          onAddVault!();
                        },
                      ),
                    ]),

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
                    docked: docked,
                  ),

                  if (showStorageLocations)
                    DrawerGroup(children: [
                    // Keeps the drives' free space current while the list is on screen.
                    if (PlatformFeatures.isDesktop) const _DriveListRefresher(),
                    Builder(
                      builder: (tileContext) => ContextMenuRegion(
                        onOpen: (onOpenInNewTab != null && primary != null)
                            ? (pos) =>
                                  _showOpenInNewTabMenu(context, pos, primary)
                            : null,
                        child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        selected: currentVolId == kDecoyLocalVolId,
                        selectedTileColor: cs.secondaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        leading: Icon(
                          PlatformFeatures.localStorageIcon,
                          color: currentVolId == kDecoyLocalVolId
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        title: Text(
                          localStorageDisplayName(context.l10n.localStorageCardTitle),
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: currentVolId == kDecoyLocalVolId
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                        onLongPress:
                            (onOpenInNewTab != null && primary != null)
                            ? touchOnlyLongPress(() {
                                final box =
                                    tileContext.findRenderObject()
                                        as RenderBox?;
                                final pos = box != null
                                    ? box.localToGlobal(
                                        box.size.center(Offset.zero),
                                      )
                                    : Offset.zero;
                                _showOpenInNewTabMenu(context, pos, primary);
                              })
                            : null,
                        onTap: () {
                          _closeDrawer(context);
                          if (currentVolId == kDecoyLocalVolId) return;
                          if (onOpenLocalStorage != null) {
                            onOpenLocalStorage!();
                          } else if (primary != null) {
                            onSelectContainer?.call(primary);
                          }
                        },
                        ),
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
                                borderRadius: BorderRadius.circular(10),
                              ),
                              selected: currentVolId == loc.volId,
                              selectedTileColor: cs.secondaryContainer
                                  .withValues(alpha: 0.5),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                              // One block: icon, name and the free / total
                              // size on a single row, with the usage bar
                              // spanning the tile's full width underneath.
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _iconForStorage(loc.path),
                                        size: 20,
                                        color: currentVolId == loc.volId
                                            ? cs.primary
                                            : cs.secondary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          loc.displayName,
                                          style: textTheme.bodyMedium?.copyWith(
                                            fontWeight:
                                                currentVolId == loc.volId
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (loc.freeBytes != null &&
                                          loc.totalBytes != null) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          _freeOfTotal(
                                            loc.freeBytes!,
                                            loc.totalBytes!,
                                          ),
                                          style: textTheme.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (loc.usedFraction != null)
                                    _DriveUsageBar(fraction: loc.usedFraction!),
                                ],
                              ),
                              onLongPress: touchOnlyLongPress(() {
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
                              }),
                              onTap: () async {
                                if (currentVolId == loc.volId) {
                                  _closeDrawer(context);
                                  return;
                                }
                                final container = buildExternalStorageContainer(
                                  rootPath: loc.resolvedUri,
                                  displayName: loc.displayName,
                                  volId: loc.volId,
                                );
                                // Raw-path volumes (SD card / USB) go
                                // through the all-files-access flow, like
                                // the primary Local Storage tile does; a
                                // missing grant would otherwise just be
                                // reported as "unavailable" below.
                                if (!loc.resolvedUri.startsWith('content://') &&
                                    onOpenExternalStorage != null) {
                                  _closeDrawer(context);
                                  onOpenExternalStorage!(container);
                                  return;
                                }
                                final isAccessible = await ref
                                    .read(
                                      externalStorageLocationsProvider.notifier,
                                    )
                                    .isAccessible(loc);
                                if (!context.mounted) return;
                                if (!isAccessible) {
                                  _closeDrawer(context);
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
                                _closeDrawer(context);
                                onSelectContainer?.call(container);
                              },
                            ),
                          );
                        },
                      ),
                    ],

                    // Desktop lists its drives itself; no manual add button there.
                    if (!PlatformFeatures.isDesktop)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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
                          _closeDrawer(context);
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
                    ]),

                  // 3b. Category shortcuts (Images, Videos, Audio, Documents)
                  DrawerCategoriesSection(
                    primaryLocalContainer: primary,
                    currentVolId: currentVolId,
                    onOpenLocalStorage: onOpenLocalStorage,
                    onSelectContainer: onSelectContainer,
                    onOpenCategory: onOpenCategory,
                    docked: docked,
                  ),

                  // 3b. Authenticator Destination (same screen as the
                  // dashboard app bar shortcut, reachable from every tab)
                  if (enableAuthenticator)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(
                        Icons.verified_user_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      title: Text(
                        context.l10n.authenticatorScreenTitle,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        _closeDrawer(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AuthenticatorScreen(),
                          ),
                        );
                      },
                    ),

                ],
              ),
            ),
            // Tools and Settings are pinned to the bottom of the menu, outside
            // the scrolling list, so they are always visible: the same compact
            // icon strip whether the menu is docked or a modal drawer.
            _ToolsStrip(
              toolsSelected: isTools,
              settingsSelected: isSettings,
              onTools: openTools,
              onSettings: openSettings,
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Tools and Settings as two icon buttons along the bottom of the menu (docked
/// sidebar or modal drawer). No divider above them: they continue the menu.
class _ToolsStrip extends StatelessWidget {
  const _ToolsStrip({
    required this.toolsSelected,
    required this.settingsSelected,
    required this.onTools,
    required this.onSettings,
  });

  final bool toolsSelected;
  final bool settingsSelected;
  final VoidCallback onTools;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget button(IconData icon, String tooltip, bool selected, VoidCallback onTap) {
      return IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        onPressed: onTap,
        isSelected: selected,
        style: IconButton.styleFrom(
          fixedSize: const Size(36, 36),
          minimumSize: const Size(36, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          foregroundColor: selected ? cs.primary : cs.onSurfaceVariant,
          backgroundColor: selected
              ? cs.secondaryContainer.withValues(alpha: 0.5)
              : null,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: SizedBox(
            height: 46,
            child: DecoratedBox(
            // Same soft surface as the groups above, so the two buttons read
            // as a footer of the menu rather than loose icons in the corner.
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              button(
                Icons.build_rounded,
                context.l10n.navBarToolsLabel,
                toolsSelected,
                onTools,
              ),
              const SizedBox(width: 4),
              button(
                Icons.settings,
                context.l10n.settingsMenuItem,
                settingsSelected,
                onSettings,
              ),
            ],
          ),
            ),
          ),
          ),
        ),
      ],
    );
  }
}

/// The surface behind the menu: a modal [Drawer] normally, or a flat panel
/// when the menu is docked beside the content (the shell draws the divider).
class _DrawerShell extends StatelessWidget {
  const _DrawerShell({required this.docked, required this.child});

  final bool docked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!docked) return Drawer(child: child);
    final theme = Theme.of(context);
    return Material(
      color:
          theme.drawerTheme.backgroundColor ??
          theme.colorScheme.surfaceContainerLow,
      child: child,
    );
  }
}

class _DrawerVaultRow extends ConsumerWidget {
  final VaultListItem item;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onLock;
  final VoidCallback? onOpenInNewTab;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DrawerVaultRow({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onTap,
    this.onOpenInNewTab,
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

    // No resting fill on locked vaults (a subtle one appears on hover); an
    // unlocked vault gets a light tint and the open one a stronger fill.
    final tileColor = isCurrent
        ? cs.secondaryContainer.withValues(alpha: 0.7)
        : isMounted
        ? cs.secondaryContainer.withValues(alpha: 0.35)
        : Colors.transparent;

    return Material(
      color: tileColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Builder(
        builder: (tileContext) {
          return ContextMenuRegion(
            onOpen: (pos) => _showContextMenu(context, pos),
            child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            contentPadding: const EdgeInsets.only(left: 12, right: 6),
            hoverColor: cs.onSurface.withValues(alpha: 0.06),
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isCurrent
                    ? cs.primaryContainer
                    : (isMounted
                          ? cs.primaryContainer.withValues(alpha: 0.7)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.9)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: isUsb
                  ? Icon(
                      Icons.usb_rounded,
                      size: 18,
                      color: isMounted
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.9),
                    )
                  : ContainerFormatIcon(
                      format: format,
                      size: 18,
                      color: isMounted
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.9),
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
                : Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
            onLongPress: touchOnlyLongPress(() {
              final box = tileContext.findRenderObject() as RenderBox?;
              final pos = box != null
                  ? box.localToGlobal(box.size.center(Offset.zero))
                  : Offset.zero;
              _showContextMenu(context, pos);
            }),
            onTap: onTap,
            ),
          );
        },
      ),
    );
  }
}

/// "171 / 999 GB": free space over total, with the unit written once when both
/// use the same one.
String _freeOfTotal(int free, int total) {
  final f = formatBytes(free);
  final t = formatBytes(total);
  final fUnit = f.substring(f.lastIndexOf(' ') + 1);
  final tUnit = t.substring(t.lastIndexOf(' ') + 1);
  return fUnit == tUnit
      ? '${f.substring(0, f.lastIndexOf(' '))} / $t'
      : '$f / $t';
}

/// A thin bar showing how full a drive is; it turns to the error colour once
/// the drive is nearly full.
class _DriveUsageBar extends StatelessWidget {
  const _DriveUsageBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: fraction,
          minHeight: 5,
          color: fraction >= 0.9 ? cs.error : cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// Re-reads the drives (their free space changes as files are written) when the
/// list first appears and every 30 seconds while it stays on screen.
class _DriveListRefresher extends ConsumerStatefulWidget {
  const _DriveListRefresher();

  @override
  ConsumerState<_DriveListRefresher> createState() =>
      _DriveListRefresherState();
}

class _DriveListRefresherState extends ConsumerState<_DriveListRefresher> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  void _refresh() {
    unawaited(
      ref.read(externalStorageLocationsProvider.notifier).refreshSystemVolumes(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}