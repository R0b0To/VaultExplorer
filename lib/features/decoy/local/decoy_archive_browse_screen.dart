import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/features/browser/archive_file_viewer.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart' show PathSegment;
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/file_tile.dart';
import 'decoy_archive_browse_controller.dart';

/// In-app browser for a real, on-disk zip file, pushed when the decoy's
/// local storage explorer's [_openFile] sees an archive extension.
///
/// The vault file browser can navigate into an archive inline (pushing an
/// archive-root [PathSegment] onto its own `_pathStack`); this is a
/// separate, standalone screen instead, because that inline integration
/// is wired end-to-end to the vault's `_currentItems`/`_loadDirectoryContents`
/// machinery. Scanning and extraction both go through the native engine via
/// `ArchiveService.openLocal`/`ArchiveContext.extractEntry` -- a file
/// descriptor is indexed/read on demand rather than the whole archive being
/// read into Dart memory up front -- and extraction writes straight to disk
/// instead of through `FileBrowserScreen`'s engine APIs.
class DecoyArchiveBrowseScreen extends ConsumerWidget {
  final File archiveFile;
  final String archiveName;

  const DecoyArchiveBrowseScreen({
    super.key,
    required this.archiveFile,
    required this.archiveName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = decoyArchiveBrowseProvider(archiveFile.path, archiveName);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    ref.listen<DecoyArchiveBrowseState>(provider, (previous, next) {
      if (next.needsPassphrase && previous?.needsPassphrase != true) {
        _promptForPassword(
          context,
          notifier,
          wrongPassword: next.openStatus == ArchiveOpenStatus.wrongPassphrase,
        );
      }
    });

    return PopScope(
      canPop: state.pathStack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        notifier.jumpTo(state.pathStack.length - 2);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(archiveName, maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: BreadcrumbBar(stack: state.pathStack, onTap: notifier.jumpTo),
          ),
          actions: [
            if (state.archive != null && !state.needsPassphrase)
              IconButton(
                icon: state.extracting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.unarchive_outlined),
                tooltip: context.l10n.archiveExplorerExtractAll,
                onPressed: state.extracting
                    ? null
                    : () async {
                        final result = await notifier.extractAll(archiveFile.path, archiveName);
                        if (!context.mounted) return;
                        if (result != null) {
                          showAppSnackBar(
                            context,
                            message: context.l10n.archiveExplorerExtractSuccess(result.$1, result.$2),
                            tone: AppBannerTone.success,
                          );
                        } else {
                          showAppSnackBar(
                            context,
                            message: context.l10n.archiveExplorerExtractFailed,
                            tone: AppBannerTone.error,
                          );
                        }
                      },
              ),
          ],
        ),
        body: Column(
          children: [
            if (state.isSolid)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: InlineBanner(
                  context.l10n.archiveSolidWarning,
                  tone: AppBannerTone.warning,
                ),
              ),
            Expanded(child: _buildBody(context, state, notifier)),
          ],
        ),
      ),
    );
  }

  Future<void> _promptForPassword(
    BuildContext context,
    DecoyArchiveBrowse notifier, {
    required bool wrongPassword,
  }) async {
    final password = await BrowserDialogs.showArchivePasswordPrompt(
      context,
      wrongPassword: wrongPassword,
    );
    if (password == null || !context.mounted) return;
    await notifier.retryWithPassword(archiveFile.path, archiveName, password);
  }

  Widget _buildBody(BuildContext context, DecoyArchiveBrowseState state, DecoyArchiveBrowse notifier) {
    if (state.openFailed) {
      return AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: context.l10n.archiveExplorerOpenFailed,
        message: '',
      );
    }
    if (state.needsPassphrase) {
      return AppEmptyState(
        icon: Icons.lock_outline_rounded,
        title: context.l10n.archivePasswordPromptTitle,
        message: context.l10n.archivePasswordPromptMessage,
        actionLabel: context.l10n.unlock,
        actionIcon: Icons.lock_open_rounded,
        onAction: () => _promptForPassword(
          context,
          notifier,
          wrongPassword: state.openStatus == ArchiveOpenStatus.wrongPassphrase,
        ),
      );
    }
    if (state.archive == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = state.entries;
    if (entries.isEmpty) {
      return AppEmptyState(
        icon: Icons.folder_open_outlined,
        title: context.l10n.filesEmptyTitle,
        message: context.l10n.filesEmptyMessage,
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry.isDir) {
          return DirectoryTile(
            entry: entry,
            isSelectionMode: false,
            isSelected: false,
            onTap: () => notifier.enter(entry),
            onLongPress: () {},
          );
        }
        return FileTile(
          entry: entry,
          isSelectionMode: false,
          isSelected: false,
          currentDirPath: state.currentPath,
          onTap: () async {
            final bytes = await notifier.extractEntry(entry);
            if (!context.mounted || bytes == null) return;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ArchiveFileViewer(bytes: bytes, fileName: entry.name),
            ));
          },
          onLongPress: () {},
        );
      },
    );
  }
}