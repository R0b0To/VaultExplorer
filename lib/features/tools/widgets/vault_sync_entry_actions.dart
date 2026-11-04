import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/features/browser/file_open_dispatch.dart';
import 'package:vaultexplorer/features/browser/viewer/html_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_screen.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_target_style.dart';

/// Plain-text extensions the in-app text editor opens directly. Same set the
/// Duplicate Finder's preview uses.
const Set<String> _kTextExtensions = {
  'txt',
  'md',
  'markdown',
  'csv',
  'json',
  'xml',
  'log',
  'yaml',
  'yml',
  'dart',
  'js',
  'css',
};

/// The container path of [relativePath] on [side] (the side's own folder
/// joined with the entry's path relative to it).
String vaultSyncAbsPath(VaultSyncSide side, String relativePath) {
  final root = side.relativePath;
  if (root.isEmpty) return relativePath;
  if (relativePath.isEmpty) return root;
  return '$root/$relativePath';
}

/// Opens one copy of a file in the app's own viewers (media, PDF, HTML, text),
/// or hands it to a system app for anything else. Decrypted bytes for a vault
/// side are streamed into the viewer, never written out unencrypted.
Future<void> openVaultSyncFile(
  BuildContext context,
  WidgetRef ref, {
  required VaultSyncSide side,
  required String relativePath,
  required String name,
}) async {
  final container = side.container;
  final path = vaultSyncAbsPath(side, relativePath);
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

  Widget? viewer;
  final action = decideFileOpenAction(
    ext: ext,
    extensionPreference: null,
    needsSystemAppForLocal: false,
    isSupportedMedia: MediaViewerConstants.isSupported(name),
  );
  if (action is OpenInMediaViewer) {
    viewer = MediaViewerScreen(
      container: container,
      mediaFiles: [path],
      initialIndex: 0,
      thumbnailCacheMode: ThumbnailCacheMode.appCache,
    );
  } else if (action is OpenInPdfViewer) {
    viewer = PdfViewerScreen(container: container, filePath: path);
  } else if (action is OpenInHtmlViewer) {
    viewer = HtmlViewerScreen(container: container, filePath: path);
  } else if (action is OpenInEditor || _kTextExtensions.contains(ext)) {
    viewer = TextEditorScreen(container: container, filePath: path);
  }

  if (viewer != null) {
    final page = viewer;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    return;
  }

  try {
    final ok = await ref
        .read(vaultFileIoApiProvider)
        .openWithApp(container, path);
    if (!ok && context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.vaultSyncOpenFailedMessage(name),
        tone: AppBannerTone.error,
      );
    }
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.vaultSyncOpenFailedMessage(name),
        tone: AppBannerTone.error,
      );
    }
  }
}

/// Asks for confirmation and permanently deletes [entries] from one side
/// (or both), reporting the outcome in a snackbar.
///
/// Returns true if anything was deleted, so callers know to reload.
Future<bool> confirmAndDeleteVaultSyncEntries(
  BuildContext context,
  WidgetRef ref, {
  required List<VaultDiffEntry> entries,
  required bool fromLeft,
  required bool fromRight,
}) async {
  if (entries.isEmpty || (!fromLeft && !fromRight)) return false;
  final notifier = ref.read(vaultSyncProvider.notifier);
  final state = ref.read(vaultSyncProvider);
  final left = state.left;
  final right = state.right;
  if (left == null || right == null) return false;

  final blocked =
      (fromLeft && left.container.readOnly) ||
      (fromRight && right.container.readOnly);
  if (blocked) {
    showAppSnackBar(
      context,
      message: context.l10n.readOnlyCantDelete,
      tone: AppBannerTone.error,
    );
    return false;
  }

  final names = vaultSyncNamesOf(left, right, context.l10n);
  final String where;
  if (fromLeft && fromRight) {
    where = context.l10n.vaultSyncDeleteBothSidesLabel(names.left, names.right);
  } else {
    where = fromLeft ? names.left : names.right;
  }
  final confirmed = await showAppConfirmDialog(
    context,
    title: context.l10n.deleteItemsTitle(entries.length),
    message: context.l10n.vaultSyncDeleteConfirmMessage(where),
    confirmLabel: context.l10n.delete,
    isDestructive: true,
  );
  if (!confirmed || !context.mounted) return false;

  final l10n = context.l10n;
  var deleted = 0;
  var failed = 0;
  if (fromLeft) {
    final r = await notifier.deleteNow(
      fromLeft: true,
      entries: entries.where((e) => e.existsOnLeft).toList(),
      l10n: l10n,
    );
    deleted += r.deleted;
    failed += r.failed;
  }
  if (fromRight) {
    final r = await notifier.deleteNow(
      fromLeft: false,
      entries: entries.where((e) => e.existsOnRight).toList(),
      l10n: l10n,
    );
    deleted += r.deleted;
    failed += r.failed;
  }
  if (context.mounted) {
    showAppSnackBar(
      context,
      message: failed == 0
          ? l10n.vaultSyncDeleteDoneMessage(deleted)
          : l10n.vaultSyncDeletePartialMessage(deleted, failed),
      tone: failed == 0 ? AppBannerTone.success : AppBannerTone.warning,
    );
  }
  return deleted > 0;
}

