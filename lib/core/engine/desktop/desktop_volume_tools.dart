// Expand volume, grow the file system, and add a hidden volume to an existing volume, for the desktop engine.
//
// The work is done by `ve_expand_*`, `ve_grow_*_fs`, `ve_hidden_analyze` and `ve_hidden_create_in_existing`
// (ffi/ve_tools.cpp), over the same containers/container_create.cpp and containers/container_expand_bitlocker.cpp that
// Android's JNI layer calls. This class is what Android's VeraCryptToolsHandlers.kt does around them: check the
// method arguments, run the call in a worker isolate, and turn every outcome into the same success map or the same
// error code and message that `VeraCryptToolsApi` already handles, so the Volume tools screen behaves identically
// on both platforms.
//
// A container file is addressed by its filesystem path (what `uri` means on desktop). A container file that is
// currently unlocked in this process is refused by the engine itself (CONTAINER_IN_USE).
import 'dart:convert';

import 'package:flutter/services.dart';

import 'desktop_archive.dart' show EngineCall;
import 've_native.dart' show veErrFailed, veOk;

/// Which container format an expand / grow call targets. The index is the `kind` the worker op takes.
enum VolumeToolKind { veracrypt, luks, bitlocker }

class DesktopVolumeTools {
  DesktopVolumeTools({required this.call});

  final EngineCall call;

  static PlatformException _error(String code, String message) => PlatformException(code: code, message: message);

  static String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

  /// A filesystem path from a `uri` argument (a `file:` URI is accepted too). Null when absent or empty.
  static String? _path(Object? uri) {
    final s = _nonEmpty(uri);
    if (s == null) return null;
    if (s.startsWith('file:')) {
      try {
        return Uri.parse(s).toFilePath();
      } on UnsupportedError {
        return s;
      }
    }
    return s;
  }

