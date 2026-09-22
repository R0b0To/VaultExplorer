import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

class StorageLocationsSheet extends ConsumerWidget {
  final int activeVolId;
  final MountedContainer primaryLocalContainer;
  final ValueChanged<MountedContainer> onSelected;

  const StorageLocationsSheet({
    super.key,
    required this.activeVolId,
    required this.primaryLocalContainer,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required int activeVolId,
    required MountedContainer primaryLocalContainer,
    required ValueChanged<MountedContainer> onSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (_) => StorageLocationsSheet(
        activeVolId: activeVolId,
        primaryLocalContainer: primaryLocalContainer,
        onSelected: onSelected,
      ),
    );
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.removeStorageLocationTitle),
        content: Text(context.l10n.removeStorageLocationConfirm(loc.displayName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          FilledButton(
            onPressed: () {
              ref.read(externalStorageLocationsProvider.notifier).removeLocation(loc.id);
              Navigator.pop(ctx);
            },
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final externals = ref.watch(externalStorageLocationsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                context.l10n.storageLocationsTitle,
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),

            // 1. Primary Internal Storage
            ListTile(
              leading: Icon(Icons.phone_android_rounded, color: cs.primary),
              title: Text(
                primaryLocalContainer.displayName,
                style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                context.l10n.internalStorageSubtitle,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: activeVolId == kDecoyLocalVolId
                  ? Icon(Icons.check_circle_rounded, color: cs.primary)
                  : null,
              onTap: () {
                Navigator.pop(context);
                onSelected(primaryLocalContainer);
              },
            ),

            // 2. Added External Storages
            for (final loc in externals) ...[
              ListTile(
                leading: Icon(Icons.sd_card_rounded, color: cs.secondary),
                title: Text(
                  loc.displayName,
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  loc.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (activeVolId == loc.volId)
                      Icon(Icons.check_circle_rounded, color: cs.primary),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
                      onSelected: (action) {
                        if (action == 'rename') {
                          _promptRename(context, ref, loc);
                        } else if (action == 'remove') {
                          _confirmRemove(context, ref, loc);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'rename', child: Text(context.l10n.rename)),
                        PopupMenuItem(value: 'remove', child: Text(context.l10n.remove)),
                      ],
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  onSelected(buildExternalStorageContainer(
                    rootPath: loc.resolvedUri,
                    displayName: loc.displayName,
                    volId: loc.volId,
                  ));
                },
              ),
            ],

            const Divider(),

            // 3. Add Storage Location
            ListTile(
              leading: Icon(Icons.add_to_drive_rounded, color: cs.primary),
              title: Text(
                context.l10n.addStorageLocationTitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                context.l10n.addStorageLocationSubtitle,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              onTap: () async {
                final notifier = ref.read(externalStorageLocationsProvider.notifier);
                final loc = await notifier.promptAndAddLocation();
                if (!context.mounted) return;
                if (loc != null) {
                  Navigator.pop(context);
                  onSelected(buildExternalStorageContainer(
                    rootPath: loc.resolvedUri,
                    displayName: loc.displayName,
                    volId: loc.volId,
                  ));
                } else {
                  showAppSnackBar(
                    context,
                    message: context.l10n.storageLocationUnresolvedError,
                    tone: AppBannerTone.warning,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}