/// Copies [entries] to the other side immediately and reports the outcome.
/// Returns true when it ran without a failed operation.
Future<bool> copyVaultSyncEntriesNow(
  BuildContext context,
  WidgetRef ref, {
  required List<VaultDiffEntry> entries,
  required bool toRight,
}) async {
  final l10n = context.l10n;
  final failed = await ref
      .read(vaultSyncProvider.notifier)
      .copyNow(toRight: toRight, entries: entries, l10n: l10n);
  if (context.mounted) {
    showAppSnackBar(
      context,
      message: failed == 0
          ? l10n.vaultSyncCopyDoneMessage
          : l10n.vaultSyncCopyFailedMessage,
      tone: failed == 0 ? AppBannerTone.success : AppBannerTone.error,
    );
  }
  return failed == 0;
}

/// Bottom sheet with everything the person can do with one entry: see both
/// copies (size and full date + time), open it, jump to its folder, copy it
/// across immediately, or delete it from either or both sides.
///
/// [onOpenFolder] (folders) and [onShowInFolder] (files and folders) are
/// provided by the caller because what "opening a folder" means depends on
/// where the sheet was shown; leave one null to hide that action. [onChanged]
/// runs after a copy or delete, so the caller can reload its list.
Future<void> showVaultSyncEntrySheet(
  BuildContext context,
  WidgetRef ref, {
  required VaultDiffEntry entry,
  required VaultSyncSide left,
  required VaultSyncSide right,
  required VaultSyncNames names,
  VoidCallback? onOpenFolder,
  VoidCallback? onShowInFolder,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VaultSyncEntrySheet(
      hostContext: context,
      ref: ref,
      entry: entry,
      left: left,
      right: right,
      names: names,
      onOpenFolder: onOpenFolder,
      onShowInFolder: onShowInFolder,
      onChanged: onChanged,
    ),
  );
}

class _VaultSyncEntrySheet extends StatelessWidget {
  /// The screen that opened the sheet. Actions run against it (not the
  /// sheet's own context) because the sheet closes before they start.
  final BuildContext hostContext;
  final WidgetRef ref;
  final VaultDiffEntry entry;
  final VaultSyncSide left;
  final VaultSyncSide right;
  final VaultSyncNames names;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onShowInFolder;
  final VoidCallback? onChanged;