  static List<String> _paths(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (_path(e) case final path?) path,
    ];
  }

  static int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;

  static bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

  /// Passwords reach the engine as the raw UTF-8 bytes Android's password marshalling produces.
  static Uint8List _secret(Object? v) => Uint8List.fromList(utf8.encode(v is String ? v : ''));

  /// Overwrites this side's copy of a secret once the call is done (the worker wipes its own copy).
  static void _wipe(Uint8List? bytes) {
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
  }

  static List<int> _ints(Object? v) => (v as List).cast<int>();

  // ── expand ────────────────────────────────────────────────────────────────

  /// `expandVeraCryptContainer`, `expandLuksContainer` and `expandBitLockerContainer`.
  Future<Map<String, Object?>> expand(VolumeToolKind kind, Map<Object?, Object?> args) async {
    final path = _path(args['uri']);
    final password = _nonEmpty(args['password']) ?? '';
    final keyfiles = kind == VolumeToolKind.bitlocker ? const <String>[] : _paths(args['keyfilePaths']);
    final newSize = _int(args['newSizeBytes'], 0);
    final noCredential = kind == VolumeToolKind.bitlocker ? password.isEmpty : password.isEmpty && keyfiles.isEmpty;
    if (path == null || newSize <= 0 || noCredential) {
      throw _error(
        'INVALID_ARGS',
        kind == VolumeToolKind.bitlocker
            ? 'uri, newSizeBytes and a password or recovery key are required'
            : 'uri, newSizeBytes and a password or keyfile are required',
      );
    }
    final secret = _secret(password);
    try {
      final r = await call('toolExpand', [
        kind.index,
        path,
        secret,
        _int(args['pim'], 0),
        _int(args['cipherId'], 255),
        _int(args['hashId'], 255),
        keyfiles,
        newSize,
        _bool(args['initFreeSpace'], kind != VolumeToolKind.bitlocker),
        _bool(args['growFileSystem'], true),
      ]) as List<Object?>;
      return _growResult(kind, r);
    } finally {
      _wipe(secret);
    }
  }

  // ── grow the file system only ─────────────────────────────────────────────

  /// `growVeraCryptFileSystem`, `growLuksFileSystem` and `growBitLockerFileSystem`.
  Future<Map<String, Object?>> growFileSystem(VolumeToolKind kind, Map<Object?, Object?> args) async {
    final path = _path(args['uri']);
    final password = _nonEmpty(args['password']) ?? '';
    final keyfiles = kind == VolumeToolKind.bitlocker ? const <String>[] : _paths(args['keyfilePaths']);
    final noCredential = kind == VolumeToolKind.bitlocker ? password.isEmpty : password.isEmpty && keyfiles.isEmpty;
    if (path == null || noCredential) {
      throw _error(
        'INVALID_ARGS',
        kind == VolumeToolKind.bitlocker
            ? 'uri and a password or recovery key are required'
            : 'uri and a password or keyfile are required',
      );
    }
    final secret = _secret(password);
    try {
      final r = await call('toolGrowFs', [
        kind.index,
        path,
        secret,
        _int(args['pim'], 0),
        _int(args['cipherId'], 255),
        _int(args['hashId'], 255),
        keyfiles,
      ]) as List<Object?>;
      return _growResult(kind, r);
    } finally {
      _wipe(secret);
    }
  }

  /// The engine's `[rc, [outcome, fsStep, fsKind]]` answer as the success map, or the error Android raises.
  static Map<String, Object?> _growResult(VolumeToolKind kind, List<Object?> r) {
    final rc = r[0] as int;
    final out = _ints(r[1]);
    // The container is the one thing the engine could not open when the worker answers veErrFailed; every other
    // non-OK answer leaves the outcome at its "I/O error" default.
    final outcome = rc == veOk || out[0] != 0 ? out[0] : 4;
    if (outcome == 0) {
      return {'fsStatus': fsStatusName(out[1]), 'fsName': fsKindName(out[2])};
    }
    if (rc == veErrFailed && outcome == 4) throw _error('IO_ERROR', 'Could not open the container file.');
    throw expandFailure(kind, outcome);
  }

  /// The error for a non-zero expand / grow outcome (ve_engine.h, "container tools"), with the messages
  /// VeraCryptToolsHandlers.kt uses.
  static PlatformException expandFailure(VolumeToolKind kind, int outcome) {
    final bitlocker = kind == VolumeToolKind.bitlocker;
    switch (outcome) {
      case 1:
        return _error('PASSWORD_INCORRECT', 'Incorrect password');
      case 2:
        return _error(
          'NOT_EXPANDABLE',
          switch (kind) {
            VolumeToolKind.bitlocker =>
              "This BitLocker volume can't be expanded. It must be a fully encrypted Windows 7 or later volume in the classic layout (not BitLocker To Go, and not the encrypt-on-write / used-space-only layout) that fits inside its file.",
            VolumeToolKind.luks => 'This LUKS container uses an unsupported segment layout or inconsistent metadata.',
            VolumeToolKind.veracrypt => 'Only a standard volume that fills its container can be expanded.',
          },
        );
      case 3:
        return _error('NOT_LARGER', 'The new size must be larger than the current size.');
      case 5:
        return _error('KEYFILE_ERROR', 'A keyfile could not be read.');
      case 6:
        return _error('NOT_LUKS', 'The selected file is not a LUKS container.');
      case 7:
        return _error(
          'INVALID_HEADER',
          bitlocker
              ? 'The BitLocker metadata is damaged, failed verification or uses an unsupported layout, so nothing was changed.'
              : 'The LUKS header is damaged or unsupported.',
        );
      case 8:
        return _error('CONTAINER_IN_USE', 'Close the unlocked volume before expanding or growing its file system.');
      case 9:
        return _error(
          'NOT_BITLOCKER',
          'No BitLocker volume was found. The file must be a raw BitLocker volume, or a fixed/dynamic VHD or VHDX with a BitLocker partition (or a BitLocker volume that fills the whole virtual disk).',
        );
      case 10:
        return _error(
          'DISK_UNSUPPORTED',
          "This virtual disk can't be grown in place: differencing disks, VHDX files with a pending log, 4096-byte logical sectors, or a disk whose allocation table has no room for the added space are not supported. Nothing was changed.",
        );
      case 11:
        return _error(
          'PARTITION_UNSUPPORTED',
          "The BitLocker partition can't be grown: it must be the last partition of an MBR or GPT disk (no extended partitions). Nothing was changed.",
        );
      default:
        return _error(
          'IO_ERROR',
          bitlocker
              ? 'Could not complete the volume operation (code $outcome). If the container was already expanded, use "Grow file system only" to finish.'
              : 'Could not complete the volume operation (code $outcome)',
        );
    }
  }

  /// Mirrors FsGrowStatus in cpp/filesystems/fs_grow.h (and `fsStatusName` in VeraCryptToolsHandlers.kt).
  static String fsStatusName(int status) => switch (status) {
        0 => 'grown',
        1 => 'already_fills',
        2 => 'unsupported',
        3 => 'needs_check',
        4 => 'busy',
        5 => 'failed',
        _ => 'not_run',
      };

  /// Mirrors `fsKindName` in VeraCryptToolsHandlers.kt.
  static String fsKindName(int kind) => switch (kind) {
        1 => 'FAT12',
        2 => 'FAT16',
        3 => 'FAT32',
        4 => 'exFAT',
        5 => 'NTFS',
        6 => 'ext2',
        7 => 'ext3',
        8 => 'ext4',
        _ => '',
      };

  // ── hidden volume in an existing standard volume ──────────────────────────

  /// The error for a non-zero hidden-volume outcome (`hiddenHostErrorFor` in VeraCryptToolsHandlers.kt).
  static PlatformException hiddenFailure(int outcome) => switch (outcome) {
        1 => _error('PASSWORD_INCORRECT', 'Incorrect password'),
        2 => _error('UNSUPPORTED_FS', "The outer volume's file system must be FAT, exFAT or NTFS to host a hidden volume."),
        3 => _error('NO_SPACE', 'There is not enough free space at the end of the outer volume for a hidden volume of that size.'),
        5 => _error('KEYFILE_ERROR', 'A keyfile could not be read.'),
        6 => _error(
            'INVALID_VOLUME',
            'Only a standard volume that fills its container can host a hidden volume, and the hidden password must differ from the outer one.',
          ),
        _ => _error('IO_ERROR', 'Operation failed (code $outcome)'),
      };

  /// `analyzeHiddenVolumeHost`: the largest hidden volume that fits at the end of the outer volume.
  Future<Map<String, Object?>> analyzeHiddenHost(Map<Object?, Object?> args) async {
    final path = _path(args['uri']);
    final password = _nonEmpty(args['password']) ?? '';
    final keyfiles = _paths(args['keyfilePaths']);
    if (path == null || (password.isEmpty && keyfiles.isEmpty)) {
      throw _error('INVALID_ARGS', 'uri and a password or keyfile are required');
    }
    final secret = _secret(password);
    final List<Object?> r;
    try {
      r = await call('toolHiddenAnalyze', [
        path,
        secret,
        _int(args['pim'], 0),
        _int(args['cipherId'], 255),
        _int(args['hashId'], 255),
        keyfiles,
      ]) as List<Object?>;
    } finally {
      _wipe(secret);
    }
    final rc = r[0] as int;
    final out = _ints(r[1]);
    if (rc == veErrFailed) {
      // The worker could not open a file: a keyfile (5), else the container.
      if (out[0] == 5) throw hiddenFailure(5);
      throw _error('IO_ERROR', 'Could not open the container file.');
    }
    if (rc != veOk) throw _error('IO_ERROR', 'Analysis failed');
    if (out[0] != 0) throw hiddenFailure(out[0]);
    return {'fsKind': out[1], 'clusterSize': out[2], 'maxHiddenBytes': out[3]};
  }

  /// `createHiddenVolumeInExisting`: adds a hidden volume to an existing standard volume ("direct mode").
  Future<bool> createHiddenInExisting(Map<Object?, Object?> args) async {
    final path = _path(args['uri']);
    final outerPassword = _nonEmpty(args['outerPassword']) ?? '';
    final hiddenPassword = _nonEmpty(args['hiddenPassword']) ?? '';
    final outerKeyfiles = _paths(args['outerKeyfilePaths']);
    final hiddenKeyfiles = _paths(args['hiddenKeyfilePaths']);
    final hiddenSize = _int(args['hiddenSizeBytes'], 0);
    if (path == null ||
        hiddenSize <= 0 ||
        (outerPassword.isEmpty && outerKeyfiles.isEmpty) ||
        (hiddenPassword.isEmpty && hiddenKeyfiles.isEmpty)) {
      throw _error('INVALID_ARGS', 'uri, hiddenSizeBytes and passwords/keyfiles are required');
    }
    final entropyArg = args['userEntropy'];
    final outerSecret = _secret(outerPassword);
    final hiddenSecret = _secret(hiddenPassword);
    final entropy = entropyArg is Uint8List ? Uint8List.fromList(entropyArg) : null;
    final List<Object?> r;
    try {
      r = await call('toolHiddenCreate', [
        path,
        outerSecret,
        _int(args['outerPim'], 0),
        _int(args['outerCipherId'], 255),
        _int(args['outerHashId'], 255),
        outerKeyfiles,
        hiddenSecret,
        _int(args['hiddenPim'], 0),
        _nonEmpty(args['hiddenFileSystem']) ?? 'exFAT',
        hiddenSize,
        _int(args['hiddenCipherId'], 255),
        _int(args['hiddenHashId'], 255),
        hiddenKeyfiles,
        _bool(args['quickFormat'], false),
        entropy,
      ]) as List<Object?>;
    } finally {
      _wipe(outerSecret);
      _wipe(hiddenSecret);
      _wipe(entropy);
    }
    final rc = r[0] as int;
    final outcome = r[1] as int;
    if (rc == veOk && outcome == 0) return true;
    if (rc == veErrFailed && outcome == 4) throw _error('IO_ERROR', 'Could not open the container file.');
    throw hiddenFailure(rc == veOk || outcome != 0 ? outcome : 4);
  }
}
