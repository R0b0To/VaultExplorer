import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';

class StorageLocationsDrawer extends ConsumerWidget {
  final int activeVolId;
  final MountedContainer? primaryLocalContainer;
  final ValueChanged<MountedContainer> onSelected;

  const StorageLocationsDrawer({
    super.key,
    required this.activeVolId,
    required this.primaryLocalContainer,
    required this.onSelected,
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
    return Icons.sd_card_rounded;
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final externals = ref.watch(externalStorageLocationsProvider);
    final primary = primaryLocalContainer;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  if (primary != null)
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      selected: activeVolId == kDecoyLocalVolId,
                      selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                      leading: Icon(
                        Icons.phone_android_rounded,
                        color: activeVolId == kDecoyLocalVolId ? cs.primary : cs.onSurfaceVariant,
                      ),
                      title: Text(
                        context.l10n.localStorageCardTitle,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: activeVolId == kDecoyLocalVolId ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        if (activeVolId == kDecoyLocalVolId) return;
                        onSelected(primary);
                      },
                    ),

                  for (final loc in externals) ...[
                    Builder(
                      builder: (tileContext) {
                        final isCurrent = activeVolId == loc.volId;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onSecondaryTapDown: (details) =>
                              _showLocationContextMenu(context, ref, loc, details.globalPosition),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                            selected: isCurrent,
                            selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.5),
                            leading: Icon(
                              _iconForStorage(loc.path),
                              color: isCurrent ? cs.primary : cs.secondary,
                            ),
                            title: Text(
                              loc.displayName,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
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
                              if (isCurrent) {
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
                              onSelected(buildExternalStorageContainer(
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
                        onSelected(buildExternalStorageContainer(
                          rootPath: loc.resolvedUri,
                          displayName: loc.displayName,
                          volId: loc.volId,
                        ));
                      }
                    },
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 1),
                    child: Divider(),
                  ),

                  // Decoy Settings (Only shows File Manager / Interface settings, no vault security)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    leading: Icon(Icons.settings, color: cs.onSurfaceVariant),
                    title: Text(
                      context.l10n.settingsMenuItem,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FileManagerToolbarSettingsScreen(isLocalStorage: true),
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