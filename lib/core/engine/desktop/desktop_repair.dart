// Check & Repair and the header backup tool for the desktop engine.
//
// The work is done by `ve_repair_*`, `ve_header_*` and `ve_fv_check` / `ve_fv_repair` (ffi/ve_repair.cpp,
// ffi/ve_foldervault.cpp), over the same containers/container_repair.cpp and foldervault/fv_check.cpp that
// Android's JNI layer calls. This class is what Android's RepairHandlers.kt, HeaderBackupHandlers.kt and
// FolderVaultChecker.kt do around them: map the method arguments onto those calls, decode the results, and turn
// every outcome into the same map or the same error code the Dart `VaultRepairApi` already handles (so the
// repair wizard and the header backup tool behave identically on both platforms).
//
// A container file or folder vault is addressed by its filesystem path (what `uri` means on desktop).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'desktop_archive.dart' show EngineCall;
import 've_native.dart' show veErrNotUnlocked, veFormatWireName, veOk;

/// One issue found by a folder-vault check, as the wire map the Dart models read.
Map<String, Object?> _issue(int severity, String path, String message) =>
    {'severity': severity, 'path': path, 'message': message};

/// Decoded `ve_fv_check` / `ve_fv_repair` record (layout in ve_engine.h).
class FolderVaultRecord {
  const FolderVaultRecord({
    required this.outcome,
    required this.message,
    this.filesScanned = 0,
    this.deepScan = false,
    this.fixed = 0,
    this.recovered = 0,
    this.removed = 0,
    this.issues = const [],
  });

  /// 0 ok, 1 wrong password, 2 not a vault / refused.
  final int outcome;
  final String message;
  final int filesScanned;
  final bool deepScan;
  final int fixed;
  final int recovered;
  final int removed;
  final List<Map<String, Object?>> issues;

  /// Null when [bytes] is not a well-formed record.
  static FolderVaultRecord? tryParse(Uint8List bytes, {required bool repair}) {
    try {
      final d = ByteData.sublistView(bytes);
      var pos = 0;
      int u32() {
        final v = d.getUint32(pos, Endian.little);
        pos += 4;
        return v;
      }

      String str() {
        final len = u32();
        final s = utf8.decode(Uint8List.sublistView(bytes, pos, pos + len), allowMalformed: true);
        pos += len;
        return s;
      }

      List<Map<String, Object?>> issues() {
        final n = u32();
        return [
          for (var i = 0; i < n; i++) _issue(u32(), str(), str()),
        ];
      }

      final outcome = u32();
      final message = str();
      if (outcome != 0) return FolderVaultRecord(outcome: outcome, message: message);
      if (repair) {
        final fixed = u32();
        final recovered = u32();
        final removed = u32();
        return FolderVaultRecord(
          outcome: 0,
          message: message,
          fixed: fixed,
          recovered: recovered,
          removed: removed,
          issues: issues(),
        );
      }
      final scanned = u32();
      final deep = u32() != 0;
      return FolderVaultRecord(outcome: 0, message: message, filesScanned: scanned, deepScan: deep, issues: issues());
    } on RangeError {
      return null;
    }
  }

  /// No warning and no critical issue (info entries do not count).
  bool get healthy => issues.every((i) => i['severity'] == 0);
}

class DesktopRepair {
  DesktopRepair({
    required this.call,
    required this.folderVaultStateDir,
    required this.tempDir,
    required this.withActivity,
  });

  final EngineCall call;

  /// Where CryFS keeps its local state (the same folder the unlock path uses).
  final Future<String> Function() folderVaultStateDir;
  final String tempDir;

  /// Keeps the host's event pump (the live repair log) running while [body] is in flight.
  final Future<Object?> Function(Future<Object?> Function() body) withActivity;

  static PlatformException _error(String code, [String? message]) => PlatformException(code: code, message: message);

  static String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

  static String _path(Object? uri) {
    final s = _nonEmpty(uri);
    if (s == null) throw _error('INVALID_ARGS', 'uri required');
    if (s.startsWith('file:')) {
      try {
        return Uri.parse(s).toFilePath();
      } on UnsupportedError {
        return s;
      }
    }
    return s;
  }

