import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/listener_registry.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';

part 'vault_explorer_api_crypto.dart';
part 'vault_explorer_api_container_lifecycle.dart';
part 'vault_explorer_api_file_io.dart';

/// A single keyfile picked via [VaultExplorerApi.pickKeyfiles]: [uri] is
/// what gets sent back to native (and round-tripped through
/// [VaultExplorerApi.unlockContainer]/[unlockUsbContainer]/[deriveDerivedKey]/
/// [createContainer] as a `keyfilePaths` entry); [displayName] is purely for
/// showing a chip or list entry in the unlock/create UI.
typedef KeyfileRef = ({String uri, String displayName});

/// One "onUnlockProgress" push from native during cipher/hash auto-detect.
/// [attempted]/[total] count hash-algorithm rounds tried so far (auto-detect
/// runs up to 5 in parallel, each then tries up to 8 ciphers against it very
/// quickly) — suitable for a "trying combination 2 of 5" style indicator.
/// [hashId]/[cipherId] are whichever combination was just attempted (-1 for
/// cipherId if that hash's PBKDF2 itself hadn't finished yet); see
/// [hashAlgorithmName]/[cipherAlgorithmName] to render them.
typedef UnlockProgress = ({
  int volId,
  int attempted,
  int total,
  int hashId,
  int cipherId,
  String containerFormat,
  int slot,
});

String hashAlgorithmName(int hashId) => HashAlgo.nameFor(hashId);
String cipherAlgorithmName(int cipherId) => CipherAlgo.nameFor(cipherId);

/// One "onImportProgress" push from native while importing files/folders
/// from device storage (see [VaultExplorerApi.importFiles]/[importFolder]).
/// [opId] is the [FileOperation.id] passed into that call — listeners
/// should filter on it themselves if more than one import could be in
/// flight. [done]/[total] count files written so far vs. the total native
/// discovered during its pre-count pass; [currentName] is the leaf name of
/// the file most recently written.
typedef ImportProgress = ({
  int opId,
  int done,
  int total,
  String currentName,
  int transferredBytes,
  int totalBytes,
});


/// Logs an exception this method is about to swallow (return a default
/// value instead of rethrowing) so a real native/channel failure is at
/// least visible in the debug console instead of silently degrading to
/// "false"/"null"/"0" — which looks identical to a legitimate empty
/// result at every call site.
///
/// [method] is the channel method name (or a short description) so the
/// log line identifies *what* failed without needing a stack trace.
/// [expected] marks a catch that's already documented as intentionally
/// best-effort (e.g. [VaultExplorerApi.cancelUnlock] racing a call that's
/// about to resolve on its own) — those still get logged, but tagged
/// separately so they don't read as equally alarming as a genuine
/// unexpected failure such as a corrupted container header or a revoked
/// SAF permission.
void _logSwallowed(String method, Object error, {bool expected = false}) {
  debugPrint(
    '${expected ? '[VaultExplorerApi:expected]' : '[VaultExplorerApi]'} '
    '$method failed: $error',
  );
}

/// The single platform channel used by every VaultExplorerApi operation,
/// including those implemented across the _CryptoOps / _ContainerLifecycleOps
/// / _FileIoOps mixins in the sibling part files below. Declared at library
/// (not class) level -- rather than as a `static` member of
/// [VaultExplorerApi] -- because those mixins aren't subclasses of
/// VaultExplorerApi and so can't reach a class-static member unqualified;
/// a top-level private is visible, unqualified, to every part file in this
/// library instead.
const _channel = MethodChannel('com.aeidolon.vaultexplorer/engine');

class VaultExplorerApi with _CryptoOps, _ContainerLifecycleOps, _FileIoOps {
  const VaultExplorerApi();


  static void Function(String ext, String pkg)? onAppSelectedCallback;


  static final ListenerRegistry<int> _usbContainerDetachedRegistry =
      ListenerRegistry<int>();

  static void addUsbContainerDetachedListener(
    void Function(int volId) listener,
  ) {
    _usbContainerDetachedRegistry.add(listener);
  }

  static void removeUsbContainerDetachedListener(
    void Function(int volId) listener,
  ) {
    _usbContainerDetachedRegistry.remove(listener);
  }


  static final List<void Function()> _screenOffListeners = [];

  static void addScreenOffListener(void Function() listener) {
    _screenOffListeners.add(listener);
  }

  static void removeScreenOffListener(void Function() listener) {
    _screenOffListeners.remove(listener);
  }

  // ── Unlock progress / cancellation ──────────────────────────────────────
  //
  // "onUnlockStarted" fires once, synchronously from the native method call
  // handler, as soon as a volId has been allocated for this attempt — before
  // the (potentially several-second) auto-detect search actually begins.
  // "onUnlockProgress" then fires repeatedly during that search. Listeners
  // should filter on volId themselves if more than one unlock could be in
  // flight (in practice: at most one per UnlockSheet/UsbUnlockSheet instance).

