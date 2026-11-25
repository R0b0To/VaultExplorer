// Browsing and extracting archives (zip, 7z, rar, tar.*, iso, cpio, split sets) for the desktop engine.
//
// The work is done by the archive engine behind `ve_archive_*` (ffi/ve_archive.cpp); this class is the Dart half
// of the engine channel's archive methods: it maps the method arguments onto those calls, decodes the result
// record (layout in ve_engine.h) into the maps the Dart models expect, and manages the one place where desktop
// needs a plaintext file.
//
//   * An archive INSIDE a vault is read straight from the vault's stream -- no copy, folder vaults included
//     (Android stages those to cache files; here nothing plaintext touches the disk).
//   * "Browse staging" (an entry opened in a viewer, or a large entry queued for transfer) streams the entry into
//     one private file. That file lives in a fresh owner-only directory under $XDG_RUNTIME_DIR (a memory-backed
//     tmpfs on Linux) or the system temp directory, only files named `archive_browse_*` in it can be discarded
//     through the API, everything is removed when the vault it came from is locked and at shutdown, and a crashed
//     run's directory is purged the next time the app starts.
//   * Extracting into a vault goes through the vault's own write path (and the folder-vault write batch).
//
//   * Creating an archive (`archiveCreate`) reads its sources and writes its result the same way, so a folder
//     vault source or destination needs no staging either. The one exception is the temporary file the 7z and ISO
//     writers assemble their output in: it goes to a private folder under the system temp directory that exists
//     only for the duration of the call.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/utils/secure_temp_file.dart';

import 've_native.dart' show veErrNotUnlocked, veOk;

/// One call into the engine worker (`EngineWorkerPool.call`).
typedef EngineCall = Future<Object?> Function(String op, List<Object?> args);

/// Decoded `ve_archive_*` result record.
class ArchiveRecord {
  const ArchiveRecord({
    required this.status,
    required this.flags,
    required this.count,
    required this.message,
    this.entries = const [],
  });

  /// 0 ok, 1 unsupported format, 2 passphrase required, 3 wrong passphrase, 4 I/O error.
  final int status;
  final int flags;
  final int count;
  final String message;
  final List<Map<String, Object?>> entries;

  bool get isSolid => flags & 1 != 0;
  bool get isSevenZip => flags & 2 != 0;
  bool get cancelled => flags & 4 != 0;

  static const int statusIoError = 4;

  factory ArchiveRecord.failed(String message) =>
      ArchiveRecord(status: statusIoError, flags: 0, count: 0, message: message);

  /// Null when [bytes] is not a well-formed record.
  static ArchiveRecord? tryParse(Uint8List bytes, {bool withEntries = false}) {
    try {
      final d = ByteData.sublistView(bytes);
      var pos = 0;
      int u32() {
        final v = d.getUint32(pos, Endian.little);
        pos += 4;
        return v;
      }

      int u64() {
        final v = d.getUint64(pos, Endian.little);
        pos += 8;
        return v;
      }

      int i64() {
        final v = d.getInt64(pos, Endian.little);
        pos += 8;
        return v;
      }

      String str() {
        final len = u32();
        final s = utf8.decode(Uint8List.sublistView(bytes, pos, pos + len), allowMalformed: true);
        pos += len;
        return s;
      }

      final status = u32();
      final flags = u32();
      final count = u32();
      final message = str();
      final entries = <Map<String, Object?>>[];
      if (withEntries) {
        for (var i = 0; i < count; i++) {
          final path = str();
          final uncompressed = u64();
          final compressed = u64();
          final mtime = i64();
          final entryFlags = u32();
          final index = d.getInt32(pos, Endian.little);
          pos += 4;
          entries.add({
            'path': path,
            'uncompressedSize': uncompressed,
            'compressedSize': compressed,
            'modTimeEpochSeconds': mtime,
            'isEncrypted': entryFlags & 1 != 0,
            'isDirectory': entryFlags & 2 != 0,
            'index': index,
          });
        }
      }
      return ArchiveRecord(status: status, flags: flags, count: count, message: message, entries: entries);
    } on RangeError {
      return null;
    }
  }
}

