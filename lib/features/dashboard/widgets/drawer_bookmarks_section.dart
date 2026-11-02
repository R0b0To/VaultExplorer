import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_settings.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_settings_resolver.dart';
import 'package:vaultexplorer/features/browser/controllers/bookmark_navigation_request.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_pins_bookmarks_controller.dart';
import 'package:vaultexplorer/features/browser/widgets/book_cover_support.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';

/// The navigation drawer's bookmarks, grouped by their vault or storage
/// location.
///
/// Vault groups come from the mounted vaults handed in by the drawer, so a
/// locked vault disappears and its marks can be dropped from memory. Phone
/// storage and configured locations use their device-local marks store.
///
/// A tap does what a tap on the vault itself does (switch to it) and then
/// asks the browser showing it to go to the bookmark; see
/// [bookmarkNavigationRequestsProvider].
///
/// A bookmarked book (.epub, .cbz, ...) shows its cover in place of the generic
/// file icon, as it does in the file manager; see [_DrawerBookCover].
class DrawerBookmarksSection extends ConsumerStatefulWidget {
  /// The unlocked vaults, in the order the drawer lists them.
  final List<MountedContainer> vaults;

  /// Phone storage and configured storage locations, in drawer order.
  final List<MountedContainer> storageLocations;

  /// The container the browser in front is showing, if any.
  final int? currentVolId;

  /// Opens a container exactly as tapping its drawer location does.
  final ValueChanged<MountedContainer>? onSelectContainer;

  /// Set only while the file manager is open with tabs.
  final ValueChanged<MountedContainer>? onOpenInNewTab;

  /// Opens phone storage through its access and permission checks.
  final VoidCallback? onOpenLocalStorage;

  const DrawerBookmarksSection({
    super.key,
    required this.vaults,
    this.storageLocations = const [],
    this.currentVolId,
    this.onSelectContainer,
    this.onOpenInNewTab,
    this.onOpenLocalStorage,
  });

  @override
  ConsumerState<DrawerBookmarksSection> createState() =>
      _DrawerBookmarksSectionState();
}

