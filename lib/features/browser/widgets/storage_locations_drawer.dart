import 'package:vaultexplorer/core/utils/local_storage_name.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/dashboard/widgets/app_navigation_drawer.dart'
    show DrawerFooterStrip, DriveListRefresher, DriveUsageBar, driveFreeOfTotal;
import 'package:vaultexplorer/features/dashboard/widgets/drawer_categories_section.dart';
import 'package:vaultexplorer/features/dashboard/widgets/drawer_group.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
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

class StorageLocationsDrawer extends ConsumerWidget {
  final int activeVolId;
  final MountedContainer? primaryLocalContainer;
  final ValueChanged<MountedContainer> onSelected;
  final ValueChanged<FileCategory>? onOpenCategory;

  const StorageLocationsDrawer({
    super.key,
    required this.activeVolId,
    required this.primaryLocalContainer,
    required this.onSelected,
    this.onOpenCategory,
  });

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

  void _promptRename(BuildContext context, WidgetRef ref, ExternalStorageLocation loc) {
    final ctrl = TextEditingController(text: loc.displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.renameStorageLocationTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.l10n.displayNameTitle,
          ),
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
    final isCurrent = activeVolId == loc.volId;
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
              }
            },
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
  }

  void _showLocationContextMenu(
    BuildContext context,
    WidgetRef ref,
    ExternalStorageLocation loc,
    Offset tapPosition,
  ) {
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
      if (action == 'rename') {
        _promptRename(context, ref, loc);
      } else if (action == 'remove') {
        _confirmRemove(context, ref, loc);
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final externals = ref.watch(externalStorageLocationsProvider);
    final primary = primaryLocalContainer;

    // Same structure as the main side menu: grouped rows in a scrolling list
    // and the Settings button pinned in the shared footer strip.
    return Drawer(
      child: SafeArea(
        left: false,
        right: false,
        child: MediaQuery.removePadding(
          context: context,
          removeLeft: true,
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
                    DrawerGroup(children: [
                      // Keeps the drives' free space current while the list
                      // is on screen.
                      if (PlatformFeatures.isDesktop) const DriveListRefresher(),
                      if (primary != null)
                        ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          selected: activeVolId == kDecoyLocalVolId,
                          selectedTileColor:
                              cs.secondaryContainer.withValues(alpha: 0.5),
                          leading: Icon(
                            PlatformFeatures.localStorageIcon,
                            color: activeVolId == kDecoyLocalVolId
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          title: Text(
                            localStorageDisplayName(
                              context.l10n.localStorageCardTitle,
                            ),
                            style: textTheme.bodyLarge?.copyWith(
                              fontWeight: activeVolId == kDecoyLocalVolId
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            if (activeVolId == kDecoyLocalVolId) return;
                            onSelected(primary);
                          },
                        ),
                      for (final loc in externals) _buildExternalTile(context, ref, loc),

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
                          onTap: () => _addLocation(context, ref),
                        ),
                    ]),

                    // Category shortcuts: the same ones the real drawer has,
                    // over phone storage and storage locations only.
                    DrawerCategoriesSection(
                      primaryLocalContainer: primary,
                      currentVolId: activeVolId,
                      onOpenLocalStorage:
                          primary == null ? null : () => onSelected(primary),
                      onSelectContainer: onSelected,
                      onOpenCategory: onOpenCategory,
                      includeVaults: false,
                    ),
                  ],
                ),
              ),
              // Decoy Settings (only File Manager / Interface settings, no
              // vault security), in the same footer as the main menu.
              DrawerFooterStrip(
                onSettings: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SkinAreaScope(
                        area: SkinArea.settings,
                        child: const FileManagerToolbarSettingsScreen(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExternalTile(
    BuildContext context,
    WidgetRef ref,
    ExternalStorageLocation loc,
  ) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCurrent = activeVolId == loc.volId;
    return Builder(
      builder: (tileContext) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // System-discovered volumes have no context actions, so don't leave
          // a long-press/secondary-tap gesture that opens an empty menu.
          onSecondaryTapDown: loc.isSystemVolume
              ? null
              : (details) => _showLocationContextMenu(
                  context,
                  ref,
                  loc,
                  details.globalPosition,
                ),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            selected: isCurrent,
            selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            // One block: icon, name and the free / total size on a single
            // row, with the usage bar underneath (as in the main menu).
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      _iconForStorage(loc.path),
                      size: 20,
                      color: isCurrent ? cs.primary : cs.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        loc.displayName,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (loc.freeBytes != null && loc.totalBytes != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        driveFreeOfTotal(loc.freeBytes!, loc.totalBytes!),
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                if (loc.usedFraction != null)
                  DriveUsageBar(fraction: loc.usedFraction!),
              ],
            ),
            onLongPress: loc.isSystemVolume
                ? null
                : touchOnlyLongPress(() {
                    final box = tileContext.findRenderObject() as RenderBox?;
                    final pos = box != null
                        ? box.localToGlobal(box.size.center(Offset.zero))
                        : Offset.zero;
                    _showLocationContextMenu(context, ref, loc, pos);
                  }),
            onTap: () async {
              if (isCurrent) {
                Navigator.pop(context);
                return;
              }
              // SAF locations carry their own persisted grant; only raw paths
              // (auto-discovered SD card / USB) need file access.
              if (!loc.resolvedUri.startsWith('content://') &&
                  !await _ensureAllFilesAccess(context, ref)) {
                return;
              }
              if (!context.mounted) return;
              final isAccessible = await ref
                  .read(externalStorageLocationsProvider.notifier)
                  .isAccessible(loc);
              if (!context.mounted) return;
              if (!isAccessible) {
                Navigator.pop(context);
                showAppSnackBar(
                  context,
                  message: context.l10n.storageLocationUnavailable(
                    loc.displayName,
                  ),
                  tone: AppBannerTone.warning,
                );
                return;
              }
              Navigator.pop(context);
              onSelected(
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
    );
  }

  Future<void> _addLocation(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(externalStorageLocationsProvider.notifier);
    ExternalStorageLocation? loc;
    try {
      loc = await ref
          .read(sessionLockControllerProvider)
          .withLockSuppression(() => notifier.promptAndAddLocation());
    } on SelfReferentialStorageException {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        message: context.l10n.storageLocationSelfReferenceError,
        tone: AppBannerTone.warning,
      );
      return;
    }
    if (!context.mounted) return;
    if (loc != null) {
      Navigator.pop(context);
      onSelected(
        buildExternalStorageContainer(
          rootPath: loc.resolvedUri,
          displayName: loc.displayName,
          volId: loc.volId,
        ),
      );
    }
  }
}