  static int _opId(Map<Object?, Object?> args) => (args['opId'] as num?)?.toInt() ?? -1;

  Future<List<Object?>> _run(String op, List<Object?> args) async {
    final raw = await withActivity(() => call(op, args));
    return raw as List<Object?>;
  }

  // ── single-file containers ────────────────────────────────────────────────

  Future<Map<String, Object?>> diagnoseUnmounted(Map<Object?, Object?> args) async {
    final r = await _run('repairDiagnoseFile', [_path(args['uri']), _opId(args)]);
    if (r[0] != veOk) throw _error('IO_ERROR');
    final format = r[2] as int;
    return {'diagnosisCode': r[1] as int, 'format': format >= 0 ? veFormatWireName(format) : null};
  }

  Future<Map<String, Object?>> diagnoseMounted(Map<Object?, Object?> args) async {
    final vol = (args['volId'] as num?)?.toInt();
    if (vol == null) throw _error('INVALID_ARGS', 'volId required');
    final r = await _run('repairDiagnoseMounted', [vol, _opId(args)]);
    if (r[0] != veOk) throw _error('IO_ERROR');
    return {'diagnosisCode': r[1] as int, 'format': null};
  }

  Future<bool> runMountedCheck(Map<Object?, Object?> args) async {
    final vol = (args['volId'] as num?)?.toInt();
    if (vol == null) throw _error('INVALID_ARGS', 'volId required');
    final r = await _run('repairCheckMounted', [vol, _opId(args)]);
    if (r[0] != veOk) throw _error('IO_ERROR');
    return r[1] as bool;
  }