class DesktopArchive {
  DesktopArchive({
    required this.call,
    required this.volFor,
    required this.volOrNull,
    required this.isFolderVault,
    required this.registerOp,
    required this.unregisterOp,
    required this.withActivity,
  });

  final EngineCall call;

  /// The slot of an unlocked container (throws the host's NOT_MOUNTED error otherwise).
  final int Function(Object? uri) volFor;

  /// The slot of an unlocked container, or null when [uri] is not one (a plain folder).
  final int? Function(Object? uri) volOrNull;
  final bool Function(int vol) isFolderVault;

  /// Declares / drops an operation id so `cancelSplitJoin` can stop an extraction (VeNative.opRegister).
  final void Function(int opId) registerOp;
  final void Function(int opId) unregisterOp;

  /// Keeps the host's event pump (progress) running while [body] is in flight.
  final Future<Object?> Function(Future<Object?> Function() body) withActivity;

  static const String _stagingPrefix = 'vaultexplorer-archive-';
  static const String _browsePrefix = 'archive_browse_';

  Directory? _stagingDir;
  bool _purgedStale = false;
  int _nextStaged = 1;
  final Map<int, Set<String>> _stagedByVolume = {}; // -1: staged from a host archive

  static PlatformException _invalid(String what) => PlatformException(code: 'INVALID_ARGS', message: what);

  static String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

  /// A host archive is addressed by path (Android also accepts a SAF URI; a `file://` URI is the desktop analogue).
  static String _localPath(String pathOrUri) {
    if (pathOrUri.startsWith('file:')) {
      try {
        return Uri.parse(pathOrUri).toFilePath();
      } on UnsupportedError {
        return pathOrUri;
      }
    }
    return pathOrUri;
  }

  /// (slot or -1, path) of the archive an `archive*` method names: in the vault when `vaultPath` is given.
  (int, String) _source(Map<Object?, Object?> args) {
    final filePath = _nonEmpty(args['filePath']) ?? _nonEmpty(args['localUri']);
    if (filePath == null) throw _invalid('filePath required');
    final vaultPath = _nonEmpty(args['vaultPath']);
    if (vaultPath != null) return (volFor(filePath), vaultPath);
    return (-1, _localPath(filePath));
  }

  ArchiveRecord _record(Object? raw, {bool withEntries = false}) {
    final r = raw as List<Object?>;
    final rc = r[0] as int;
    if (rc == veErrNotUnlocked) throw PlatformException(code: 'NOT_UNLOCKED', message: 'NOT_UNLOCKED');
    final bytes = r[1] as Uint8List?;
    if (rc != veOk || bytes == null) return ArchiveRecord.failed('The archive operation failed (engine code $rc)');
    return ArchiveRecord.tryParse(bytes, withEntries: withEntries) ??
        ArchiveRecord.failed('The archive result could not be read');
  }