class _DrawerBookmarksSectionState
    extends ConsumerState<DrawerBookmarksSection> {
  /// Every source whose marks are available in the drawer. Storage locations
  /// keep their marks in the device-local store, keyed by their own URI.
  List<MountedContainer> get _containers => [
    ...widget.vaults,
    ...widget.storageLocations,
  ];

  /// Asks for the marks of every container that hasn't loaded them. Idempotent
  /// (a load already in flight is shared), and asks the provider rather than
  /// remembering: an auto-disposed provider loads its stored marks again when
  /// needed.
  void _requestLoads(List<MountedContainer> containers) {
    final pending = [
      for (final v in containers)
        if (!ref
            .read(fileBrowserPinsBookmarksProvider(v.volId).notifier)
            .isLoaded)
          v,
    ];
    if (pending.isEmpty) return;
    // After this frame: loading changes provider state, which isn't allowed
    // while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final vault in pending) {
        ref
            .read(fileBrowserPinsBookmarksProvider(vault.volId).notifier)
            .ensureLoaded(vault);
      }
    });
  }

  void _open(
    BuildContext context,
    MountedContainer vault,
    VaultBookmark bookmark, {
    required bool inNewTab,
  }) {
    final requests = ref.read(bookmarkNavigationRequestsProvider.notifier);
    Navigator.pop(context); // close the drawer
    if (inNewTab && widget.onOpenInNewTab != null) {
      // Open the tab first: it becomes the active one, so a browser that is
      // already showing this container leaves the request for the new tab.
      widget.onOpenInNewTab!(vault);
    } else if (vault.volId != widget.currentVolId) {
      if (vault.isPrimaryLocalStorage && widget.onOpenLocalStorage != null) {
        widget.onOpenLocalStorage!.call();
      } else {
        widget.onSelectContainer?.call(vault);
      }
    }
    // Same container already in front: its browser takes the request at once.
    requests.request(vault.volId, bookmark);
  }

  void _manage(BuildContext context, MountedContainer vault) {
    final navigator = Navigator.of(context);
    navigator.pop(); // close the drawer
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SkinAreaScope(
          area: SkinArea.settings,
          child: FileManagerBookmarksScreen(container: vault),
        ),
      ),
    );
  }

  void _showMenu(
    BuildContext tileContext,
    MountedContainer vault,
    VaultBookmark bookmark,
  ) {
    HapticFeedback.mediumImpact();
    final cs = Theme.of(tileContext).colorScheme;
    final overlay =
        Overlay.of(tileContext).context.findRenderObject() as RenderBox?;
    final box = tileContext.findRenderObject() as RenderBox?;
    if (overlay == null || box == null) return;
    final position = box.localToGlobal(box.size.center(Offset.zero));
    final notifier = ref.read(
      fileBrowserPinsBookmarksProvider(vault.volId).notifier,
    );
    showMenu<String>(
      context: tileContext,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        if (widget.onOpenInNewTab != null)
          PopupMenuItem(
            value: 'new_tab',
            child: Row(
              children: [
                Icon(Icons.tab_rounded, size: 20, color: cs.onSurface),
                const SizedBox(width: 12),
                Text(tileContext.l10n.browserTabOpenInNewTab),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: cs.error),
              const SizedBox(width: 12),
              Text(
                tileContext.l10n.removeFromBookmarks,
                style: TextStyle(color: cs.error),
              ),
            ],
          ),
        ),
      ],
    ).then((action) {
      if (action == 'remove') {
        notifier.removeBookmark(vault, bookmark.path);
      } else if (action == 'new_tab' && tileContext.mounted) {
        _open(tileContext, vault, bookmark, inNewTab: true);
      }
    });
  }

  /// Whether [bookmark] is a book whose cover can stand in for its icon.
  static bool _showsCover(VaultBookmark bookmark) =>
      !bookmark.isDir && isBookWithCover(bookmark.name);

  /// The thumbnail settings that apply to [vault]'s files, exactly as its file
  /// browser resolves them (the vault's own override, else the app-wide
  /// default; Local Storage has a slot of its own), or null until they have
  /// loaded.
  ///
  /// Waiting matters, not just politeness: the cache mode decides whether a
  /// cover is written to disk at all, and a vault whose owner turned that off
  /// must not get one because its settings had not arrived yet.
  ThumbnailSettings? _coverSettingsFor(MountedContainer vault) {
    final state = ref.watch(
      fileManagerToolbarSettingsProvider(
        vault.isLocalStorage ? null : vault.uri,
      ),
    );
    if (state.loading) return null;
    return resolveThumbnailSettings(
      config: state.config,
      isLocalStorage: vault.isLocalStorage,
      record: state.record,
    );
  }

  @override
  Widget build(BuildContext context) {
    final containers = _containers;
    _requestLoads(containers);

    // Watched here (not in each group) so the section title knows whether any
    // group has something to show.
    final groups = <({MountedContainer vault, VaultMarks marks})>[
      for (final vault in containers)
        (
          vault: vault,
          marks: ref.watch(fileBrowserPinsBookmarksProvider(vault.volId)),
        ),
    ].where((g) => g.marks.bookmarks.isNotEmpty).toList();

    if (groups.isEmpty) return const SizedBox.shrink();

    final collapsedBookmarkGroupUris = ref.watch(
      fileManagerToolbarSettingsProvider(null).select(
        (settings) => settings.config.collapsedBookmarkGroupUris,
      ),
    );
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 1),
          child: Divider(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text(
            context.l10n.drawerBookmarksSectionTitle.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        for (final group in groups)
          _group(
            context,
            group.vault,
            group.marks.bookmarks,
            collapsed: collapsedBookmarkGroupUris.contains(group.vault.uri),
          ),
      ],
    );
  }

  Widget _group(
    BuildContext context,
    MountedContainer vault,
    List<VaultBookmark> bookmarks, {
    required bool collapsed,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final skin = FileManagerSkinScope.of(context);
    // Watched here, not in the tiles' builders below: those run outside this
    // State's build, where Riverpod does not allow `ref.watch`. Looked up only
    // for an expanded group that has a book in it, so a drawer of plain files
    // and folders touches no thumbnail setting at all.
    final coverSettings = !collapsed && bookmarks.any(_showsCover)
        ? _coverSettingsFor(vault)
        : null;
    return Column(
      key: ValueKey('drawer_bookmarks_${vault.volId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => unawaited(
            ref
                .read(fileManagerToolbarSettingsProvider(null).notifier)
                .toggleBookmarkGroupCollapsed(vault.uri),
          ),
          onLongPress: () => _manage(context, vault),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 2, 4),
            child: Row(
              children: [
                Icon(
                  collapsed
                      ? Icons.chevron_right_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    vault.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          for (final bookmark in bookmarks)
            Builder(
              builder: (tileContext) {
                final isDir = bookmark.isDir;
                final name = bookmark.name;
                final icon = Icon(
                  isDir ? skin.folderIcon : skin.fileIcon(name),
                  size: 20,
                  color: isDir
                      ? skin.folderIconColor(cs)
                      : skin.fileIconColor(cs, name),
                );
                return ListTile(
                  key: ValueKey(
                    'drawer_bookmark_${vault.volId}_${bookmark.path}',
                  ),
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  contentPadding: const EdgeInsets.only(left: 28, right: 12),
                  leading: coverSettings != null && _showsCover(bookmark)
                      ? _DrawerBookCover(
                          container: vault,
                          filePath: bookmark.path,
                          settings: coverSettings,
                          fallback: icon,
                        )
                      : icon,
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: bookmark.parentPath.isEmpty
                      ? null
                      : Text(
                          bookmark.parentPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                  onTap: () =>
                      _open(tileContext, vault, bookmark, inNewTab: false),
                  onLongPress: () => _showMenu(tileContext, vault, bookmark),
                );
              },
            ),
      ],
    );
  }
}

/// A bookmarked book's cover, in the slot a bookmark's file icon normally
/// fills.
///
/// Loads through the same path and cache as the file manager's tiles
/// ([loadBookCoverThumbnail]) and honours the same per-vault thumbnail
/// settings, so a cover the file manager cached at this quality is reused
/// here instead of reopening the book. Until it arrives, and for a book with
/// no cover, it shows [fallback]: the icon the bookmark has always had, in the
/// same place, so a tile without a cover looks exactly as before.
class _DrawerBookCover extends ConsumerWidget {
  /// Fits the drawer's dense tile (48 dp one line, 64 dp with a subtitle) and
  /// is about the proportions of a book.
  static const double _width = 28;
  static const double _height = 40;

  final MountedContainer container;
  final String filePath;
  final ThumbnailSettings settings;
  final Widget fallback;

  const _DrawerBookCover({
    required this.container,
    required this.filePath,
    required this.settings,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final bookApi = ref.read(vaultBookApiProvider);
    final quality = settings.quality;
    final cacheMode = settings.cacheMode;

    // Left-aligned like the icon it replaces, so the tile's text does not move.
    final icon = SizedBox(
      width: _width,
      height: _height,
      child: Align(alignment: Alignment.centerLeft, child: fallback),
    );

    return SizedBox(
      width: _width,
      height: _height,
      child: AsyncThumbnail(
        key: ValueKey('drawer_book:$filePath'),
        container: container,
        filePath: filePath,
        cache: ThumbnailConcurrency.inFlightThumbnails,
        limiter: ThumbnailConcurrency.imageLimiter,
        quality: quality,
        fetchFn: (c, p) async => (await loadBookCoverThumbnail(
          thumbnailCache: thumbnailCache,
          bookApi: bookApi,
          container: c,
          path: p,
          mode: cacheMode,
          quality: quality,
        )).bytes,
        debounce: const Duration(milliseconds: 100),
        syncLookup: () => thumbnailCache.peekMemory(container, filePath, quality),
        cacheHeight: quality.scaledSize(180),
        imageBuilder: (context, bytes, cacheHeight) => ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: DecoratedBox(
            // A hairline so a pale cover does not melt into the drawer.
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.6),
                width: 0.5,
              ),
            ),
            child: Image.memory(
              bytes,
              width: _width,
              height: _height,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              cacheHeight: cacheHeight,
              errorBuilder: (_, _, _) => icon,
            ),
          ),
        ),
        loadingBuilder: (context) => icon,
        errorBuilder: (context) => icon,
      ),
    );
  }
}
