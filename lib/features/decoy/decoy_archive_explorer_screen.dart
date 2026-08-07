import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/file_size.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

class _ZipEntry {
  final File file;
  final String name;
  final int sizeBytes;
  final DateTime modified;

  const _ZipEntry({
    required this.file,
    required this.name,
    required this.sizeBytes,
    required this.modified,
  });
}

/// Decoy "Archive Explorer" home screen: a small, genuinely-functional zip
/// browser over the device's public Downloads folder. Shown instead of the
/// real vault UI whenever Mask Mode is active.
///
/// The app-bar title carries the [HiddenVaultTrigger] hold gesture back to
/// the real [LockGateScreen] -- see that widget for the timing rationale.
class DecoyArchiveExplorerScreen extends StatefulWidget {
  const DecoyArchiveExplorerScreen({super.key});

  @override
  State<DecoyArchiveExplorerScreen> createState() => _DecoyArchiveExplorerScreenState();
}

class _DecoyArchiveExplorerScreenState extends State<DecoyArchiveExplorerScreen>
    with WidgetsBindingObserver {
  static const _api = VaultExplorerApi();

  bool _loading = true;
  bool _hasAccess = false;
  List<_ZipEntry> _entries = const [];
  String? _extractingPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the user granting "All files access" in Settings and coming
    // back without needing an explicit pull-to-refresh.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<Directory> _downloadsDir() async {
    // There's no cross-version public API for the shared Downloads folder,
    // but its path is stable on every real device: walk up from the app's
    // external files dir (.../Android/data/<pkg>/files) to the storage
    // root and append "Download".
    final appExternal = await getExternalStorageDirectory();
    if (appExternal == null) {
      return Directory('/storage/emulated/0/Download');
    }
    var dir = appExternal;
    while (dir.path.isNotEmpty && p.basename(dir.path) != 'Android') {
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    final root = p.basename(dir.path) == 'Android' ? dir.parent : appExternal;
    return Directory(p.join(root.path, 'Download'));
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    final hasAccess = await _api.hasAllFilesAccess();
    if (!hasAccess) {
      if (mounted) setState(() {
        _hasAccess = false;
        _loading = false;
      });
      return;
    }

    List<_ZipEntry> found = [];
    try {
      final dir = await _downloadsDir();
      if (await dir.exists()) {
        await for (final item in dir.list(followLinks: false)) {
          if (item is! File) continue;
          if (p.extension(item.path).toLowerCase() != '.zip') continue;
          final stat = await item.stat();
          found.add(_ZipEntry(
            file: item,
            name: p.basename(item.path),
            sizeBytes: stat.size,
            modified: stat.modified,
          ));
        }
        found.sort((a, b) => b.modified.compareTo(a.modified));
      }
    } catch (_) {
      // Best effort -- leave whatever was found before the error.
    }

    if (!mounted) return;
    setState(() {
      _hasAccess = true;
      _entries = found;
      _loading = false;
    });
  }

  Future<void> _requestAccess() async {
    await _api.requestAllFilesAccess();
    await _refresh();
  }

  Future<void> _extractAll(_ZipEntry entry) async {
    setState(() => _extractingPath = entry.file.path);

    final archiveBaseName = p.basenameWithoutExtension(entry.name);
    ArchiveContext? ctx;
    try {
      ctx = ArchiveContext.open(
        archivePathInContainer: entry.name,
        tempFilePath: entry.file.path,
        pathStackEntryIndex: 0,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _extractingPath = null);
        showAppSnackBar(
          context,
          message: context.l10n.archiveExplorerOpenFailed,
          tone: AppBannerTone.error,
        );
      }
      return;
    }

    try {
      // Extracts to a real temp dir via plain dart:io (no encrypted
      // container involved) -- see ArchiveContext.extractAll.
      final extracted = await ctx.extractAll();

      final downloads = await _downloadsDir();
      final destRoot = Directory(p.join(downloads.path, 'Extracted', archiveBaseName));
      await destRoot.create(recursive: true);

      var count = 0;
      for (final mapEntry in extracted.entries) {
        final relativePath = mapEntry.key;
        final tempPath = mapEntry.value;
        final destPath = p.join(destRoot.path, relativePath);
        final destFile = File(destPath);
        try {
          await destFile.parent.create(recursive: true);
          await File(tempPath).copy(destPath);
          count++;
        } finally {
          try {
            await File(tempPath).delete();
          } catch (_) {}
        }
      }

      if (!mounted) return;
      showAppSnackBar(
        context,
        message: context.l10n.archiveExplorerExtractSuccess(count, archiveBaseName),
        tone: AppBannerTone.success,
      );
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.archiveExplorerExtractFailed,
          tone: AppBannerTone.error,
        );
      }
    } finally {
      // Deliberately NOT calling ctx.dispose() here: tempFilePath on this
      // context is the *real* file the user picked from Downloads, and
      // dispose() deletes tempFilePath -- that would delete their archive.
      if (mounted) setState(() => _extractingPath = null);
    }
  }

  int _entryCount(_ZipEntry entry) {
    try {
      final ctx = ArchiveContext.open(
        archivePathInContainer: entry.name,
        tempFilePath: entry.file.path,
        pathStackEntryIndex: 0,
      );
      return ctx.listDirectory('').length;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: HiddenVaultTrigger(child: Text(context.l10n.appNameZipExplorer)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.l10n.archiveExplorerRefreshTooltip,
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (!_hasAccess) {
      return AppEmptyState(
        icon: Icons.folder_zip_rounded,
        title: context.l10n.archiveExplorerPermissionTitle,
        message: context.l10n.archiveExplorerPermissionMessage,
        actionLabel: context.l10n.archiveExplorerGrantAccess,
        actionIcon: Icons.lock_open_rounded,
        onAction: _requestAccess,
      );
    }

    if (_entries.isEmpty) {
      return AppEmptyState(
        icon: Icons.folder_zip_rounded,
        title: context.l10n.archiveExplorerEmptyTitle,
        message: context.l10n.archiveExplorerEmptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final isExtracting = _extractingPath == entry.file.path;
          return ListTile(
            leading: const Icon(Icons.folder_zip_rounded, size: 32),
            title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${FileSize.bytes(entry.sizeBytes).formatted} · '
              '${context.l10n.archiveExplorerEntryCount(_entryCount(entry))}',
            ),
            trailing: isExtracting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: () => _extractAll(entry),
                    child: Text(context.l10n.archiveExplorerExtractAll),
                  ),
          );
        },
      ),
    );
  }
}