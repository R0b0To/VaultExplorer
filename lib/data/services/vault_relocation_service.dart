import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/app_storage_vault_uri.dart';

const _kLogTag = 'VaultRelocation';

/// Where a move currently is. Cancelling only has an effect while [copying].
enum RelocationPhase { copying, switching, finishing }

/// Why a move did not happen. The UI picks its message from this.
enum RelocationFailure {
  /// The vault is unlocked; it must be locked before its files can move.
  vaultUnlocked,

  /// A USB drive or composite vault: there is no single file or folder to copy.
  unsupportedSource,

  /// A piece of a split container, which cannot be moved on its own.
  splitContainer,

  /// A folder that does not hold a vault's configuration file.
  notAVaultFolder,

  /// The folder chosen as the destination already has files in it.
  destinationNotEmpty,
  alreadyInAppStorage,
  notInAppStorage,

  /// The vault's file or folder can no longer be read.
  sourceMissing,
  insufficientSpace,

  /// The copy did not match the original byte for byte, so it was thrown away.
  verifyFailed,
  cancelled,
  noPicker,

  /// The copy was good, but the app could not switch the vault over to it. The copy was removed.
  recordSwitchFailed,

  /// Another move is already running.
  busy,
  io,
}

class RelocationException implements Exception {
  const RelocationException(
    this.reason, {
    this.message,
    this.neededBytes,
    this.availableBytes,
  });

  final RelocationFailure reason;
  final String? message;

  /// Set for [RelocationFailure.insufficientSpace] when the platform reports it.
  final int? neededBytes;
  final int? availableBytes;

  @override
  String toString() => 'RelocationException($reason${message == null ? '' : ': $message'})';
}

/// A verified copy of a vault at [uri].
class RelocationCopy {
  const RelocationCopy({required this.uri, this.bytes = 0, this.files = 0});
  final String uri;
  final int bytes;
  final int files;
}

class RelocationFinalize {
  const RelocationFinalize({
    required this.sourceDeleted,
    this.automationReset = false,
    this.reason,
  });
  final bool sourceDeleted;

  /// The vault had an automation grant (Tasker etc.); it is not carried to the new location.
  final bool automationReset;
  final String? reason;
}

/// What switching the record did besides moving it.
class RecordMove {
  const RecordMove({this.biometricsDropped = false});

  /// Biometric unlock could not be carried over (its enrollment check failed), so the vault now asks for its password.
  final bool biometricsDropped;
}

