// Composite containers for the desktop engine: one VeraCrypt volume spread over several ordinary files ("carriers")
// that each keep their own content and carry their share of the encrypted volume after it.
//
// The work is done by `ve_composite_profile`, `ve_composite_create` and `ve_composite_unlock` (ffi/ve_composite.cpp),
// over the same containers/carrier_profiler.cpp, composite_map.cpp and container_create_composite.cpp that Android's
// JNI layer calls. This class is what Android's CompositeContainerHandlers.kt does around them: check the method
// arguments, run the call in a worker isolate, and turn every outcome into the same result map or the same error code
// and message that `VaultCompositeApi` already handles.
//
// Differences from Android that follow from the platform, none of which the app can tell apart:
//   * A carrier is addressed by its filesystem path (what `uri` means on desktop; a `file:` URI is accepted too), so
//     there are no descriptors to detach and no read-only fallbacks to work out.
//   * The engine works out every carrier's payload offset and extent itself from the files, in the canonical order
//     (a digest of each file's first bytes), so `payloadOffsets` is not needed and `extentLengths` only says how much
//     capacity was asked for (its sum; the profile's total when the app passes the profile's budgets).
//   * An unlocked composite volume is listed from its root, like any other unlock here, so `files` is filled in.
//
// A composite session is registered under `composite:<first carrier as the app gave it>`, the key the app saves for
// the container, so lock, status and auto-lock find it exactly as they find any other session.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import 'desktop_archive.dart' show EngineCall;
import 've_native.dart' show veErrCancelled, veErrFailed, veErrInvalidArg, veOk;

/// Decodes the record `ve_composite_profile` writes (layout in ve_engine.h) into the map `VaultCompositeApi.profileCarriers`
/// reads. Null when [bytes] is not a well-formed record.
Map<String, Object?>? parseCompositeProfile(Uint8List bytes) {
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

    String str() {
      final len = u32();
      final s = utf8.decode(Uint8List.sublistView(bytes, pos, pos + len), allowMalformed: true);
      pos += len;
      return s;
    }

    final total = u64();
    final count = u32();
    final carriers = <Map<String, Object?>>[];
    for (var i = 0; i < count; i++) {
      final fileIndex = u32();
      final inputIndex = u32();
      final tier = u32();
      final fileSize = u64();
      final payloadOffset = u64();
      final allocatable = u64();
      final format = str();
      final path = str();
      carriers.add({
        'fileIndex': fileIndex,
        'inputIndex': inputIndex,
        'path': path,
        'detectedFormat': format,
        'fileSize': fileSize,
        'payloadOffset': payloadOffset,
        'allocatableBytes': allocatable,
        'tier': tier,
      });
    }
    if (pos != bytes.length) return null; // trailing bytes: not the record this code knows
    return {'totalAllocatableBytes': total, 'carriers': carriers};
  } on RangeError {
    return null;
  }
}

class DesktopComposite {
  DesktopComposite({
    required this.call,
    required this.slotFor,
    required this.releaseSlot,
    required this.register,
    required this.emit,
    required this.withActivity,
    void Function(String message)? log,
  }) : _log = log ?? ((message) => debugPrint('[desktop-composite] $message'));

  final EngineCall call;

  /// The slot a composite call works in: the live session of [key] when there is one, otherwise a free slot that no
  /// other composite call holds (throws the host's MAX_CONTAINERS error when there is none). The slot stays held
  /// until [releaseSlot].
  final Future<int> Function(String? key) slotFor;
  final void Function(int vol) releaseSlot;

  /// Records the unlocked volume as an active session under [key] (and exposes it, when the app asked for that).
  final void Function(int vol, String key, String displayName, String format, bool readOnly, Map<Object?, Object?> args)
      register;

  /// Pushes a native->Dart call to the app (`onUnlockStarted`).
  final void Function(String method, Object? arguments) emit;

  final Future<Object?> Function(Future<Object?> Function() body) withActivity;
  final void Function(String message) _log;

  static PlatformException _error(String code, String message, [Object? details]) =>
      PlatformException(code: code, message: message, details: details);

  /// A filesystem path from a `uri` argument (a `file:` URI is accepted too). Null when absent or empty.
  static String? _path(Object? uri) {
    if (uri is! String || uri.isEmpty) return null;
    if (uri.startsWith('file:')) {
      try {
        return Uri.parse(uri).toFilePath();
      } on UnsupportedError {
        return uri;
      }
    }
    return uri;
  }

  /// Every entry of a list of carrier URIs as a path, or null when the list is absent, empty or has a bad entry.
  static List<String>? _carrierPaths(Object? raw) {
    if (raw is! List || raw.isEmpty) return null;
    final paths = <String>[];
    for (final e in raw) {
      final path = _path(e);
      if (path == null) return null;
      paths.add(path);
    }
    return paths;
  }

