// Import / export between the host filesystem and an unlocked vault, for the desktop engine.
//
// Android does this with SAF pickers + a long Kotlin handler (ImportExportHandlers.kt). The
// contract the Dart layer relies on is what this file reproduces:
//
//   pickImportFiles / pickImportFolder   -> {pickToken, conflicts, items}; nothing is written yet
//   prepareDropImport                    -> the same result for paths dropped from the OS file manager
//                                           (no dialog; files and folders may be mixed)
//   importFile / importFolder            -> resumes a pick by token with a conflictPlan; returns the
//                                           number of entries written
//   exportFilesToFolder / exportFileToStorage / decryptFile / cancel* / deleteImportSources ...
//
// Progress reaches Dart as the same `onImportProgress` / `onImportItemFinished` /
// `onExportProgress` / `onExportItemFinished` / `onCopyProgress` pushes. The byte counts come from
// the engine's own per-chunk callbacks (drained by the host's event pump); entry counts are kept
// here.
//
// The import rules are Android's (ImportExportHandlers.kt), kept as pure functions in
// desktop_import_policy.dart: a name the destination filesystem cannot hold is skipped and reported
// (`onImportItemSkipped`); siblings that differ only by case on a case-insensitive destination are
// imported under unique names instead of replacing each other; every file is hashed (SHA-256) before
// it is written and read back out of the vault afterwards, and a mismatch fails the import. A source
// is only offered for "delete after import" when every picked item was written, the read-back
// matched, and the import ran to the end.
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';

import 'desktop_import_policy.dart';
import 'dropped_paths.dart';
import 'engine_worker_pool.dart';
import 've_native.dart';

class _VaultEntry {
  _VaultEntry(this.name, this.isDir, this.sizeBytes);
  final String name;
  final bool isDir;
  final int sizeBytes;
}

class _PickedEntry {
  _PickedEntry(this.name, this.hostPath, this.isDir, this.sizeBytes);
  final String name;
  final String hostPath;
  final bool isDir;
  final int sizeBytes;
}

class _Pick {
  _Pick(this.vol, this.targetDir, this.caseSensitive, this.entries);
  final int vol;
  final String targetDir;
  final bool caseSensitive;
  final List<_PickedEntry> entries;
}

class _Progress {
  int done = 0;
  int total = 0;
  int transferred = 0;
  int totalBytes = 0;
  String currentName = '';
}

/// What one import run needs while it walks the picked entries.
class _ImportRun {
  _ImportRun(this.fsType, this.caseSensitive);

  /// The rule set the destination's names are checked against (see [DesktopTransfers._nameRules]).
  final FilesystemType? fsType;
  final bool caseSensitive;

  /// Every file written so far, with the SHA-256 of the source bytes it was written from.
  final List<({String vaultPath, Uint8List sha256})> verifications = [];
}

class _ImportSources {
  _ImportSources(this.paths, this.verified);
  final List<String> paths;
  final bool verified;
}

class DesktopTransfers {
  DesktopTransfers({
    required this.pool,
    required this.volFor,
    required this.emit,
    required this.native,
    required this.withActivity,
  });

  final EngineWorkerPool pool;
  final int Function(Object? uri) volFor;
  final void Function(String method, Object? arguments) emit;

  /// The main-isolate engine handle (operation registry + cancellation are process-wide).
  final VeNative Function() native;

  /// Keeps the host's event pump running while [body] is in flight.
  final Future<Object?> Function(Future<Object?> Function() body) withActivity;

  int _nextToken = 1;
  final Map<int, _Pick> _picks = {};
  final Map<int, _Progress> _importProgress = {};
  final Map<int, _Progress> _exportProgress = {};
  final Set<int> _cancelled = {};
  final Map<int, _ImportSources> _importSources = {};

  // ── native event routing (called by the host's pump) ────────────────────

