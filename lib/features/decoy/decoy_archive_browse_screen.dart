import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/file_size.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/browser/archive_file_viewer.dart';
import 'package:vaultexplorer/features/decoy/decoy_archive_extract.dart';

/// Lets the user look inside a `.zip` picked from the decoy Archive
/// Explorer screen without extracting the whole thing first: navigate its
/// folders, tap a file to preview it, or extract the current folder (or
/// the whole archive) to a chosen destination.
///
/// Deliberately its own small screen rather than reusing
/// [ArchiveFileViewer]'s host, [FileBrowserScreen] -- that screen is wired
/// to the encrypted-container backend end to end, and pulling it apart to
/// also serve a plain on-disk zip would be a much bigger, riskier change
/// than this purpose-built ~200 lines.
class DecoyArchiveBrowseScreen extends StatefulWidget {
  final File archiveFile;
  final String archiveName;

  const DecoyArchiveBrowseScreen({
    super.key,
    required this.archiveFile,
    required this.archiveName,
  });

  @override
  State<DecoyArchiveBrowseScreen> createState() => _DecoyArchiveBrowseScreenState();
}

class _DecoyArchiveBrowseScreenState extends State<DecoyArchiveBrowseScreen> {
  static const _api = VaultExplorerApi();

  ArchiveContext? _ctx;
  Object? _openError;
  String _currentPath = '';
  bool _extracting = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      // ArchiveContext.open() reads and decodes the whole file
      // synchronously; running it inside a Future (rather than calling it
      // straight from initState) keeps that off the frame that's building
      // the loading spinner.
      final ctx = await Future(() => ArchiveContext.open(
            archivePathInContainer: widget.archiveName,
            tempFilePath: widget.archiveFile.path,
            pathStackEntryIndex: 0,
          ));
      if (!mounted) return;
      setState(() => _ctx = ctx);
    } catch (e) {
      if (!mounted) return;
      setState(() => _openError = e);
    }
  }

  List<RawEntry> get _currentEntries {
    final ctx = _ctx;
    if (ctx == null) return const [];
    final entries = RawEntry.parseAll(ctx.listDirectory(_currentPath));
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  String _joinArchivePath(String base, String name) => base.isEmpty ? name : '$base/$name';

  bool _goUp() {
    if (_currentPath.isEmpty) return false;
    final idx = _currentPath.lastIndexOf('/');
    setState(() => _currentPath = idx < 0 ? '' : _currentPath.substring(0, idx));
    return true;
  }

  Future<void> _openEntry(RawEntry entry) async {
    final ctx = _ctx;
    if (ctx == null) return;
    final entryPath = _joinArchivePath(_currentPath, entry.name);

    if (entry.isDir) {
      setState(() => _currentPath = entryPath);
      return;
    }

    try {
      final tempPath = await ctx.extractEntry(entryPath);
      if (tempPath == null) throw StateError('entry not found: $entryPath');
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ArchiveFileViewer(file: File(tempPath), fileName: entry.name),
      ));
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: context.l10n.archiveBrowserOpenFileFailed,
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _extract({required bool wholeArchive}) async {
    final ctx = _ctx;
    if (ctx == null || _extracting) return;

    showAppSnackBar(context, message: context.l10n.archiveExplorerChoosingDestination);
    final picked = await _api.pickExtractFolder();
    if (!mounted) return;
    if (picked == null) {
      showAppSnackBar(context, message: context.l10n.archiveExplorerNoDestinationChosen);
      return;
    }
    final destPath = picked.path;
    if (destPath == null) {
      showAppSnackBar(
        context,
        message: context.l10n.archiveExplorerUnresolvedPath,
        tone: AppBannerTone.error,
      );
      return;
    }

    setState(() => _extracting = true);
    try {
      final count = await extractArchiveContextTo(
        ctx,
        Directory(destPath),
        subPath: wholeArchive ? '' : _currentPath,
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: context.l10n.archiveExplorerExtractSuccessTo(count, picked.displayName),
        tone: AppBannerTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: context.l10n.archiveExplorerExtractFailed,
        tone: AppBannerTone.error,
      );
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Backing out of a subfolder should surface the parent folder
      // first, and only actually leave the screen once we're already at
      // archive root -- the same "one level at a time" behavior as the
      // real vault's file browser.
      canPop: _currentPath.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _currentPath.isEmpty ? widget.archiveName : p.basename(_currentPath),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_ctx != null)
              _extracting
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : PopupMenuButton<bool>(
                      icon: const Icon(Icons.drive_file_move_outline),
                      tooltip: context.l10n.archiveExplorerExtractTo,
                      onSelected: (wholeArchive) => _extract(wholeArchive: wholeArchive),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: true,
                          child: Text(context.l10n.archiveExplorerExtractAll),
                        ),
                        if (_currentPath.isNotEmpty)
                          PopupMenuItem(
                            value: false,
                            child: Text(context.l10n.archiveExplorerExtractTo),
                          ),
                      ],
                    ),
          ],
        ),
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_openError != null) {
      return AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: context.l10n.archiveExplorerOpenFailed,
        message: widget.archiveName,
      );
    }

    if (_ctx == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    final entries = _currentEntries;
    if (entries.isEmpty) {
      return AppEmptyState(
        icon: Icons.folder_open_rounded,
        title: context.l10n.archiveBrowserEmptyTitle,
        message: context.l10n.archiveBrowserEmptyMessage,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          leading: Icon(
            entry.isDir ? Icons.folder_rounded : iconForFile(entry.name),
            size: 28,
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: entry.isDir ? null : Text(FileSize.bytes(entry.sizeBytes).formatted),
          trailing: entry.isDir ? const Icon(Icons.chevron_right_rounded) : null,
          onTap: () => _openEntry(entry),
        );
      },
    );
  }
}
