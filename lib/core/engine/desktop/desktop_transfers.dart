// Import / export between the host filesystem and an unlocked vault, for the desktop engine.
//
// Android does this with SAF pickers + a long Kotlin handler (ImportExportHandlers.kt). The
// contract the Dart layer relies on is what this file reproduces:
//
//   pickImportFiles / pickImportFolder   -> {pickToken, conflicts, items}; nothing is written yet
//   importFile / importFolder            -> resumes a pick by token with a conflictPlan; returns the
//                                           number of entries written
//   exportFilesToFolder / exportFileToStorage / decryptFile / cancel* / deleteImportSources ...
//
// Progress reaches Dart as the same `onImportProgress` / `onImportItemFinished` /
// `onExportProgress` / `onExportItemFinished` / `onCopyProgress` pushes. The byte counts come from
// the engine's own per-chunk callbacks (drained by the host's event pump); entry counts are kept
// here.
//
// Differences from Android, deliberately left for later: per-filesystem file-name validation
// (the engine rejects an illegal name when it writes it) and the post-import SHA-256 read-back
// verification. A source is therefore only offered for "delete after import" when every picked
// item was written successfully.
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

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

  static String _fold(String name, bool caseSensitive) => caseSensitive ? name : name.toLowerCase();

  static String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

  /// "name" -> "name (1)" -> "name (2)" ... keeping the extension (same scheme as Android).
  static String _unique(Set<String> takenFolded, String name, bool caseSensitive) {
    if (!takenFolded.contains(_fold(name, caseSensitive))) return name;
    final dot = name.lastIndexOf('.');
    final hasExt = dot > 0 && dot < name.length - 1;
    final base = hasExt ? name.substring(0, dot) : name;
    final ext = hasExt ? name.substring(dot) : '';
    for (var n = 1;; n++) {
      final candidate = '$base ($n)$ext';
      if (!takenFolded.contains(_fold(candidate, caseSensitive))) return candidate;
    }
  }

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
    if (neededBytes * 1.01 <= free) return;
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
          final count = await _importEntry(vol, entry.hostPath, _join(pick.targetDir, name), entry.isDir, opId, progress);
          successCount += count;
          reports.add((
            source: entry.name,
            resolved: name,
            isDir: entry.isDir,
            success: count == expected[i] && (count > 0 || !entry.isDir),
          ));
        }

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
        if (opId > 0 && reports.isNotEmpty && reports.every((r) => r.success)) {
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

  Future<int> _importEntry(int vol, String hostPath, String vaultPath, bool isDir, int opId, _Progress progress) async {
    if (!isDir) {
      final rc = await pool.call('import', [vol, vaultPath, hostPath, opId]) as int;
      progress.done++;
      if (opId > 0) _emitProgress('onImportProgress', opId, progress);
      return rc == veOk ? 1 : 0;
    }
    if ((await pool.call('mkdir', [vol, vaultPath]) as int) != veOk) return 0;
    var count = 1;
    progress.done++;
    await for (final child in Directory(hostPath).list(followLinks: false)) {
      if (_isCancelled(opId)) break;
      final name = p.basename(child.path);
      if (child is Directory) {
        count += await _importEntry(vol, child.path, _join(vaultPath, name), true, opId, progress);
      } else if (child is File) {
        progress.currentName = name;
        count += await _importEntry(vol, child.path, _join(vaultPath, name), false, opId, progress);
      }
    }
    return count;
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

  // ── cancellation ────────────────────────────────────────────────────────

  void cancel(int opId) {
    if (opId <= 0) return;
    _cancelled.add(opId);
    native().opCancel(opId);
  }
}
