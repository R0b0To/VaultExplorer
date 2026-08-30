import 'dart:io';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/features/browser/archive_file_viewer.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart' show PathSegment;
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/file_tile.dart';

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
  ArchiveContext? _archive;
  bool _openFailed = false;
  bool _extracting = false;
  late List<PathSegment> _pathStack;

  @override
  void initState() {
    super.initState();
    _pathStack = [PathSegment(widget.archiveName, '', isArchiveRoot: true)];
    _open();
  }

  Future<void> _open() async {
    try {
      final bytes = await widget.archiveFile.readAsBytes();
      final ctx = ArchiveContext.open(
        archivePathInContainer: widget.archiveName,
        bytes: Uint8List.fromList(bytes),
        pathStackEntryIndex: 0,
      );
      if (!mounted) return;
      setState(() => _archive = ctx);
    } catch (_) {
      if (!mounted) return;
      setState(() => _openFailed = true);
    }
  }

  String get _currentPath => _pathStack.last.fatPath;

  List<RawEntry> get _entries {
    final archive = _archive;
    if (archive == null) return const [];
    final entries = archive.listDirectory(_currentPath).map(RawEntry.parse).toList();
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  String _fullEntryPath(RawEntry entry) =>
      _currentPath.isEmpty ? entry.name : '$_currentPath/${entry.name}';

  void _enter(RawEntry entry) {
    setState(() => _pathStack.add(PathSegment(entry.name, _fullEntryPath(entry))));
  }

  void _jumpTo(int index) {
    if (index == _pathStack.length - 1) return;
    setState(() => _pathStack.removeRange(index + 1, _pathStack.length));
  }

  Future<void> _preview(RawEntry entry) async {
    final archive = _archive;
    if (archive == null) return;
    final bytes = await archive.extractEntry(_fullEntryPath(entry));
    if (!mounted || bytes == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ArchiveFileViewer(bytes: bytes, fileName: entry.name),
    ));
  }

  /// Picks a non-colliding sibling folder next to the archive itself --
  /// same convention the deleted decoy_archive_extract.dart used, and
  /// what most system archive tools default to (extract "notes.zip" to a
  /// "notes" folder beside it).
  Future<Directory> _uniqueExtractRoot() async {
    final parent = widget.archiveFile.parent.path;
    final baseName = p.basenameWithoutExtension(widget.archiveName);
    var dir = Directory(p.join(parent, baseName));
    var suffix = 1;
    while (await dir.exists()) {
      dir = Directory(p.join(parent, '$baseName ($suffix)'));
      suffix++;
    }
    return dir;
  }

  Future<void> _extractAll() async {
    final archive = _archive;
    if (archive == null || _extracting) return;
    setState(() => _extracting = true);
    try {
      final destRoot = await _uniqueExtractRoot();
      await destRoot.create(recursive: true);
      for (final dirPath in archive.getSubDirectories('')) {
        await Directory(p.join(destRoot.path, dirPath)).create(recursive: true);
      }
      final files = await archive.extractAll();
      for (final entry in files.entries) {
        final outFile = File(p.join(destRoot.path, entry.key));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.value);
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: context.l10n.archiveExplorerExtractSuccess(files.length, p.basename(destRoot.path)),
        tone: AppBannerTone.success,
      );
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, message: context.l10n.archiveExplorerExtractFailed, tone: AppBannerTone.error);
      }
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _pathStack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _jumpTo(_pathStack.length - 2);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.archiveName, maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: BreadcrumbBar(stack: _pathStack, onTap: _jumpTo),
          ),
          actions: [
            if (_archive != null)
              IconButton(
                icon: _extracting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.unarchive_outlined),
                tooltip: context.l10n.archiveExplorerExtractAll,
                onPressed: _extracting ? null : _extractAll,
              ),
          ],
        ),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_openFailed) {
      return AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: context.l10n.archiveExplorerOpenFailed,
        message: '',
      );
    }
    if (_archive == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = _entries;
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
            onTap: () => _enter(entry),
            onLongPress: () {},
          );
        }
        return FileTile(
          entry: entry,
          isSelectionMode: false,
          isSelected: false,
          currentDirPath: _currentPath,
          onTap: () => _preview(entry),
          onLongPress: () {},
        );
      },
    );
  }
}