  /// `restoreBackupHeaderUnmounted`: probes the format, then restores from the backup the format keeps in the file
  /// itself (LUKS2: the secondary header copy; VeraCrypt/TrueCrypt: the backup header, which needs the password).
  Future<bool> restoreBackupHeaderUnmounted(Map<Object?, Object?> args) async {
    final path = _path(args['uri']);
    final opId = _opId(args);
    final probe = await _run('repairDiagnoseFile', [path, opId]);
    final format = probe[0] == veOk ? probe[2] as int : -1;
    switch (format) {
      case 2: // LUKS2: checksum-verified, no password needed
        final rc = await withActivity(() => call('repairRestoreLuks2', [path, opId])) as int;
        if (rc == veOk) return true;
        throw _error('NOTHING_TO_REPAIR');
      case 0: // VeraCrypt / TrueCrypt: decrypt-and-verify the backup first
        final password = _nonEmpty(args['password']);
        if (password == null) throw _error('PASSWORD_REQUIRED');
        final bytes = Uint8List.fromList(utf8.encode(password));
        try {
          final r = await _run('repairRestoreVeracrypt', [
            path,
            bytes,
            (args['pim'] as num?)?.toInt() ?? 0,
            (args['cipherId'] as num?)?.toInt() ?? 255,
            (args['hashId'] as num?)?.toInt() ?? 255,
            opId,
          ]);
          if (r[0] != veOk) throw _error('IO_ERROR');
          switch (r[1] as int) {
            case 0:
            case 2: // restored, or already healthy: nothing left to fix
              return true;
            case 1:
              throw _error('PASSWORD_INCORRECT');
            default:
              throw _error('IO_ERROR');
          }
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      default:
        throw _error('UNSUPPORTED_FORMAT');
    }
  }

  // ── header backup ──────────────────────────────────────────────────────────

  Future<Map<String, Object?>> exportContainerHeader(Map<Object?, Object?> args) async {
    final r = await _run('headerExport', [_path(args['uri']), _opId(args)]);
    final record = r[1] as Uint8List?;
    if (r[0] != veOk || record == null || record.length < 12) {
      throw _error('IO_ERROR', 'Could not read the container file');
    }
    final d = ByteData.sublistView(record);
    final result = d.getUint32(0, Endian.little);
    final format = d.getUint32(4, Endian.little);
    final length = d.getUint32(8, Endian.little);
    switch (result) {
      case 0:
        if (12 + length > record.length) throw _error('IO_ERROR', 'Could not read the container file');
        return {
          'format': veFormatWireName(format),
          'bytes': Uint8List.fromList(Uint8List.sublistView(record, 12, 12 + length)),
        };
      case 1:
        throw _error('UNRECOGNIZED_FILE', "This doesn't look like a container this app recognizes.");
      case 2:
        throw _error('UNSUPPORTED_FORMAT', "This container format doesn't support header backup.");
      case 3:
        throw _error(
          'HEADER_UNREADABLE',
          "Could not read this container's header fields -- try Check & Repair first.",
        );
      default:
        throw _error('IO_ERROR', 'Could not read the container file (code $result)');
    }
  }

  static int? _containerFormatOrdinal(String wire) => switch (wire) {
        'veracrypt' => 0,
        'luks1' => 1,
        'luks2' => 2,
        _ => null,
      };

  Future<bool> restoreContainerHeaderRegion(Map<Object?, Object?> args) async {
    final format = _nonEmpty(args['format']);
    final bytes = args['bytes'];
    if (_nonEmpty(args['uri']) == null || format == null || bytes is! Uint8List || bytes.isEmpty) {
      throw _error('INVALID_ARGS', 'uri, format, and bytes are required');
    }
    final ordinal = _containerFormatOrdinal(format);
    if (ordinal == null) throw _error('UNSUPPORTED_FORMAT', "This container format doesn't support header restore.");
    final password = _nonEmpty(args['password']);
    final keyfiles = [
      for (final k in (args['keyfilePaths'] as List?) ?? const []) _path(k),
    ];
    if (ordinal == 0 && password == null && keyfiles.isEmpty) {
      throw _error('PASSWORD_REQUIRED', 'A password or keyfile is needed to verify the backup header');
    }
    final secret = password == null ? null : Uint8List.fromList(utf8.encode(password));
    try {
      final r = await _run('headerRestore', [
        _path(args['uri']),
        ordinal,
        bytes,
        secret,
        (args['pim'] as num?)?.toInt() ?? 0,
        (args['cipherId'] as num?)?.toInt() ?? 255,
        (args['hashId'] as num?)?.toInt() ?? 255,
        _opId(args),
        keyfiles,
      ]);
      if (r[0] != veOk && r[1] != 4) throw _error('IO_ERROR');
      final outcome = r[1] as int;
      switch (outcome) {
        case 0:
          return true;
        case 1:
          throw _error('PASSWORD_INCORRECT', 'Incorrect password');
        case 2:
          throw _error('BACKUP_INVALID', "This backup doesn't look genuine for this container.");
        case 3:
          throw _error('SIZE_MISMATCH', 'The selected container is smaller than the backup header -- wrong file?');
        default:
          throw _error('IO_ERROR', 'Could not restore the header (code $outcome)');
      }
    } finally {
      secret?.fillRange(0, secret.length, 0);
    }
  }

  // ── folder vaults ──────────────────────────────────────────────────────────

  /// The wire format a folder-vault name denotes (`directory_vault` is the legacy name of Cryptomator).
  static int? _folderFormat(Object? wire) => switch (wire) {
        'gocryptfs' => 0,
        'cryptomator' || 'directory_vault' => 1,
        'cryfs' => 2,
        _ => null,
      };

  static const List<String> _folderFormatNames = ['gocryptfs', 'cryptomator', 'cryfs'];

  Future<Map<String, Object?>> checkFolderVault(Map<Object?, Object?> args) => _checkOrRepair(false, args);

  Future<Map<String, Object?>> repairFolderVault(Map<Object?, Object?> args) => _checkOrRepair(true, args);

  Future<Map<String, Object?>> _checkOrRepair(bool repair, Map<Object?, Object?> args) async {
    final root = _nonEmpty(args['uri']);
    final wire = _nonEmpty(args['format']);
    if (root == null || wire == null) throw _error('INVALID_ARGS', 'uri and format required');
    final format = _folderFormat(wire);
    if (format == null) throw _error('INVALID_VAULT');

    final password = _nonEmpty(args['password']);
    final secret = password == null ? null : Uint8List.fromList(utf8.encode(password));
    try {
      final r = await _run('fvCheck', [
        repair,
        format,
        _path(root),
        secret,
        (args['volId'] as num?)?.toInt() ?? -1,
        await folderVaultStateDir(),
        tempDir,
        _opId(args),
      ]);
      final bytes = r[1] as Uint8List?;
      if (r[0] == veErrNotUnlocked) throw _error('INVALID_VAULT');
      if (r[0] != veOk || bytes == null) throw _error('IO_ERROR');
      final rec = FolderVaultRecord.tryParse(bytes, repair: repair);
      if (rec == null) throw _error('IO_ERROR');
      switch (rec.outcome) {
        case 0:
          return repair
              ? {
                  'format': _folderFormatNames[format],
                  'fixedCount': rec.fixed,
                  'recoveredCount': rec.recovered,
                  'removedCount': rec.removed,
                  'remainingIssues': rec.issues,
                }
              : {
                  'format': _folderFormatNames[format],
                  'healthy': rec.healthy,
                  'filesScanned': rec.filesScanned,
                  'deepScanPerformed': rec.deepScan,
                  'issues': rec.issues,
                };
        case 1:
          throw _error('PASSWORD_INCORRECT');
        default:
          throw _error('INVALID_VAULT');
      }
    } finally {
      secret?.fillRange(0, secret.length, 0);
    }
  }

  /// `pickFolderVaultForRepair`: a folder chooser that also reports whether, and as which format, the folder is a
  /// vault. Null when the chooser is cancelled.
  Future<Map<String, Object?>?> pickFolderVaultForRepair() async {
    final dir = await getDirectoryPath();
    if (dir == null) return null;
    final detected = await call('fvProbe', [dir]) as int;
    final name = p.basename(dir);
    return {
      'uri': dir,
      'displayName': name.isEmpty ? dir : name,
      'looksLikeVault': detected >= 0 && detected < _folderFormatNames.length,
      'format': detected >= 0 && detected < _folderFormatNames.length ? _folderFormatNames[detected] : null,
    };
  }

  Future<String> _configFileName(Object? wire) async {
    final format = _folderFormat(wire);
    final name = format == null ? null : await call('fvConfigFileName', [format]) as String?;
    if (format == null || name == null || name.isEmpty) {
      throw _error('UNSUPPORTED_FORMAT', 'Unknown folder vault format: $wire');
    }
    return name;
  }

  /// `resolveFolderVaultConfigFile`: where the vault's key-material file is (`uri` is null when it is missing; the
  /// file name is always returned so a restore knows what to recreate).
  Future<Map<String, Object?>> resolveFolderVaultConfigFile(Map<Object?, Object?> args) async {
    final root = _path(args['uri']);
    if (_nonEmpty(args['format']) == null) throw _error('INVALID_ARGS', 'uri and format are required');
    final fileName = await _configFileName(args['format']);
    final file = File(p.join(root, fileName));
    final exists = file.existsSync();
    return {'fileName': fileName, 'uri': exists ? file.path : null, 'exists': exists};
  }

  /// `restoreFolderVaultConfig`: validates [bytes] as a genuine config of the format (structure only; it cannot
  /// prove the password matches), then replaces the vault's own copy atomically (write beside it, rename over it).
  Future<void> restoreFolderVaultConfig(Map<Object?, Object?> args) async {
    final root = _path(args['uri']);
    final bytes = args['bytes'];
    if (_nonEmpty(args['format']) == null || bytes is! Uint8List || bytes.isEmpty) {
      throw _error('INVALID_ARGS', 'uri, format, and bytes are required');
    }
    final fileName = await _configFileName(args['format']);
    final reason = await call('fvValidateConfig', [_folderFormat(args['format']), bytes]) as String?;
    if (reason != null) throw _error('BACKUP_INVALID', reason);

    final target = File(p.join(root, fileName));
    final staging = File(p.join(root, '.$fileName.restore'));
    try {
      await staging.writeAsBytes(bytes, flush: true);
      await staging.rename(target.path); // replaces an existing file
    } on FileSystemException catch (e) {
      try {
        if (staging.existsSync()) staging.deleteSync();
      } on FileSystemException {
        // best effort
      }
      throw _error('IO_ERROR', e.message);
    }
  }
}