  // ── scan ────────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> scanVault(Map<Object?, Object?> args) {
    if (_nonEmpty(args['vaultPath']) == null) throw _invalid('filePath and vaultPath required');
    return _scan(args);
  }

  Future<Map<String, Object?>> scanLocal(Map<Object?, Object?> args) => _scan(args);

  Future<Map<String, Object?>> _scan(Map<Object?, Object?> args) async {
    final (vol, path) = _source(args);
    final rec = _record(await call('archiveScan', [vol, path, _nonEmpty(args['passphrase'])]), withEntries: true);
    return {
      'status': rec.status,
      'entries': rec.entries,
      'isSolid': rec.isSolid,
      'isSevenZip': rec.isSevenZip,
      'errorMessage': rec.message,
    };
  }

  // ── one entry, into memory ───────────────────────────────────────────────

  Future<Map<String, Object?>> extractVaultEntry(Map<Object?, Object?> args) {
    if (_nonEmpty(args['vaultPath']) == null) throw _invalid('filePath and vaultPath required');
    return _extractToMemory(args);
  }

  Future<Map<String, Object?>> extractLocalEntry(Map<Object?, Object?> args) => _extractToMemory(args);

  Future<Map<String, Object?>> _extractToMemory(Map<Object?, Object?> args) async {
    final index = (args['targetIndex'] as num?)?.toInt();
    if (index == null || index < 0) throw _invalid('targetIndex required');
    final (vol, path) = _source(args);
    final r = await call('archiveExtractEntry', [vol, path, index, _nonEmpty(args['passphrase']), -1, null])
        as List<Object?>;
    final rec = _record([r[0], r[1]]);
    final data = r[2] as Uint8List?;
    return {
      'status': rec.status,
      'errorMessage': rec.message,
      // A zero-byte entry is a successful empty list, never an absent one.
      if (rec.status == 0) 'data': data ?? Uint8List(0),
    };
  }

  // ── browse staging ────────────────────────────────────────────────────────

  Future<Directory> _stagingDirectory() async {
    final existing = _stagingDir;
    if (existing != null && existing.existsSync()) return existing;
    if (!_purgedStale) {
      _purgedStale = true;
      await _purgeStale();
    }
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    final base = (runtime != null && runtime.isNotEmpty && Directory(runtime).existsSync())
        ? Directory(runtime)
        : Directory.systemTemp;
    return _stagingDir = await base.createTemp(_stagingPrefix); // mkdtemp: created 0700 on POSIX
  }

  Future<void> _purgeStale() async {
    final bases = <Directory>{Directory.systemTemp};
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtime != null && runtime.isNotEmpty) bases.add(Directory(runtime));
    for (final base in bases) {
      try {
        await for (final e in base.list(followLinks: false)) {
          if (e is Directory && p.basename(e.path).startsWith(_stagingPrefix)) {
            await SecureTempFile.wipeAndDeleteDir(e);
          }
        }
      } on FileSystemException {
        // base not listable
      }
    }
  }

  /// The staged file's name: the entry's own file name, with anything a file system dislikes replaced.
  static String _safeName(String entryName) {
    var name = p.posix.basename(entryName.replaceAll('\\', '/'));
    name = name.replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_');
    if (name.isEmpty || name == '.' || name == '..') name = 'entry';
    return name.length > 120 ? name.substring(name.length - 120) : name;
  }

  Future<Map<String, Object?>> stageBrowseEntry(Map<Object?, Object?> args) async {
    final index = (args['targetIndex'] as num?)?.toInt();
    final entryName = _nonEmpty(args['entryName']);
    if (index == null || index < 0 || entryName == null) throw _invalid('targetIndex and entryName required');
    final (vol, path) = _source(args);

    final dir = await _stagingDirectory();
    final dest = p.join(dir.path, '$_browsePrefix${_nextStaged++}_${_safeName(entryName)}');
    final r = await call('archiveExtractEntry', [vol, path, index, _nonEmpty(args['passphrase']), -1, dest])
        as List<Object?>;
    final rec = _record([r[0], r[1]]);
    if (rec.status != 0) {
      await _deleteQuietly(dest); // the engine already removed a partial file; this is belt and braces
      return {'status': rec.status, 'errorMessage': rec.message};
    }
    (_stagedByVolume[vol] ??= {}).add(dest);
    return {'status': 0, 'errorMessage': '', 'path': dest};
  }

  Future<bool> discardBrowseFile(Object? path) async {
    final dir = _stagingDir;
    if (path is! String || path.isEmpty || dir == null) return false;
    // Only a staged file, directly inside the staging directory: this must not be a way to delete other files.
    if (!p.basename(path).startsWith(_browsePrefix)) return false;
    if (p.canonicalize(p.dirname(path)) != p.canonicalize(dir.path)) return false;
    for (final set in _stagedByVolume.values) {
      set.remove(path);
    }
    return _deleteQuietly(path);
  }

  Future<bool> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await SecureTempFile.wipeAndDelete(f);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Deletes what was staged from [vol]'s archives (called when it locks); `-1` is the host archives.
  Future<void> cleanupVolume(int vol) async {
    final files = _stagedByVolume.remove(vol);
    if (files == null) return;
    for (final f in files) {
      await _deleteQuietly(f);
    }
  }

  Future<void> cleanupAll() async {
    _stagedByVolume.clear();
    final dir = _stagingDir;
    _stagingDir = null;
    if (dir == null) return;
    await SecureTempFile.wipeAndDeleteDir(dir);
  }

  // ── extract everything ─────────────────────────────────────────────────────

  /// `archiveExtractVaultAll`. The archive is `filePath` (a host file) or `vaultPath` inside the container
  /// `filePath`; the destination is `destDirPath` inside the container `destUri` (default: the archive's own
  /// container), or a host folder when `destUri` is not an unlocked container.
  Future<Map<String, Object?>> extractAll(Map<Object?, Object?> args) async {
    final (srcVol, srcPath) = _source(args);
    final filePath = _nonEmpty(args['filePath']) ?? _nonEmpty(args['localUri'])!;
    final destUri = _nonEmpty(args['destUri']) ?? filePath;
    final destDirPath = (args['destDirPath'] as String?) ?? '';
    final subPath = _nonEmpty(args['subPath']);
    final passphrase = _nonEmpty(args['passphrase']);
    final opId = (args['opId'] as num?)?.toInt() ?? 0;

    final destVol = volOrNull(destUri);
    final destVolId = destVol ?? -1;
    final destDir = destVol != null
        ? destDirPath
        : (destDirPath.isEmpty ? _localPath(destUri) : p.join(_localPath(destUri), destDirPath));

    final batched = destVol != null && isFolderVault(destVol);
    if (opId > 0) registerOp(opId);
    try {
      if (batched) await call('fvBatch', [destVol, 0, true]);
      try {
        final raw = await withActivity(
          () => call('archiveExtractAll', [srcVol, srcPath, passphrase, subPath, destVolId, destDir, opId]),
        );
        final rec = _record(raw);
        return {'status': rec.status, 'extractedCount': rec.count, 'errorMessage': rec.message};
      } finally {
        if (batched) await call('fvBatch', [destVol, 0, false]);
      }
    } finally {
      if (opId > 0) unregisterOp(opId);
    }
  }

  // ── create ─────────────────────────────────────────────────────────────────

  /// Formats whose writer assembles the archive in a temporary file before emitting it (7z, ISO).
  static const Set<int> _spooledFormats = {1, 8};

  /// `archiveCreate`. Sources are vault paths when `srcUri` is an unlocked container, otherwise host paths (a
  /// relative one is taken against `srcUri` as a folder). The archive goes into the vault at `destVaultPath`
  /// when `destUri` is an unlocked container, otherwise to the host file `destFilePath` (or `destUri` /
  /// `destVaultPath`). Returns whether the archive was written.
  Future<bool> createArchive(Map<Object?, Object?> args) async {
    final rawPaths = args['srcPaths'];
    if (rawPaths is! List || rawPaths.isEmpty) throw _invalid('srcPaths and matching entryNames required');
    final srcPaths = rawPaths.cast<String>();
    final rawNames = args['entryNames'];
    final entryNames = rawNames is List
        ? rawNames.cast<String>()
        : [for (final s in srcPaths) s.split(RegExp(r'[\\/]')).last];
    if (entryNames.length != srcPaths.length) throw _invalid('srcPaths and matching entryNames required');
    final rawTimes = args['modifiedSecs'];
    if (rawTimes is List && rawTimes.length != srcPaths.length) {
      throw _invalid('modifiedSecs must match srcPaths when provided');
    }
    final modified = rawTimes is List ? [for (final t in rawTimes) (t as num).toInt()] : List<int>.filled(srcPaths.length, 0);

    final srcUri = _nonEmpty(args['srcUri']);
    final srcVol = srcUri == null ? null : volOrNull(srcUri);
    final List<String> sources = srcVol != null
        ? srcPaths
        : [
            for (final sp in srcPaths)
              (srcUri != null && !p.isAbsolute(sp)) ? p.join(_localPath(srcUri), sp) : _localPath(sp),
          ];

    final destUri = _nonEmpty(args['destUri']);
    final destVaultPath = _nonEmpty(args['destVaultPath']);
    final destFilePath = _nonEmpty(args['destFilePath']);
    final destVol = destUri == null ? null : volOrNull(destUri);
    final String destPath;
    if (destVol != null && destVaultPath != null) {
      destPath = destVaultPath;
    } else if (destFilePath != null) {
      destPath = _localPath(destFilePath);
    } else if (destUri != null && destVaultPath != null) {
      destPath = p.join(_localPath(destUri), destVaultPath);
    } else if (destUri != null && destVol == null) {
      destPath = _localPath(destUri);
    } else {
      throw _invalid('A destination is required');
    }
    final intoVault = destVol != null && destVaultPath != null;

    final format = (args['format'] as num?)?.toInt() ?? 0;
    final opId = (args['opId'] as num?)?.toInt() ?? 0;
    Directory? spool;
    if (opId > 0) registerOp(opId);
    try {
      if (_spooledFormats.contains(format)) spool = await Directory.systemTemp.createTemp('${_stagingPrefix}spool-');
      final raw = await withActivity(
        () => call('archiveCreate', [
          srcVol ?? -1,
          sources,
          entryNames,
          modified,
          intoVault ? destVol : -1,
          destPath,
          format,
          _nonEmpty(args['passphrase']),
          args['encryptFilenames'] == true,
          (args['compressionLevel'] as num?)?.toInt() ?? -1,
          (args['compressionMethod'] as num?)?.toInt() ?? 0,
          (args['splitSizeBytes'] as num?)?.toInt() ?? 0,
          spool?.path,
          opId,
        ]),
      );
      final rec = _record(raw);
      if (kDebugMode && rec.status != 0) debugPrint('[desktop-archive] create failed (${rec.status}): ${rec.message}');
      return rec.status == 0;
    } finally {
      if (opId > 0) unregisterOp(opId);
      if (spool != null) {
        await SecureTempFile.wipeAndDeleteDir(spool);
      }
    }
  }

  // ── pickers ────────────────────────────────────────────────────────────────

  static const XTypeGroup _archiveTypes = XTypeGroup(
    label: 'Archives',
    extensions: [
      'zip', '7z', 'rar', 'tar', 'gz', 'tgz', 'bz2', 'tbz', 'tbz2', 'xz', 'txz', 'zst', 'tzst', 'lzma', 'iso', 'cpio',
      '001', 'z01',
    ],
  );

  /// `pickArchiveFile`: `{path, displayName}`, null when cancelled. A desktop path is always a real path.
  Future<Map<String, Object?>?> pickArchiveFile() async {
    final file = await openFile(acceptedTypeGroups: const [_archiveTypes]);
    if (file == null) return null;
    return {'path': file.path, 'displayName': p.basename(file.path)};
  }

  /// `pickExtractFolder`: the generic "choose a folder" used by the extract, export and tool screens.
  /// `{path, displayName, treeUri}`; there is no tree URI on desktop.
  Future<Map<String, Object?>?> pickExtractFolder() async {
    final dir = await getDirectoryPath();
    if (dir == null) return null;
    final name = p.basename(dir);
    return {'path': dir, 'displayName': name.isEmpty ? dir : name, 'treeUri': null};
  }
}