  void onNativeEvent(VeNativeEvent e) {
    switch (e.kind) {
      case veEventCopyProgress:
        emit('onCopyProgress', {'opId': e.opId, 'bytesDelta': e.n0});
      case veEventImportProgress:
        {
          final s = _importProgress[e.opId];
          if (s == null) return;
          s.transferred += e.n0;
          _emitProgress('onImportProgress', e.opId, s);
        }
      case veEventExportProgress:
        {
          final s = _exportProgress[e.opId];
          if (s == null) return;
          s.transferred += e.n0;
          _emitProgress('onExportProgress', e.opId, s);
        }
    }
  }

  void _emitProgress(String method, int opId, _Progress s) => emit(method, {
        'opId': opId,
        'done': s.done,
        'total': s.total,
        'currentName': s.currentName,
        'transferredBytes': s.transferred,
        'totalBytes': s.totalBytes,
      });

  // ── helpers ─────────────────────────────────────────────────────────────

  static String _fold(String name, bool caseSensitive) => foldName(name, caseSensitive);

  static String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

  /// "name" -> "name (1)" -> "name (2)" ... keeping the extension (same scheme as Android).
  static String _unique(Set<String> takenFolded, String name, bool caseSensitive) =>
      uniqueNameAgainst(takenFolded, name, caseSensitive: caseSensitive);

  /// Parses the engine's directory-entry wire string: "<F|D>|<size>|<mtime>|<name>".
  static _VaultEntry? _parseEntry(String wire) {
    if (wire.startsWith('System:')) return null;
    final a = wire.indexOf('|');
    if (a < 0) return null;
    final b = wire.indexOf('|', a + 1);
    if (b < 0) return null;
    final c = wire.indexOf('|', b + 1);
    if (c < 0) return null;
    return _VaultEntry(wire.substring(c + 1), wire[0] == 'D', int.tryParse(wire.substring(a + 1, b)) ?? 0);
  }

  Future<List<_VaultEntry>> _listVault(int vol, String dir) async {
    final r = await pool.call('list', [vol, dir]) as List<Object?>;
    if (r[0] != veOk) return const [];
    return [
      for (final w in (r[1] as List<Object?>).cast<String>())
        if (_parseEntry(w) case final _VaultEntry e) e,
    ];
  }

  Future<bool> _deleteVaultRecursive(int vol, String path, bool isDir) async {
    if (!isDir) return (await pool.call('delete', [vol, path]) as int) == veOk;
    var ok = true;
    for (final child in await _listVault(vol, path)) {
      if (!await _deleteVaultRecursive(vol, _join(path, child.name), child.isDir)) ok = false;
    }
    return (await pool.call('delete', [vol, path]) as int) == veOk && ok;
  }

  Future<(int, int)> _countHost(String path, bool isDir) async {
    if (!isDir) return (1, await File(path).length());
    var count = 1;
    var bytes = 0;
    await for (final e in Directory(path).list(recursive: true, followLinks: false)) {
      if (e is Directory) {
        count++;
      } else if (e is File) {
        count++;
        bytes += await e.length();
      }
    }
    return (count, bytes);
  }

  Future<(int, int)> _countVault(int vol, String path, bool isDir) async {
    if (!isDir) return (1, (await pool.call('fileSize', [vol, path]) as int).clamp(0, 1 << 62).toInt());
    var count = 1;
    var bytes = 0;
    for (final child in await _listVault(vol, path)) {
      final (c, b) = await _countVault(vol, _join(path, child.name), child.isDir);
      count += c;
      bytes += b;
    }
    return (count, bytes);
  }

  /// Android's INSUFFICIENT_SPACE guard: stop before writing anything if the batch cannot fit
  /// (with a 1% safety margin for filesystem overhead). Skipped when free space is unknown.
  Future<void> _requireSpace(int vol, int neededBytes) async {
    final r = await pool.call('space', [vol]) as List<Object?>;
    if (r[0] != veOk) return;
    final free = (r[1] as List<Object?>).cast<int>()[1];
    if (fitsWithinSafetyMargin(neededBytes, free)) return;
    throw PlatformException(
      code: 'INSUFFICIENT_SPACE',
      message: 'Not enough free space in the vault: need $neededBytes bytes, only $free available',
      details: {'neededBytes': neededBytes, 'availableBytes': free},
    );
  }

