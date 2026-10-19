import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_tab_strip.dart';

/// Where a new tab should open: a container and, optionally, a directory in
/// it (null = the container root).
typedef BrowserNewTabChoice = ({MountedContainer container, String? path});

/// Bottom sheet listing every place a new tab can open: a copy of the current
/// location, each unlocked vault, this device's storage and any added
/// external storage. Returns the picked [BrowserNewTabChoice] (or null when
/// dismissed).
class BrowserNewTabSheet extends ConsumerWidget {
  final MountedContainer currentContainer;
  final String currentDirPath;
  final List<MountedContainer> mountedVaults;
  final MountedContainer? primaryLocalContainer;

  const BrowserNewTabSheet({
    super.key,
    required this.currentContainer,
    required this.currentDirPath,
    required this.mountedVaults,
    required this.primaryLocalContainer,
  });

  static Future<BrowserNewTabChoice?> show(
    BuildContext context, {
    required MountedContainer currentContainer,
    required String currentDirPath,
    required List<MountedContainer> mountedVaults,
    required MountedContainer? primaryLocalContainer,
  }) {
    return showModalBottomSheet<BrowserNewTabChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (_) => BrowserNewTabSheet(
        currentContainer: currentContainer,
        currentDirPath: currentDirPath,
        mountedVaults: mountedVaults,
        primaryLocalContainer: primaryLocalContainer,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final externals = ref.watch(externalStorageLocationsProvider);
    final local = primaryLocalContainer;

    void pick(MountedContainer c, [String? path]) {
      Navigator.pop<BrowserNewTabChoice>(context, (container: c, path: path));
    }

    final duplicateSubtitle = currentDirPath.isEmpty
        ? currentContainer.displayName
        : '${currentContainer.displayName} / $currentDirPath';

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                context.l10n.browserTabNew,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: BrowserLocationIcon(
                container: currentContainer,
                color: cs.primary,
                size: 24,
              ),
              title: Text(context.l10n.browserTabDuplicate),
              subtitle: Text(
                duplicateSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => pick(currentContainer, currentDirPath),
            ),
            const Divider(height: 16),
            for (final vault in mountedVaults)
              ListTile(
                leading: BrowserLocationIcon(
                  container: vault,
                  color: cs.primary,
                  size: 24,
                ),
                title: Text(
                  vault.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => pick(vault),
              ),
            if (local != null)
              ListTile(
                leading: BrowserLocationIcon(
                  container: local,
                  color: cs.primary,
                  size: 24,
                ),
                title: Text(
                  local.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(context.l10n.internalStorageSubtitle),
                onTap: () => pick(local),
              ),
            for (final loc in externals)
              ListTile(
                leading: Icon(Icons.sd_card_rounded, color: cs.secondary),
                title: Text(
                  loc.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  final notifier = ref.read(
                    externalStorageLocationsProvider.notifier,
                  );
                  final accessible = await notifier.isAccessible(loc);
                  if (!context.mounted) return;
                  if (!accessible) {
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
                  final container = notifier.resolveContainer(loc.volId);
                  if (container == null) {
                    Navigator.pop(context);
                    return;
                  }
                  pick(container);
                },
              ),
          ],
        ),
      ),
    );
  }
}
