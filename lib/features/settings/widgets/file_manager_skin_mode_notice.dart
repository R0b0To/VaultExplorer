import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';

/// Explains when the File Manager is using its own skin instead of App Skin.
class FileManagerSkinModeNotice extends ConsumerWidget {
  const FileManagerSkinModeNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSkin = ref.watch(appSkinSettingsProvider);
    if (appSkin.fileManagerFollowsAppSkin) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.info_outline_rounded,
                color: colorScheme.primary,
              ),
              title: Text(
                context.l10n.skinFileManagerIndependentTitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                context.l10n.skinFileManagerIndependentDescription,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => ref
                    .read(appSkinSettingsProvider.notifier)
                    .setFileManagerFollowsAppSkin(true),
                icon: const Icon(Icons.palette_outlined),
                label: Text(context.l10n.skinFollowAppSkin),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