  bool _isCancelled(int opId) => opId > 0 && _cancelled.contains(opId);

  // ── import: phase 1 (pick) ──────────────────────────────────────────────

  Future<Object?> pickImportFiles(Map<Object?, Object?> args) async {
    final vol = volFor(args['filePath']);
    final files = await openFiles();
    if (files.isEmpty) return null;
    final entries = <_PickedEntry>[];
    for (final f in files) {
      entries.add(_PickedEntry(p.basename(f.path), f.path, false, await File(f.path).length()));
    }
    return _registerPick(vol, args, entries);
  }

  Future<Object?> pickImportFolder(Map<Object?, Object?> args) async {
    final vol = volFor(args['filePath']);
    final dir = await getDirectoryPath();
    if (dir == null) return null;
    return _registerPick(vol, args, [_PickedEntry(p.basename(dir), dir, true, 0)]);
  }

  /// Drag-and-drop counterpart of the two pickers: [args]`['paths']` are host paths the OS file manager
  /// dropped on the window. Returns the same `{pickToken, conflicts, items}` shape (nothing is written
  /// yet), or `null` when none of the paths can be imported -- see [resolveDroppedPaths] for what is
  /// left out. Files and folders can be mixed in one drop; [importPicked] already handles both.
  Future<Object?> prepareDropImport(Map<Object?, Object?> args) async {
    final vol = volFor(args['filePath']);
    final dropped = resolveDroppedPaths(
      ((args['paths'] as List<Object?>?) ?? const []).whereType<String>(),
      // On desktop the container "URI" is its own filesystem path.
      vaultHostPath: args['filePath'] as String?,
    );
    final entries = <_PickedEntry>[];
    for (final e in dropped.accepted) {
      var size = 0;
      if (!e.isDir) {
        try {
          size = await File(e.path).length();
        } on FileSystemException {
          continue; // vanished between the drop and now
        }
      }
      entries.add(_PickedEntry(p.basename(e.path), e.path, e.isDir, size));
    }
    if (entries.isEmpty) return null;
    return _registerPick(vol, args, entries);
  }

  Future<Object?> _registerPick(int vol, Map<Object?, Object?> args, List<_PickedEntry> entries) async {
    final targetDir = (args['targetPath'] as String?) ?? '';
    final caseSensitive = args['caseSensitive'] == true;
    final existing = {
      for (final e in await _listVault(vol, targetDir)) _fold(e.name, caseSensitive): e.isDir,
    };
    final token = _nextToken++;
    _picks[token] = _Pick(vol, targetDir, caseSensitive, entries);
    return {
      'pickToken': token,
      'conflicts': [
        for (final e in entries)
          if (existing.containsKey(_fold(e.name, caseSensitive)))
            {'name': e.name, 'destIsDir': existing[_fold(e.name, caseSensitive)]},
      ],
      'items': [
        for (final e in entries) {'name': e.name, 'isDir': e.isDir, 'sizeBytes': e.sizeBytes},
      ],
    };
  }

  void cancelPickedImport(Object? token) {
    if (token is num) _picks.remove(token.toInt());
  }

  // ── import: phase 2 (write) ─────────────────────────────────────────────

