import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/features/browser/archive_file_viewer.dart';
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
/// machinery. [ArchiveContext] itself already anticipates this simpler
/// "not backed by a container at all" use (see its class doc comment) --
/// bytes come from a plain `File.readAsBytes()` here instead of a chunked
/// container read, and extraction writes straight to disk instead of
/// through `VaultExplorerApi`.
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
    final state = ref.watch(decoyArchiveBrowseProvider(archiveFile.path, archiveName));
    final notifier = ref.read(decoyArchiveBrowseProvider(archiveFile.path, archiveName).notifier);

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
            if (state.archive != null)
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
        body: _buildBody(context, state, notifier),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DecoyArchiveBrowseState state, DecoyArchiveBrowse notifier) {
    if (state.openFailed) {
      return AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: context.l10n.archiveExplorerOpenFailed,
        message: '',
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