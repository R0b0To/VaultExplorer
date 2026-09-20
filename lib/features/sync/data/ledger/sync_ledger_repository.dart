import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

/// The sync ledger: the last-synced ("base") state of every file, per rule.
///
/// Reads and mutations are synchronous and in memory; only [open] and
/// [flush] touch storage. The executor mutates the ledger as it goes and
/// the caller flushes at safe points (end of run, on cancellation).
abstract class SyncLedgerRepository {
  /// Loads persisted state. A missing or unreadable ledger opens empty,
  /// which is safe: every file is then "first sight" (copied, adopted or
  /// conflict-preserved) and nothing is ever deleted on that basis.
  Future<void> open();

  /// Every key that currently has baseline rows. (A "rule id" here is
  /// whatever key the caller files rows under; the coordinator uses
  /// `<ruleId>#<target fingerprint>` so devices with different targets
  /// never share a baseline.)
  Iterable<String> get ruleKeys;

  /// Copy of the baseline rows for [ruleId], keyed by relative path.
  Map<String, SyncStateRecord> baselineFor(String ruleId);

  void put(SyncStateRecord record);
  void remove(String ruleId, String relPath);
  void clearRule(String ruleId);

  bool get isDirty;

  /// Persists pending changes. True if nothing was pending or the write
  /// succeeded.
  Future<bool> flush();

  Future<void> close();
}

class InMemorySyncLedger implements SyncLedgerRepository {
  final Map<String, Map<String, SyncStateRecord>> rules = {};
  bool _dirty = false;

  @override
  bool get isDirty => _dirty;

  @override
  Future<void> open() async {}

  @override
  Iterable<String> get ruleKeys => List<String>.of(rules.keys);

  @override
  Map<String, SyncStateRecord> baselineFor(String ruleId) =>
      Map<String, SyncStateRecord>.of(rules[ruleId] ?? const {});

  @override
  void put(SyncStateRecord record) {
    rules.putIfAbsent(record.ruleId, () => {})[record.relPath] = record;
    _dirty = true;
  }

  @override
  void remove(String ruleId, String relPath) {
    final removed = rules[ruleId]?.remove(relPath);
    if (removed != null) _dirty = true;
  }

  @override
  void clearRule(String ruleId) {
    if (rules.remove(ruleId) != null) _dirty = true;
  }

  @override
  Future<bool> flush() async {
    _dirty = false;
    return true;
  }

  @override
  Future<void> close() async {}

  /// For subclasses that load state: replace everything without marking
  /// the ledger dirty.
  void loadAll(Map<String, Map<String, SyncStateRecord>> loaded) {
    rules
      ..clear()
      ..addAll(loaded);
    _dirty = false;
  }

  void markClean() => _dirty = false;
  void markDirty() => _dirty = true;
}

/// On-disk format: one compact array per file so a large ledger stays
/// small.
///
/// ```json
/// {"v":1,"rules":{"<ruleId>":[
///   ["<relPath>", vMtime, vSize, "<vHash>"|null, tMtime, tSize, "<tHash>"|null, syncedAtMs]
/// ]}}
/// ```
class SyncLedgerCodec {
  static const int version = 1;

  static String encode(Map<String, Map<String, SyncStateRecord>> rules) {
    final out = <String, Object?>{};
    for (final entry in rules.entries) {
      if (entry.value.isEmpty) continue;
      out[entry.key] = [
        for (final r in entry.value.values)
          [
            r.relPath,
            r.vault.mtimeSecs,
            r.vault.size,
            r.vault.hash,
            r.target.mtimeSecs,
            r.target.size,
            r.target.hash,
            r.lastSyncedAtMs,
          ],
      ];
    }
    return jsonEncode({'v': version, 'rules': out});
  }

