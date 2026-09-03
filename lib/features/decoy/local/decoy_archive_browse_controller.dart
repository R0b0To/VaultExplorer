import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart' show PathSegment;

part 'decoy_archive_browse_controller.g.dart';

class DecoyArchiveBrowseState {
  final ArchiveContext? archive;
  final bool openFailed;
  final bool extracting;
  final List<PathSegment> pathStack;

  const DecoyArchiveBrowseState({
    this.archive,
    this.openFailed = false,
    this.extracting = false,
    required this.pathStack,
  });

  DecoyArchiveBrowseState _copy({
    ArchiveContext? archive,
    bool? openFailed,
    bool? extracting,
    List<PathSegment>? pathStack,
  }) {
    return DecoyArchiveBrowseState(
      archive: archive ?? this.archive,
      openFailed: openFailed ?? this.openFailed,
      extracting: extracting ?? this.extracting,
      pathStack: pathStack ?? this.pathStack,
    );
  }
}

extension DecoyArchiveBrowseStateX on DecoyArchiveBrowseState {
  String get currentPath => pathStack.last.fatPath;

  /// Open status of the underlying scan, once a scan attempt has returned.
  ArchiveOpenStatus? get openStatus => archive?.status;

  /// Whether the archive is waiting on a (first or retried) password.
  bool get needsPassphrase =>
      openStatus == ArchiveOpenStatus.passphraseRequired ||
      openStatus == ArchiveOpenStatus.wrongPassphrase;

  /// Whether the archive is a solid archive (RAR/7z with shared blocks),
  /// once a successful scan has returned.
  bool get isSolid => archive?.isSolid ?? false;

  List<RawEntry> get entries {
    final ctx = archive;
    if (ctx == null || ctx.status != ArchiveOpenStatus.ok) return const [];
    final list = ctx.listDirectory(currentPath).map(RawEntry.parse).toList();
    list.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  String fullEntryPath(RawEntry entry) => currentPath.isEmpty ? entry.name : '$currentPath/${entry.name}';
}

@riverpod
class DecoyArchiveBrowse extends _$DecoyArchiveBrowse {
  @override
  DecoyArchiveBrowseState build(String filePath, String archiveName) {
    final initial = DecoyArchiveBrowseState(
      pathStack: [PathSegment(archiveName, '', isArchiveRoot: true)],
    );
    Future.microtask(() => _open(filePath, archiveName));
    return initial;
  }

  /// Scans the local archive via the native engine (file descriptor based --
  /// no full read into Dart memory). Pass [passphrase] to retry after a
  /// [ArchiveOpenStatus.passphraseRequired]/[wrongPassphrase] prompt.
  Future<void> _open(String filePath, String archiveName, {String? passphrase}) async {
    try {
      final ctx = await ArchiveService.openLocal(
        pathOrUri: filePath,
        archiveName: archiveName,
        passphrase: passphrase,
      );
      if (ref.mounted) state = state._copy(archive: ctx, openFailed: false);
    } catch (_) {
      if (ref.mounted) state = state._copy(openFailed: true);
    }
  }

  /// Re-attempts opening the archive with a user-supplied password, e.g.
  /// after a [DecoyArchiveBrowseStateX.needsPassphrase] prompt.
  Future<void> retryWithPassword(String filePath, String archiveName, String passphrase) =>
      _open(filePath, archiveName, passphrase: passphrase);

  void enter(RawEntry entry) {
    state = state._copy(
      pathStack: [...state.pathStack, PathSegment(entry.name, state.fullEntryPath(entry))],
    );
  }

  void jumpTo(int index) {
    if (index == state.pathStack.length - 1) return;
    state = state._copy(pathStack: state.pathStack.sublist(0, index + 1));
  }

  Future<Uint8List?> extractEntry(RawEntry entry) async {
    final ctx = state.archive;
    if (ctx == null) return null;
    return ctx.extractEntry(state.fullEntryPath(entry));
  }

  /// Picks a non-colliding sibling folder next to the archive itself --
  /// same convention the deleted decoy_archive_extract.dart used, and what
  /// most system archive tools default to (extract "notes.zip" to a
  /// "notes" folder beside it).
  Future<Directory> _uniqueExtractRoot(String filePath, String archiveName) async {
    final parent = File(filePath).parent.path;
    final baseName = p.basenameWithoutExtension(archiveName);
    var dir = Directory(p.join(parent, baseName));
    var suffix = 1;
    while (await dir.exists()) {
      dir = Directory(p.join(parent, '$baseName ($suffix)'));
      suffix++;
    }
    return dir;
  }

  /// Extracts everything into a fresh sibling folder. Returns
  /// (file count, destination folder name) on success, null on failure --
  /// the widget turns either into a snackbar rather than this Notifier
  /// owning a transient "last result" state field for a one-shot action.
  Future<(int, String)?> extractAll(String filePath, String archiveName) async {
    final ctx = state.archive;
    if (ctx == null || ctx.status != ArchiveOpenStatus.ok || state.extracting) return null;
    state = state._copy(extracting: true);
    try {
      final destRoot = await _uniqueExtractRoot(filePath, archiveName);
      await destRoot.create(recursive: true);
      for (final dirPath in ctx.getSubDirectories('')) {
        await Directory(p.join(destRoot.path, dirPath)).create(recursive: true);
      }
      final files = await ctx.extractAll();
      for (final entry in files.entries) {
        final outFile = File(p.join(destRoot.path, entry.key));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.value);
      }
      if (ref.mounted) state = state._copy(extracting: false);
      return (files.length, p.basename(destRoot.path));
    } catch (_) {
      if (ref.mounted) state = state._copy(extracting: false);
      return null;
    }
  }
}