  static List<String> _keyfilePaths(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (_path(e) case final path?) path,
    ];
  }

  static int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;

  static Uint8List _secret(Object? v) => Uint8List.fromList(utf8.encode(v is String ? v : ''));

  static void _wipe(Uint8List? bytes) {
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
  }

  // ── profile ───────────────────────────────────────────────────────────────

  /// `profileCarriers`: sizes the carriers (read-only) and answers the map `VaultCompositeApi` decodes.
  Future<Map<String, Object?>> profileCarriers(Map<Object?, Object?> args) async {
    final paths = _carrierPaths(args['carrierUris']);
    if (paths == null) throw _error('INVALID_ARGS', 'carrierUris required');
    final r = await call('compositeProfile', [paths, _int(args['safetyMarginPct'], 10)]) as List<Object?>;
    final record = r[0] == veOk ? r[1] as Uint8List? : null;
    final profile = record == null ? null : parseCompositeProfile(record);
    if (profile == null) throw _error('PROFILE_FAILED', 'Failed profiling carrier files');
    return profile;
  }

  // ── create ────────────────────────────────────────────────────────────────

  /// `createCompositeContainer`: writes the volume's shares into the carriers (growing each) and formats it. True when
  /// the volume exists (it is not left unlocked); false when the engine refused or failed, with the reason logged.
  Future<bool> create(Map<Object?, Object?> args) async {
    final entropy = args['userEntropy'] is Uint8List ? args['userEntropy'] as Uint8List : null;
    try {
      final paths = _carrierPaths(args['carrierUris']);
      final extents = args['extentLengths'];
      if (paths == null || args['payloadOffsets'] is! List || extents is! List) {
        throw _error('INVALID_ARGS', 'carrierUris, payloadOffsets, and extentLengths required');
      }
      final password = (args['password'] as String?) ?? '';
      final keyfiles = _keyfilePaths(args['keyfilePaths']);
      if (password.isEmpty && keyfiles.isEmpty) {
        throw _error('INVALID_ARGS', 'a password or at least one keyfile is required');
      }
      var requested = 0;
      for (final e in extents) {
        final length = _int(e, 0);
        if (length > 0) requested += length;
      }

      final vol = await slotFor(null);
      final secret = _secret(password);
      try {
        final r = await withActivity(() => call('compositeCreate', [
              paths,
              vol,
              requested,
              _int(args['safetyMarginPct'], 10),
              secret,
              _int(args['pim'], 0),
              (args['fileSystem'] as String?)?.toLowerCase() ?? 'fat',
              _int(args['cipherId'], 255),
              _int(args['hashId'], 255),
              keyfiles,
              args['quickFormat'] == true,
              entropy,
            ])) as List<Object?>;
        final rc = r[0] as int;
        if (rc == veOk) return true;
        if (rc == veErrFailed) {
          _log('create failed: ${r[1] ?? 'no reason given'}');
          return false;
        }
        if (rc == veErrInvalidArg) throw _error('INVALID_ARGS', 'The engine refused the composite create arguments');
        throw _error('C++_ERROR', 'Native composite create failed (code $rc)');
      } finally {
        _wipe(secret);
        releaseSlot(vol);
      }
    } finally {
      _wipe(entropy);
    }
  }

  // ── unlock ────────────────────────────────────────────────────────────────

  /// `unlockCompositeContainer`: finds every carrier's share, unlocks the volume and registers the session.
  Future<Map<String, Object?>> unlock(Map<Object?, Object?> args) async {
    final carrierUris = args['carrierUris'];
    final paths = _carrierPaths(carrierUris);
    if (paths == null) throw _error('INVALID_ARGS', 'carrierUris required');

    final key = 'composite:${(carrierUris as List).first}';
    final vol = await slotFor(key);
    final secret = _secret(args['password']);
    try {
      emit('onUnlockStarted', {'volId': vol});
      final readOnly = args['readOnly'] == true;
      final r = await withActivity(() => call('compositeUnlock', [
            paths,
            vol,
            secret,
            _int(args['pim'], 0),
            _int(args['cipherId'], 255),
            _int(args['hashId'], 255),
            _keyfilePaths(args['keyfilePaths']),
            readOnly,
          ])) as Map;
      final rc = r['rc'] as int;
      if (rc == veOk) {
        final format = r['format'] as String;
        register(vol, key, (args['displayName'] as String?) ?? 'Composite Vault', format, readOnly, args);
        return {
          'volId': vol,
          'files': (r['files'] as List<Object?>).cast<String>(),
          'matchedCipherId': r['cipherId'],
          'matchedHashId': r['hashId'],
          'containerFormat': format,
        };
      }
      if (rc == veErrCancelled) throw _error('CANCELLED', 'Unlock cancelled');
      if (rc == veErrInvalidArg) throw _error('INVALID_ARGS', 'The engine refused the composite unlock arguments');
      final code = r['error'] as String?;
      if (rc == veErrFailed || code != null) {
        // The engine's own reason (wrong password, a carrier missing, ...) reaches the app as Android sends it.
        final reason = code ?? 'INCORRECT_PASSWORD_OR_INVALID_CONTAINER';
        throw _error('AUTH_FAIL', reason, reason);
      }
      throw _error('C++_ERROR', 'Native composite unlock failed (code $rc)');
    } finally {
      _wipe(secret);
      releaseSlot(vol);
    }
  }
}