  static final ListenerRegistry<int> _unlockStartedRegistry =
      ListenerRegistry<int>();
  static final ListenerRegistry<UnlockProgress> _unlockProgressRegistry =
      ListenerRegistry<UnlockProgress>();

  static void addUnlockStartedListener(void Function(int volId) listener) {
    _unlockStartedRegistry.add(listener);
  }

  static void removeUnlockStartedListener(void Function(int volId) listener) {
    _unlockStartedRegistry.remove(listener);
  }

  static void addUnlockProgressListener(
    void Function(UnlockProgress progress) listener,
  ) {
    _unlockProgressRegistry.add(listener);
  }

  static void removeUnlockProgressListener(
    void Function(UnlockProgress progress) listener,
  ) {
    _unlockProgressRegistry.remove(listener);
  }

  // ── Import progress ───────────────────────────────────────────────────
  //
  // "onImportProgress" fires repeatedly from native while importFile/
  // importFolder is running. Listeners should filter on opId themselves if
  // more than one import could be in flight (see FileOperationService, the
  // only current subscriber).

  static final ListenerRegistry<ImportProgress> _importProgressRegistry =
      ListenerRegistry<ImportProgress>();

  static void addImportProgressListener(
    void Function(ImportProgress progress) listener,
  ) {
    _importProgressRegistry.add(listener);
  }

  static void removeImportProgressListener(
    void Function(ImportProgress progress) listener,
  ) {
    _importProgressRegistry.remove(listener);
  }

  static void initMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAppSelected') {
        final ext = call.arguments['extension'] as String?;
        final pkg = call.arguments['package'] as String?;
        if (ext != null && pkg != null) {
          onAppSelectedCallback?.call(ext, pkg);
        }
      } else if (call.method == 'onUsbContainerDetached') {
        final volId = call.arguments['volId'] as int?;
        if (volId != null) {
          _usbContainerDetachedRegistry.notify(volId);
        }
      } else if (call.method == 'onScreenOff') {
        for (final listener in List.of(_screenOffListeners)) {
          listener();
        }
      } else if (call.method == 'onUnlockStarted') {
        final volId = call.arguments['volId'] as int?;
        if (volId != null) {
          _unlockStartedRegistry.notify(volId);
        }
      } else if (call.method == 'onUnlockProgress') {
        final args = call.arguments as Map<Object?, Object?>;
        final volId = args['volId'] as int?;
        final attempted = args['attempted'] as int?;
        final total = args['total'] as int?;
        if (volId != null && attempted != null && total != null) {
          final progress = (
            volId: volId,
            attempted: attempted,
            total: total,
            hashId: args['hashId'] as int? ?? 255,
            cipherId: args['cipherId'] as int? ?? 255,
            containerFormat: args['containerFormat'] as String? ?? 'veracrypt',
            slot: args['slot'] as int? ?? 0,
          );
          _unlockProgressRegistry.notify(progress);
        }
} else if (call.method == 'onImportProgress') {
        final args = call.arguments as Map<Object?, Object?>;
        final opId = args['opId'] as int?;
        final done = args['done'] as int?;
        final total = args['total'] as int?;
        if (opId != null && done != null && total != null) {
          final progress = (
            opId: opId,
            done: done,
            total: total,
            currentName: args['currentName'] as String? ?? '',
            transferredBytes: (args['transferredBytes'] as num?)?.toInt() ?? 0,
            totalBytes: (args['totalBytes'] as num?)?.toInt() ?? 0,
          );
          _importProgressRegistry.notify(progress);
        }
      }
    });
  }

  static final Set<int> _activeBatches = {};
  static final Set<int> _lockPending = {};

  void beginBatch(int volId) {
    _activeBatches.add(volId);
  }

  void endBatch(int volId) {
    _activeBatches.remove(volId);
  }

  bool hasActiveBatch(int volId) => _activeBatches.contains(volId);

  /// Attempts to acquire the lock guard for [volId].
  ///
  /// Returns `true` if:
  /// - No batch is active for [volId], AND
  /// - No lock is already pending for [volId].
  ///
  /// If this returns `true` the caller MUST call [releaseLockGuard] after
  /// the lock operation completes (success or failure).

  bool acquireLockGuard(int volId) {
    if (_activeBatches.contains(volId) || _lockPending.contains(volId)) {
      return false;
    }
    _lockPending.add(volId);
    return true;
  }

  void releaseLockGuard(int volId) {
    _lockPending.remove(volId);
  }
}

VaultExplorerApi vaultExplorerApi = const VaultExplorerApi();
