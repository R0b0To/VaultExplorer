import 'package:path/path.dart' as p;

/// File-name suffixes the engine uses for its own in-progress writes.
const String kSyncTempSuffix = '.vexp_tmp';
const String kSyncBackupSuffix = '.vexp_old';

/// The vault folder that holds `sync_config.json` / `sync_ledger.json`.
/// Never synced, whatever the rule's ignore patterns say.
const String kVaultMetaDir = '.vaultexplorer';

/// Paths that must never be synchronized, even if a rule's editable ignore
/// list is cleared. These cover operating-system trees and metadata commonly
/// found under a whole-device storage root. Folder-vault ciphertext is also
/// detected from its format markers while scanning.
const List<String> kSyncProtectedPatterns = [
  'Android',
  '.nomedia',
  '.thumbnails',
  'LOST.DIR',
  'System Volume Information',
  '\$RECYCLE.BIN',
  '.Trash-*',
  '.fseventsd',
  '@eaDir',
];

/// Decides which relative paths a rule skips.
///
/// Patterns are simple globs (`*` = any run of characters except `/`,
/// `?` = one character except `/`), matched case-insensitively:
///
/// * A pattern **without** `/` (`*.tmp`, `.*`) is tested against every
///   path segment, so ignoring `.git` also ignores everything beneath it.
/// * A pattern **with** `/` (`cache/*.bin`) is anchored at the sync root
///   and also covers everything beneath a matching folder.
class SyncIgnoreMatcher {
  final List<RegExp> _segmentGlobs;
  final List<RegExp> _pathGlobs;
  final Set<String> _protectedPaths;

  SyncIgnoreMatcher._(
    this._segmentGlobs,
    this._pathGlobs,
    this._protectedPaths,
  );

  factory SyncIgnoreMatcher(
    Iterable<String> userPatterns, {
    Iterable<String> protectedPaths = const [],
  }) {
    final segment = <RegExp>[];
    final path = <RegExp>[];
    final all = <String>[
      '*$kSyncTempSuffix',
      '*$kSyncBackupSuffix',
      kVaultMetaDir,
      ...kSyncProtectedPatterns,
      ...userPatterns,
    ];
    for (final raw in all) {
      final pattern = raw.trim();
      if (pattern.isEmpty) continue;
      if (pattern.contains('/')) {
        final anchored = pattern.startsWith('/')
            ? pattern.substring(1)
            : pattern;
        path.add(
          RegExp('^${_globBody(anchored)}(?:/.*)?\$', caseSensitive: false),
        );
      } else {
        segment.add(RegExp('^${_globBody(pattern)}\$', caseSensitive: false));
      }
    }
    return SyncIgnoreMatcher._(
      segment,
      path,
      protectedPaths
          .map(
            (path) =>
                p.posix.normalize(path.replaceAll('\\', '/')).toLowerCase(),
          )
          .where((path) => path.isNotEmpty && path != '.')
          .toSet(),
    );
  }

  /// Returns the vault's own ciphertext path relative to a selected local
  /// sync root, when both sides have raw filesystem paths.
  static String? vaultCiphertextPathRelativeToTarget({
    required String vaultUri,
    required String targetUri,
    required String targetSubPath,
  }) {
    try {
      final vault = Uri.parse(vaultUri);
      final vaultPath = vault.scheme == 'file' ? vault.toFilePath() : vaultUri;
      if (!p.isAbsolute(vaultPath) || !p.isAbsolute(targetUri)) return null;
      final root = p.normalize(p.join(targetUri, targetSubPath));
      final candidate = p.normalize(vaultPath);
      if (candidate == root || !p.isWithin(root, candidate)) return null;
      return p.relative(candidate, from: root).replaceAll('\\', '/');
    } catch (_) {
      return null;
    }
  }

  static String _globBody(String glob) {
    final out = StringBuffer();
    for (final rune in glob.runes) {
      final ch = String.fromCharCode(rune);
      switch (ch) {
        case '*':
          out.write('[^/]*');
        case '?':
          out.write('[^/]');
        default:
          out.write(RegExp.escape(ch));
      }
    }
    return out.toString();
  }

  /// True if [relPath] (relative to the sync root, `/`-separated) is skipped.
  bool isIgnored(String relPath) {
    if (relPath.isEmpty) return false;
    final normalized = p.posix
        .normalize(relPath.replaceAll('\\', '/'))
        .toLowerCase();
    if (_protectedPaths.any(
      (protected) =>
          normalized == protected || normalized.startsWith('$protected/'),
    )) {
      return true;
    }
    if (_segmentGlobs.isNotEmpty) {
      for (final segment in relPath.split('/')) {
        for (final glob in _segmentGlobs) {
          if (glob.hasMatch(segment)) return true;
        }
      }
    }
    for (final glob in _pathGlobs) {
      if (glob.hasMatch(relPath)) return true;
    }
    return false;
  }
}

/// True for the engine's own leftovers (`x.vexp_tmp`, `x.vexp_old`).
bool isSyncArtifact(String relPath) =>
    relPath.endsWith(kSyncTempSuffix) || relPath.endsWith(kSyncBackupSuffix);