  /// Throws [FormatException] if [source] isn't a ledger at all. Individual
  /// malformed rows are skipped -- a dropped row only makes that file
  /// "first sight" again, which never deletes anything.
  static Map<String, Map<String, SyncStateRecord>> decode(String source) {
    final root = jsonDecode(source);
    if (root is! Map || root['rules'] is! Map) {
      throw const FormatException('sync ledger: unexpected structure');
    }
    final result = <String, Map<String, SyncStateRecord>>{};
    (root['rules'] as Map).forEach((ruleId, rows) {
      if (ruleId is! String || rows is! List) return;
      final byPath = <String, SyncStateRecord>{};
      for (final row in rows) {
        final record = _decodeRow(ruleId, row);
        if (record != null) byPath[record.relPath] = record;
      }
      if (byPath.isNotEmpty) result[ruleId] = byPath;
    });
    return result;
  }

  static SyncStateRecord? _decodeRow(String ruleId, Object? row) {
    if (row is! List || row.length < 8) return null;
    final path = row[0];
    final vMtime = row[1];
    final vSize = row[2];
    final vHash = row[3];
    final tMtime = row[4];
    final tSize = row[5];
    final tHash = row[6];
    final at = row[7];
    if (path is! String ||
        vMtime is! int ||
        vSize is! int ||
        tMtime is! int ||
        tSize is! int ||
        at is! int ||
        (vHash != null && vHash is! String) ||
        (tHash != null && tHash is! String)) {
      return null;
    }
    return SyncStateRecord(
      ruleId: ruleId,
      relPath: path,
      vault: SyncSideState(size: vSize, mtimeSecs: vMtime, hash: vHash as String?),
      target: SyncSideState(size: tSize, mtimeSecs: tMtime, hash: tHash as String?),
      lastSyncedAtMs: at,
    );
  }
}

/// The ledger of one unlocked vault, persisted *inside* that vault at
/// `/.vaultexplorer/sync_ledger.json`, so it is encrypted at rest and the
/// host OS never sees which files a vault contains.
///
/// The plan called for an SQLite database here. The app has no database
/// dependency (a standing project rule), and SQLite needs random access
/// to a real file, which an encrypted vault can't offer -- Dart only sees
/// vault files through chunked reads and writes. The whole ledger is
/// therefore loaded once and rewritten atomically on [flush] (through
/// `VaultFileIoApi.writeWholeFile`: temp file, then replace). That is
/// plenty for personal-scale vaults; the [SyncLedgerRepository] interface
/// is what would let a different store slot in later.
class VaultFileSyncLedger extends InMemorySyncLedger {
  static const String _tag = 'SyncLedger';
  static const String fileName = 'sync_ledger.json';
  static const String filePath = '$kVaultMetaDir/$fileName';

  final VaultFileIoApi _io;
  final MountedContainer _vault;
  bool _metaDirEnsured = false;
  Future<bool>? _flushing;

  VaultFileSyncLedger(this._io, this._vault);

  @override
  Future<void> open() async {
    try {
      final bytes = await _io.readWholeFile(_vault, filePath);
      if (bytes == null || bytes.isEmpty) {
        loadAll(const {});
        return;
      }
      loadAll(SyncLedgerCodec.decode(utf8.decode(bytes)));
    } catch (e) {
      VeLog.w(_tag, 'ledger unreadable, starting empty', e);
      loadAll(const {});
    }
  }

  @override
  Future<bool> flush() async {
    final inProgress = _flushing;
    if (inProgress != null) await inProgress;
    if (!isDirty) return true;

    final attempt = _write();
    _flushing = attempt;
    try {
      return await attempt;
    } finally {
      if (identical(_flushing, attempt)) _flushing = null;
    }
  }

  Future<bool> _write() async {
    try {
      if (!_metaDirEnsured) {
        // Fails harmlessly if the folder already exists.
        await _io.createDirectory(_vault, kVaultMetaDir);
        _metaDirEnsured = true;
      }
      final bytes = Uint8List.fromList(utf8.encode(SyncLedgerCodec.encode(rules)));
      final ok = await _io.writeWholeFile(_vault, filePath, bytes);
      if (ok) markClean();
      return ok;
    } catch (e) {
      VeLog.w(_tag, 'ledger flush failed', e);
      return false;
    }
  }

  @override
  Future<void> close() async {
    await flush();
  }
}