  const _VaultSyncEntrySheet({
    required this.hostContext,
    required this.ref,
    required this.entry,
    required this.left,
    required this.right,
    required this.names,
    this.onOpenFolder,
    this.onShowInFolder,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final notifier = ref.read(vaultSyncProvider.notifier);

    // A file-versus-folder mismatch has a different type on each side.
    final leftIsFile = entry.existsOnLeft && !entry.isDir;
    final rightIsFile =
        entry.existsOnRight && (entry.typeMismatch ? entry.isDir : !entry.isDir);
    final canOpenFolder =
        entry.isDir && !entry.typeMismatch && onOpenFolder != null;

    void closeThen(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    Future<void> deleteFrom({required bool l, required bool r}) async {
      final changed = await confirmAndDeleteVaultSyncEntries(
        hostContext,
        ref,
        entries: [entry],
        fromLeft: l,
        fromRight: r,
      );
      if (changed) onChanged?.call();
    }

    Future<void> copyNow({required bool toRight}) async {
      await copyVaultSyncEntriesNow(
        hostContext,
        ref,
        entries: [entry],
        toRight: toRight,
      );
      onChanged?.call();
    }

    final tiles = <Widget>[
      if (canOpenFolder)
        SheetOptionTile(
          icon: Icons.folder_open_rounded,
          title: context.l10n.vaultSyncOpenFolderAction,
          subtitle: context.l10n.vaultSyncOpenFolderSubtitle,
          onTap: () => closeThen(onOpenFolder!),
        ),
      if (leftIsFile && rightIsFile) ...[
        SheetOptionTile(
          icon: Icons.open_in_new_rounded,
          title: context.l10n.vaultSyncOpenCopyAction(names.left),
          onTap: () => closeThen(
            () => openVaultSyncFile(
              hostContext,
              ref,
              side: left,
              relativePath: entry.relativePath,
              name: entry.name,
            ),
          ),
        ),
        SheetOptionTile(
          icon: Icons.open_in_new_rounded,
          title: context.l10n.vaultSyncOpenCopyAction(names.right),
          onTap: () => closeThen(
            () => openVaultSyncFile(
              hostContext,
              ref,
              side: right,
              relativePath: entry.relativePath,
              name: entry.name,
            ),
          ),
        ),
      ] else if (leftIsFile || rightIsFile)
        SheetOptionTile(
          icon: Icons.open_in_new_rounded,
          title: context.l10n.vaultSyncOpenAction,
          subtitle: leftIsFile ? names.left : names.right,
          onTap: () => closeThen(
            () => openVaultSyncFile(
              hostContext,
              ref,
              side: leftIsFile ? left : right,
              relativePath: entry.relativePath,
              name: entry.name,
            ),
          ),
        ),
      if (onShowInFolder != null)
        SheetOptionTile(
          icon: Icons.drive_file_move_rounded,
          title: context.l10n.vaultSyncShowInFolderAction,
          subtitle: context.l10n.vaultSyncShowInFolderSubtitle,
          onTap: () => closeThen(onShowInFolder!),
        ),
      if (notifier.canApply(entry, EntryAction.copyToRight))
        SheetOptionTile(
          icon: Icons.arrow_forward_rounded,
          title: context.l10n.vaultSyncCopyNowToAction(names.right),
          onTap: () => closeThen(() => copyNow(toRight: true)),
        ),
      if (notifier.canApply(entry, EntryAction.copyToLeft))
        SheetOptionTile(
          icon: Icons.arrow_back_rounded,
          title: context.l10n.vaultSyncCopyNowToAction(names.left),
          onTap: () => closeThen(() => copyNow(toRight: false)),
        ),
      if (notifier.canApply(entry, EntryAction.deleteLeft))
        SheetOptionTile(
          icon: Icons.delete_outline_rounded,
          iconColor: cs.error,
          title: context.l10n.vaultSyncDeleteFromAction(names.left),
          onTap: () => closeThen(() => deleteFrom(l: true, r: false)),
        ),
      if (notifier.canApply(entry, EntryAction.deleteRight))
        SheetOptionTile(
          icon: Icons.delete_outline_rounded,
          iconColor: cs.error,
          title: context.l10n.vaultSyncDeleteFromAction(names.right),
          onTap: () => closeThen(() => deleteFrom(l: false, r: true)),
        ),
      if (notifier.canApply(entry, EntryAction.deleteLeft) &&
          notifier.canApply(entry, EntryAction.deleteRight))
        SheetOptionTile(
          icon: Icons.delete_forever_rounded,
          iconColor: cs.error,
          title: context.l10n.vaultSyncDeleteFromBothAction,
          onTap: () => closeThen(() => deleteFrom(l: true, r: true)),
        ),
    ];

    return AppBottomSheet(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    entry.isDir ? Icons.folder_rounded : iconForFile(entry.name),
                    color: entry.isDir ? cs.secondary : colorForFile(entry.name),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (entry.relativePath != entry.name)
                          Text(
                            entry.relativePath,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SideDetailsCard(entry: entry, names: names),
            const SizedBox(height: 8),
            ...tiles,
          ],
        ),
      ),
    );
  }
}

/// Both copies of an entry: which storage each lives in, how big it is and
/// the full date and time it was last modified, with the newer one marked.
class _SideDetailsCard extends StatelessWidget {
  final VaultDiffEntry entry;
  final VaultSyncNames names;

  const _SideDetailsCard({required this.entry, required this.names});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            context,
            name: names.left,
            present: entry.existsOnLeft,
            isDirOnSide: entry.isDir,
            sizeBytes: entry.leftSizeBytes,
            modifiedSecs: entry.leftModifiedSecs,
            isNewer: entry.status == VaultDiffStatus.leftNewer,
          ),
          const SizedBox(height: 10),
          _row(
            context,
            name: names.right,
            present: entry.existsOnRight,
            isDirOnSide: entry.typeMismatch ? !entry.isDir : entry.isDir,
            sizeBytes: entry.rightSizeBytes,
            modifiedSecs: entry.rightModifiedSecs,
            isNewer: entry.status == VaultDiffStatus.rightNewer,
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String name,
    required bool present,
    required bool isDirOnSide,
    required int? sizeBytes,
    required int? modifiedSecs,
    required bool isNewer,
  }) {
    final cs = context.colors;
    final textTheme = context.typography;
    final String detail;
    if (!present) {
      detail = context.l10n.vaultSyncDetailsNotOnThisSide;
    } else {
      final parts = <String>[
        if (isDirOnSide)
          context.l10n.vaultSyncDetailsFolder
        else if (sizeBytes != null)
          formatBytes(sizeBytes),
        formatEntryDateTime(modifiedSecs ?? 0, context),
      ];
      detail = parts.join(' · ');
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
              Text(
                detail,
                style: textTheme.bodyMedium?.copyWith(
                  color: present ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (isNewer)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.schedule_rounded, size: 16, color: cs.tertiary),
          ),
      ],
    );
  }
}