/// The native side of a move (copy, verify, delete). Implemented over the platform channel;
/// faked in tests.
abstract interface class RelocationGateway {
  /// Copies the vault at [sourceUri] into app storage and verifies it. The original is untouched.
  Future<RelocationCopy> copyIn({
    required String sourceUri,
    required bool isFolderVault,
    required String displayName,
    required int opId,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  /// Asks where to put the vault, copies it there and verifies it. Null if the user dismissed the picker.
  Future<RelocationCopy?> copyOut({
    required String sourceUri,
    required bool isFolderVault,
    required String displayName,
    required int opId,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  });

  Future<RelocationFinalize> finalize({
    required String oldUri,
    required String newUri,
    required bool isFolderVault,
    required bool deleteSource,
  });

  /// Removes a copy whose switch-over failed.
  Future<void> discardCopy({required String uri, required bool isFolderVault});

  Future<void> cancel(int opId);
}

/// The app's registration of vaults (record, credentials, settings). Implemented over the container repository.
abstract interface class RelocationRecordStore {
  /// Re-registers the vault at [oldUri] as [newUri], with everything it had. All or nothing:
  /// if this throws, the vault is still registered at [oldUri] exactly as before.
  Future<RecordMove> moveRecord({required String oldUri, required String newUri});
}

/// What a finished call did.
class RelocationOutcome {
  const RelocationOutcome({
    required this.completed,
    this.newUri,
    this.bytes = 0,
    this.files = 0,
    this.deleteRequested = false,
    this.originalDeleted = false,
    this.biometricsDropped = false,
    this.automationReset = false,
  });

  /// The user dismissed the destination picker; nothing was changed.
  const RelocationOutcome.dismissed() : this(completed: false);

  final bool completed;
  final String? newUri;
  final int bytes;
  final int files;
  final bool deleteRequested;
  final bool originalDeleted;
  final bool biometricsDropped;
  final bool automationReset;

  /// The vault was moved, but the user asked for the original to be deleted and it could not be.
  bool get originalLeftBehind => completed && deleteRequested && !originalDeleted;
}

/// Moves a vault between where the user keeps it and app storage, one move at a time.
///
/// The order is what makes it safe, and it is the same in both directions:
///
///  1. **Copy and verify.** The native side copies the vault and reads the copy back, comparing
///     SHA-256 per file. The original is not touched. A failure here changes nothing.
///  2. **Switch.** The vault's registration (record, saved credentials, settings) moves to the
///     new location in one step. If that fails, the copy is removed and the original stays registered.
///  3. **Finish.** The original is deleted (if asked) and the old location's native state cleared.
///     By now the vault already works from its new location, so a failure here only leaves the
///     original behind; it never costs the user their vault.
///
/// At every point a crash leaves the original intact and registered, or the new copy fully
/// working, never neither.
class VaultRelocationService {
  VaultRelocationService({
    required RelocationGateway gateway,
    required RelocationRecordStore records,
    int firstOpId = kFirstRelocationOpId,
  }) : _gateway = gateway,
       _records = records,
       _nextOpId = firstOpId;

  /// Operation ids share the Split/Join progress channel; this range is reserved for relocation so a
  /// move can never receive another operation's progress (see also `kWaveformOpIdBase`, 0x40000000).
  static const int kFirstRelocationOpId = 0x50000000;

  final RelocationGateway _gateway;
  final RelocationRecordStore _records;
  int _nextOpId;
  int? _copyingOpId;
  bool _busy = false;

  bool get isBusy => _busy;

  Future<RelocationOutcome> moveToAppStorage({
    required String uri,
    required String displayName,
    required bool isFolderVault,
    bool deleteOriginal = true,
    void Function(RelocationPhase phase)? onPhase,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) async {
    if (uri.startsWith('usb:') || uri.startsWith('composite:')) {
      throw const RelocationException(RelocationFailure.unsupportedSource);
    }
    if (AppStorageVaultUri.isAppStorage(uri)) {
      throw const RelocationException(RelocationFailure.alreadyInAppStorage);
    }
    return await _run(
      uri: uri,
      isFolderVault: isFolderVault,
      deleteOriginal: deleteOriginal,
      onPhase: onPhase,
      copy: (opId) => _gateway.copyIn(
        sourceUri: uri,
        isFolderVault: isFolderVault,
        displayName: displayName,
        opId: opId,
        onProgress: onProgress,
      ),
    );
  }

  Future<RelocationOutcome> moveOutOfAppStorage({
    required String uri,
    required String displayName,
    required bool isFolderVault,
    bool deleteOriginal = true,
    void Function(RelocationPhase phase)? onPhase,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) async {
    if (!AppStorageVaultUri.isAppStorage(uri)) {
      throw const RelocationException(RelocationFailure.notInAppStorage);
    }
    return await _run(
      uri: uri,
      isFolderVault: isFolderVault,
      deleteOriginal: deleteOriginal,
      onPhase: onPhase,
      copy: (opId) => _gateway.copyOut(
        sourceUri: uri,
        isFolderVault: isFolderVault,
        displayName: displayName,
        opId: opId,
        onProgress: onProgress,
      ),
    );
  }

  /// Stops the copy in progress. Has no effect once the copy is done and the vault is being switched over.
  Future<void> cancel() async {
    final opId = _copyingOpId;
    if (opId == null) return;
    await _gateway.cancel(opId);
  }

  Future<RelocationOutcome> _run({
    required String uri,
    required bool isFolderVault,
    required bool deleteOriginal,
    required void Function(RelocationPhase phase)? onPhase,
    required Future<RelocationCopy?> Function(int opId) copy,
  }) async {
    if (_busy) throw const RelocationException(RelocationFailure.busy);
    _busy = true;
    try {
      // 1. Copy and verify.
      onPhase?.call(RelocationPhase.copying);
      final opId = _nextOpId++;
      final RelocationCopy? made;
      _copyingOpId = opId;
      try {
        made = await copy(opId);
      } finally {
        _copyingOpId = null;
      }
      if (made == null) return const RelocationOutcome.dismissed();

      // 2. Switch the registration over.
      onPhase?.call(RelocationPhase.switching);
      final RecordMove moved;
      try {
        moved = await _records.moveRecord(oldUri: uri, newUri: made.uri);
      } catch (e) {
        VeLog.w(_kLogTag, 'switching the record failed; removing the copy: $e', e);
        try {
          await _gateway.discardCopy(uri: made.uri, isFolderVault: isFolderVault);
        } catch (cleanup) {
          VeLog.w(_kLogTag, 'could not remove the copy: $cleanup', cleanup);
        }
        throw RelocationException(RelocationFailure.recordSwitchFailed, message: '$e');
      }

      // 3. Finish: delete the original, clear the old location's native state.
      onPhase?.call(RelocationPhase.finishing);
      var finalize = const RelocationFinalize(sourceDeleted: false);
      try {
        finalize = await _gateway.finalize(
          oldUri: uri,
          newUri: made.uri,
          isFolderVault: isFolderVault,
          deleteSource: deleteOriginal,
        );
      } catch (e) {
        // The vault already works from its new location; at worst the original is left behind.
        VeLog.w(_kLogTag, 'finishing the move failed: $e', e);
      }

      return RelocationOutcome(
        completed: true,
        newUri: made.uri,
        bytes: made.bytes,
        files: made.files,
        deleteRequested: deleteOriginal,
        originalDeleted: finalize.sourceDeleted,
        biometricsDropped: moved.biometricsDropped,
        automationReset: finalize.automationReset,
      );
    } finally {
      _busy = false;
    }
  }
}