  Future<Object?> importPicked(Map<Object?, Object?> args) async {
    final opId = (args['opId'] as num?)?.toInt() ?? 0;
    final token = (args['pickToken'] as num?)?.toInt();
    final pick = token == null ? null : _picks.remove(token);
    if (pick == null) {
      throw PlatformException(
        code: 'INVALID_ARGS',
        message: 'pickToken is required and must reference a pending pick',
      );
    }
    final plan = <String, String>{
      for (final e in ((args['conflictPlan'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
    };
    final vol = pick.vol;
    final run = _ImportRun(await _nameRules(vol), pick.caseSensitive);

    // Totals up front, so progress has a denominator and the space check can run first.
    var total = 0;
    var totalBytes = 0;
    final expected = <int>[];
    for (final e in pick.entries) {
      final (c, b) = await _countHost(e.hostPath, e.isDir);
      expected.add(c);
      total += c;
      totalBytes += b;
    }
    await _requireSpace(vol, totalBytes);

    final progress = _Progress()
      ..total = total
      ..totalBytes = totalBytes;
    if (opId > 0) {
      _importProgress[opId] = progress;
      native().opRegister(opId, veOpImport);
      _emitProgress('onImportProgress', opId, progress);
    }

    try {
      return await withActivity(() async {
        final existing = {
          for (final e in await _listVault(vol, pick.targetDir)) _fold(e.name, pick.caseSensitive): e.isDir,
        };
        final taken = existing.keys.toSet();
        final reports = <({String source, String resolved, bool isDir, bool success})>[];
        var successCount = 0;

        for (var i = 0; i < pick.entries.length; i++) {
          if (_isCancelled(opId)) break;
          final entry = pick.entries[i];
          final issues = importNameIssues(entry.name, run.fsType, isDir: entry.isDir);
          if (issues.isNotEmpty) {
            _reportSkipped(opId, entry.name, issues);
            reports.add((source: entry.name, resolved: entry.name, isDir: entry.isDir, success: false));
            continue;
          }
          final key = _fold(entry.name, pick.caseSensitive);

          String? name;
          switch (plan[key]) {
            case 'skip':
              name = null;
            case 'overwrite':
              if (existing.containsKey(key)) {
                await _deleteVaultRecursive(vol, _join(pick.targetDir, entry.name), existing[key]!);
              }
              name = entry.name;
              taken.add(key);
            default:
              name = _unique(taken, entry.name, pick.caseSensitive);
              taken.add(_fold(name, pick.caseSensitive));
          }
          if (name == null) {
            reports.add((source: entry.name, resolved: entry.name, isDir: entry.isDir, success: false));
            continue;
          }

          progress.currentName = entry.name;
          final count =
              await _importEntry(vol, entry.hostPath, _join(pick.targetDir, name), entry.isDir, opId, progress, run);
          successCount += count;
          reports.add((
            source: entry.name,
            resolved: name,
            isDir: entry.isDir,
            success: count == expected[i] && (count > 0 || !entry.isDir),
          ));
        }

        // Read every written file back out of the vault and compare it with its source. Throws on a mismatch;
        // false when the import was cancelled before everything could be checked.
        final verified = await _verifyImports(vol, run.verifications, opId);

        for (final r in reports) {
          if (opId > 0) {
            emit('onImportItemFinished', {
              'opId': opId,
              'sourceName': r.source,
              'resolvedName': r.resolved,
              'isDir': r.isDir,
              'success': r.success,
            });
          }
        }
        // Only a complete, verified run makes the sources deletable: every picked entry was processed (a
        // cancelled run leaves some untouched), every one was written, and the read-back matched.
        if (opId > 0 &&
            verified &&
            !_isCancelled(opId) &&
            reports.length == pick.entries.length &&
            reports.every((r) => r.success)) {
          _importSources[opId] = _ImportSources([for (final e in pick.entries) e.hostPath], true);
        }
        return successCount;
      });
    } finally {
      if (opId > 0) {
        native().opUnregister(opId);
        _importProgress.remove(opId);
        _cancelled.remove(opId);
      }
    }
  }

  Future<int> _importEntry(
    int vol,
    String hostPath,
    String vaultPath,
    bool isDir,
    int opId,
    _Progress progress,
    _ImportRun run,
  ) async {
    if (!isDir) {
      // Hash the bytes about to be written; the read-back after the import is compared with this.
      final expected = await _sha256OfHostFile(hostPath, opId);
      if (expected == null) return 0; // cancelled while reading the source
      final rc = await pool.call('import', [vol, vaultPath, hostPath, opId]) as int;
      progress.done++;
      if (opId > 0) _emitProgress('onImportProgress', opId, progress);
      if (rc != veOk) return 0;
      run.verifications.add((vaultPath: vaultPath, sha256: expected));
      return 1;
    }
    if ((await pool.call('mkdir', [vol, vaultPath]) as int) != veOk) return 0;
    var count = 1;
    progress.done++;

    // The whole listing first: which children collide on this destination depends on all of them. Sorted, so
    // the same folder always gives the same result (the later of two colliding names is the one renamed).
    final children = <({String name, String path, bool isDir})>[];
    await for (final child in Directory(hostPath).list(followLinks: false)) {
      if (_isCancelled(opId)) break;
      if (child is Directory) {
        children.add((name: p.basename(child.path), path: child.path, isDir: true));
      } else if (child is File) {
        children.add((name: p.basename(child.path), path: child.path, isDir: false));
      }
    }
    children.sort((a, b) => a.name.compareTo(b.name));

    final plans = planChildImports(
      [for (final c in children) ImportChild(c.name, isDir: c.isDir)],
      fsType: run.fsType,
      caseSensitive: run.caseSensitive,
    );
    for (var i = 0; i < children.length; i++) {
      if (_isCancelled(opId)) break;
      final child = children[i];
      final plan = plans[i];
      if (plan.isSkipped) {
        _reportSkipped(opId, child.name, plan.skipReasons);
        continue;
      }
      if (!child.isDir) progress.currentName = child.name;
      count += await _importEntry(vol, child.path, _join(vaultPath, plan.destName!), child.isDir, opId, progress, run);
    }
    return count;
  }

  /// Which rules a name must satisfy to be imported into [vol] -- Android's `FilesystemNameValidator.kindFor`: a
  /// folder vault (gocryptfs / Cryptomator / CryFS, native format codes from 10) takes the encrypted-vault
  /// rules; every disk-image container takes the conservative union of FAT / exFAT / NTFS / ext, so a name that
  /// imports can also be exported to any of them.
  Future<FilesystemType> _nameRules(int vol) async {
    final format = await pool.call('containerFormat', [vol]) as int;
    return format >= 10 ? FilesystemType.encryptedVault : FilesystemType.unknownConservative;
  }

  /// Tells the UI layer an entry was left out because the destination cannot hold its name (Android sends the
  /// same `onImportItemSkipped`).
  void _reportSkipped(int opId, String name, List<String> reasons) {
    if (opId <= 0) return;
    emit('onImportItemSkipped', {'opId': opId, 'name': name, 'reason': reasons.join('; ')});
  }

  // ── read-back verification ──────────────────────────────────────────────

  static const int _hashStep = 4 << 20;

  static PlatformException _verifyFailure(String message) => PlatformException(code: 'C++_ERROR', message: message);

  /// SHA-256 of a host file, or null when [opId] was cancelled while reading it.
  Future<Uint8List?> _sha256OfHostFile(String path, int opId) async {
    final handle = await pool.call('hashBegin', [1 << veHashSha256]) as int;
    if (handle == 0) throw _verifyFailure('could not open a hash session');
    RandomAccessFile? raf;
    try {
      raf = await File(path).open();
      while (true) {
        if (_isCancelled(opId)) return null;
        final chunk = await raf.read(_hashStep);
        if (chunk.isEmpty) break;
        if (await pool.call('hashUpdate', [handle, chunk]) != veOk) throw _verifyFailure('hash update failed');
      }
      return await _finishSha256(handle);
    } on FileSystemException catch (e) {
      throw PlatformException(code: 'IO_ERROR', message: e.message);
    } finally {
      await raf?.close();
      await pool.call('hashFree', [handle]);
    }
  }

  /// SHA-256 of the plaintext of a vault file, read back in [_hashStep] pieces; null when [opId] was cancelled.
  Future<Uint8List?> _sha256OfVaultFile(int vol, String path, int opId) async {
    final size = await pool.call('fileSize', [vol, path]) as int;
    if (size < 0) throw _verifyFailure('Imported file could not be verified');
    final handle = await pool.call('hashBegin', [1 << veHashSha256]) as int;
    if (handle == 0) throw _verifyFailure('could not open a hash session');
    try {
      var offset = 0;
      while (offset < size) {
        if (_isCancelled(opId)) return null;
        final want = size - offset < _hashStep ? size - offset : _hashStep;
        final r = await pool.call('read', [vol, path, offset, want]) as List<Object?>;
        final chunk = r[1] as Uint8List?;
        if (r[0] != veOk || chunk == null || chunk.isEmpty) {
          throw _verifyFailure('Imported file could not be verified');
        }
        if (await pool.call('hashUpdate', [handle, chunk]) != veOk) throw _verifyFailure('hash update failed');
        offset += chunk.length;
      }
      return await _finishSha256(handle);
    } finally {
      await pool.call('hashFree', [handle]);
    }
  }

  Future<Uint8List> _finishSha256(int handle) async {
    final r = await pool.call('hashFinish', [handle, veHashSha256]) as List<Object?>;
    if (r[0] != veOk) throw _verifyFailure('digest failed');
    return r[1] as Uint8List;
  }

  /// Compares every imported file with the digest taken from its source (Android:
  /// ImportExportHandlers.verifyCommittedImports). Throws when one differs; returns false when the import was
  /// cancelled before all of them were checked.
  Future<bool> _verifyImports(int vol, List<({String vaultPath, Uint8List sha256})> items, int opId) async {
    for (final item in items) {
      if (_isCancelled(opId)) return false;
      final actual = await _sha256OfVaultFile(vol, item.vaultPath, opId);
      if (actual == null) return false;
      if (!digestsEqual(item.sha256, actual)) throw _verifyFailure('Imported file integrity verification failed');
    }
    return true;
  }

  /// Delete-after-import: only offered (non-zero) when every picked item was written.
  Future<int> deleteImportSources(int opId) async {
    final record = _importSources.remove(opId);
    if (record == null || !record.verified) return 0;
    var deleted = 0;
    for (final path in record.paths) {
      try {
        final type = FileSystemEntity.typeSync(path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          await Directory(path).delete(recursive: true);
          deleted++;
        } else if (type == FileSystemEntityType.file) {
          await File(path).delete();
          deleted++;
        }
      } on FileSystemException {
        // leave it; the caller reports how many were removed
      }
    }
    return deleted;
  }

  void clearImportSources(int opId) => _importSources.remove(opId);

  // ── export ──────────────────────────────────────────────────────────────

  Future<Object?> exportToFolder(Map<Object?, Object?> args) async {
    final vol = volFor(args['filePath']);
    final opId = (args['opId'] as num?)?.toInt() ?? 0;
    final items = [
      for (final i in (args['items'] as List<Object?>? ?? const []))
        if (i is Map && i['path'] is String) (path: i['path'] as String, isDir: i['isDir'] == true),
    ];
    final destDir = await getDirectoryPath();
    if (destDir == null) return 0;

    var total = 0;
    var totalBytes = 0;
    for (final i in items) {
      final (c, b) = await _countVault(vol, i.path, i.isDir);
      total += c;
      totalBytes += b;
    }
    final progress = _Progress()
      ..total = total
      ..totalBytes = totalBytes;
    if (opId > 0) {
      _exportProgress[opId] = progress;
      native().opRegister(opId, veOpExport);
      _emitProgress('onExportProgress', opId, progress);
    }
    try {
      return await withActivity(() async {
        // Names already present in the destination (and earlier items of this batch) are never
        // overwritten: later ones get "name (1)". Compared case-insensitively, which is what
        // Windows/macOS destinations need and is harmless on Linux.
        final taken = <String>{
          for (final e in Directory(destDir).listSync(followLinks: false)) p.basename(e.path).toLowerCase(),
        };
        var successCount = 0;
        for (final item in items) {
          if (_isCancelled(opId)) break;
          final sourceName = item.path.split('/').last;
          final destName = _unique(taken, sourceName, false);
          taken.add(destName.toLowerCase());
          progress.currentName = sourceName;
          final count = await _exportEntry(vol, item.path, item.isDir, p.join(destDir, destName), opId, progress);
          successCount += count;
          if (opId > 0) {
            emit('onExportItemFinished', {
              'opId': opId,
              'sourceName': sourceName,
              'isDir': item.isDir,
              'success': count > 0,
            });
          }
        }
        return successCount;
      });
    } finally {
      if (opId > 0) {
        native().opUnregister(opId);
        _exportProgress.remove(opId);
        _cancelled.remove(opId);
      }
    }
  }

  Future<int> _exportEntry(int vol, String vaultPath, bool isDir, String destPath, int opId, _Progress progress) async {
    if (!isDir) {
      final rc = await pool.call('export', [vol, vaultPath, destPath, opId]) as int;
      progress.done++;
      if (opId > 0) _emitProgress('onExportProgress', opId, progress);
      if (rc != veOk) {
        // Cancelled or failed mid-file: never leave a truncated plaintext copy behind.
        try {
          await File(destPath).delete();
        } on FileSystemException {
          // nothing was created
        }
        return 0;
      }
      return 1;
    }
    await Directory(destPath).create(recursive: true);
    var count = 1;
    progress.done++;
    for (final child in await _listVault(vol, vaultPath)) {
      if (_isCancelled(opId)) break;
      progress.currentName = child.name;
      count += await _exportEntry(vol, _join(vaultPath, child.name), child.isDir, p.join(destPath, child.name), opId, progress);
    }
    return count;
  }

  /// Single-file export with a "save as" dialog.
  Future<bool> exportFileToStorage(Map<Object?, Object?> args) async {
    final vol = volFor(args['filePath']);
    final sourcePath = args['sourcePath'] as String;
    final location = await getSaveLocation(suggestedName: sourcePath.split('/').last);
    if (location == null) return false;
    final rc = await withActivity(() => pool.call('export', [vol, sourcePath, location.path, 0])) as int;
    if (rc != veOk) {
      try {
        await File(location.path).delete();
      } on FileSystemException {
        // nothing was created
      }
    }
    return rc == veOk;
  }

  /// Extracts one vault file to a host path chosen by the app (cache file for viewers, etc.).
  Future<bool> decryptFile(Map<Object?, Object?> args) async {
    final vol = volFor(args['filePath']);
    final opId = (args['opId'] as num?)?.toInt() ?? 0;
    final dest = args['destPath'] as String;
    await Directory(p.dirname(dest)).create(recursive: true);
    if (opId > 0) native().opRegister(opId, veOpExport);
    try {
      final rc = await withActivity(() => pool.call('export', [vol, args['fileName'], dest, opId])) as int;
      if (rc != veOk) {
        try {
          await File(dest).delete();
        } on FileSystemException {
          // nothing was created
        }
      }
      return rc == veOk;
    } finally {
      if (opId > 0) {
        native().opUnregister(opId);
        _cancelled.remove(opId);
      }
    }
  }

  /// Writes one host file into a vault path (the reverse of [decryptFile]). Android's `writeBackFile` is the
  /// same engine call the import path uses (`fsWriteBackFile` for a block volume), so this is `ve_import_file`
  /// for a single file with no picker, no unique-name policy and no import-source bookkeeping: the caller
  /// already chose the exact vault path. A failed or cancelled write leaves nothing to clean up here, the
  /// engine removes its own partial file.
  Future<bool> writeBackFile(Map<Object?, Object?> args) async {
    final fileName = args['fileName'];
    final sourcePath = args['sourcePath'];
    if (fileName is! String || sourcePath is! String) {
      throw PlatformException(code: 'INVALID_ARGS', message: 'fileName and sourcePath required');
    }
    final vol = volFor(args['filePath']);
    final opId = (args['opId'] as num?)?.toInt() ?? 0;
    if (opId > 0) native().opRegister(opId, veOpImport);
    try {
      final rc = await withActivity(() => pool.call('import', [vol, fileName, sourcePath, opId])) as int;
      return rc == veOk;
    } finally {
      if (opId > 0) {
        native().opUnregister(opId);
        _cancelled.remove(opId);
      }
    }
  }

  // ── cancellation ────────────────────────────────────────────────────────

  void cancel(int opId) {
    if (opId <= 0) return;
    _cancelled.add(opId);
    native().opCancel(opId);
  }
}
