import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/features/browser/category_browser_screen.dart';
import 'package:vaultexplorer/features/browser/controllers/bookmark_navigation_request.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/models/file_category_presentation.dart';
import 'package:vaultexplorer/features/dashboard/widgets/category_shortcuts_editor.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

/// The drawer's CATEGORIES section: compact shortcuts that open a
/// [CategoryBrowserScreen] gathering one kind of file from every storage.
///
/// What it shows is the user's choice (see [CategoryShortcutsEditor]); hiding
/// a shortcut here never touches the category or any file. Long-pressing any
/// shortcut opens that editor in a bottom sheet.
class DrawerCategoriesSection extends ConsumerWidget {
  const DrawerCategoriesSection({
    super.key,
    required this.primaryLocalContainer,
    required this.currentVolId,
    required this.onOpenLocalStorage,
    required this.onSelectContainer,
    this.onOpenCategory,
    this.includeVaults = true,
  });

  final MountedContainer? primaryLocalContainer;
  final int? currentVolId;
  final VoidCallback? onOpenLocalStorage;
  final ValueChanged<MountedContainer>? onSelectContainer;
  final ValueChanged<FileCategory>? onOpenCategory;

  /// False in the decoy file manager, where vaults do not exist as far as the
  /// screen can tell: the shortcuts then gather only from phone storage and
  /// storage locations, and nothing mentions vaults.
  final bool includeVaults;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings),
    );
    if (!settings.categoryShortcutsEnabled) return const SizedBox.shrink();
    final hidden = settings.hiddenCategoryShortcuts.toSet();
    final categories = [
      for (final c in FileCategory.orderedFrom(settings.categoryShortcutOrder))
        if (!hidden.contains(c.storageKey)) c,
    ];
    if (categories.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            l10n.categoriesSectionTitle.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        for (final category in categories)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            leading: Icon(category.icon, color: cs.onSurfaceVariant),
            title: Text(
              category.label(l10n),
              style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            ),
            onTap: () => _open(context, category),
            onLongPress: () => _manage(context),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 1),
          child: Divider(),
        ),
      ],
    );
  }

  void _manage(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                context.l10n.categoryShortcutsTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            CategoryShortcutsEditor(showVaultOptions: includeVaults),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, FileCategory category) {
    final onOpen = onOpenCategory;
    if (onOpen != null) {
      Navigator.pop(context); // close the drawer
      onOpen(category);
      return;
    }

    // The drawer closes before the screen opens, and its own `ref` stops
    // working with it, so keep what the "go to location" callback needs.
    final providers = ProviderScope.containerOf(context);
    Navigator.pop(context); // close the drawer
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SkinAreaScope(
          area: SkinArea.files,
          child: CategoryBrowserScreen(
            category: category,
            primaryLocalContainer: primaryLocalContainer,
            includeVaults: includeVaults,
            onShowInFolder: (target, path) =>
                _showInFolder(providers, target, path),
          ),
        ),
      ),
    );
  }

  /// Opens [target] in the file manager at the folder holding [path], the way
  /// tapping a bookmark of that file would.
  void _showInFolder(
    ProviderContainer providers,
    MountedContainer target,
    String path,
  ) {
    if (target.volId != currentVolId) {
      if (target.isPrimaryLocalStorage && onOpenLocalStorage != null) {
        onOpenLocalStorage!.call();
      } else {
        onSelectContainer?.call(target);
      }
    }
    final dir = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : '';
    providers
        .read(bookmarkNavigationRequestsProvider.notifier)
        .request(target.volId, VaultBookmark(dir, isDir: true));
  }
}
