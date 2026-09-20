/// File-name suffixes the engine uses for its own in-progress writes.
const String kSyncTempSuffix = '.vexp_tmp';
const String kSyncBackupSuffix = '.vexp_old';

/// The vault folder that holds `sync_config.json` / `sync_ledger.json`.
/// Never synced, whatever the rule's ignore patterns say.
const String kVaultMetaDir = '.vaultexplorer';

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

  SyncIgnoreMatcher._(this._segmentGlobs, this._pathGlobs);

  factory SyncIgnoreMatcher(Iterable<String> userPatterns) {
    final segment = <RegExp>[];
    final path = <RegExp>[];
    final all = <String>[
      '*$kSyncTempSuffix',
      '*$kSyncBackupSuffix',
      kVaultMetaDir,
      ...userPatterns,
    ];
    for (final raw in all) {
      final pattern = raw.trim();
      if (pattern.isEmpty) continue;
      if (pattern.contains('/')) {
        final anchored = pattern.startsWith('/') ? pattern.substring(1) : pattern;
        path.add(
          RegExp('^${_globBody(anchored)}(?:/.*)?\$', caseSensitive: false),
        );
      } else {
        segment.add(RegExp('^${_globBody(pattern)}\$', caseSensitive: false));
      }
    }
    return SyncIgnoreMatcher._(segment, path);
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
