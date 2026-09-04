import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

/// Native diagnosis result: [diagnosisCode] matches RepairDiagnosis's
/// ordinal (0=healthy, 1=headerCorrupted, 2=filesystemDirty); [format] is
/// the wire-name container format ("veracrypt"/"luks1"/"luks2"/
/// "bitlocker") when known, or null (always null for the mounted-volume
/// variant, which only ever reports on filesystem health -- see
/// diagnoseMountedVolumeFilesystem in container_repair.cpp).
typedef RepairDiagnosisResult = ({int diagnosisCode, String? format});


class VaultRepairApi {
  final MethodChannel _channel;
  const VaultRepairApi(this._channel);

  /// [opId], here and on every other call below, identifies this call to
  /// the wizard's live log panel -- see [VaultEngineEvents.addRepairLogListener]
  /// and RepairLogBridge.kt/reportRepairLog on the native side. Pass a
  /// non-positive value (the default) to skip live logging entirely.
  Future<RepairDiagnosisResult> diagnoseUnmountedContainerFile(String uri, {int opId = -1}) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      ChannelMethods.diagnoseUnmountedContainerFile,
      {'uri': uri, 'opId': opId},
    );
    return (
      diagnosisCode: raw?['diagnosisCode'] as int? ?? 1,
      format: raw?['format'] as String?,
    );
  }

  Future<RepairDiagnosisResult> diagnoseMountedVolumeFilesystem(int volId, {int opId = -1}) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      ChannelMethods.diagnoseMountedVolumeFilesystem,
      {'volId': volId, 'opId': opId},
    );
    return (
      diagnosisCode: raw?['diagnosisCode'] as int? ?? 0,
      format: null,
    );
  }

  Future<FolderVaultRepairReport> repairFolderVault(
    FolderVaultTarget target, {
    String? password,
    int opId = -1,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        ChannelMethods.repairFolderVault,
        {
          'uri': target.treeUri,
          'format': target.format,
          'password': password,
          'volId': target.mountedVolId,
          'opId': opId,
        },
      );
      if (raw == null) throw const FolderVaultInvalidException('Could not repair this vault.');
      return FolderVaultRepairReport.fromWire(raw);
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'INVALID_VAULT':
          throw FolderVaultInvalidException(e.message ?? 'This doesn\'t look like a valid vault.');
        case 'PASSWORD_INCORRECT':
          throw const RepairIncorrectPasswordException();
        default:
          rethrow;
      }
    }
  }

  /// [password]/[pim]/[cipherId]/[hashId] only matter for a VeraCrypt/
  /// TrueCrypt target; pass [password] null on the first attempt and catch
  /// [RepairPasswordRequiredException] to know whether one is actually
  /// needed (LUKS2 targets never throw it). See RepairHandlers.kt's doc
  /// comment for why the format doesn't need to be passed in here.
  Future<bool> restoreBackupHeaderUnmounted({
    required String uri,
    String? password,
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    int opId = -1,
  }) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.restoreBackupHeaderUnmounted,
        {
          'uri': uri,
          'password': password,
          'pim': pim,
          'cipherId': cipherId,
          'hashId': hashId,
          'opId': opId,
        },
      );
      return success ?? false;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'PASSWORD_REQUIRED':
          throw const RepairPasswordRequiredException();
        case 'PASSWORD_INCORRECT':
          throw const RepairIncorrectPasswordException();
        case 'UNSUPPORTED_FORMAT':
          throw const RepairUnsupportedFormatException();
        default:
          rethrow;
      }
    }
  }

  Future<bool> runMountedVolumeFilesystemCheck(int volId, {int opId = -1}) async {
    final success = await _channel.invokeMethod<bool>(
      ChannelMethods.runMountedVolumeFilesystemCheck,
      {'volId': volId, 'opId': opId},
    );
    return success ?? false;
  }

  /// Folder picker for the Check & Repair tool's folder-vault support
  /// (gocryptfs/CryFS/Cryptomator) -- same shape as
  /// [pickCryptomatorVault]/[pickGocryptfsVault]/[pickCryfsVault] (all four
  /// share one native format auto-detector), kept as its own entry point so
  /// the repair tool doesn't have to borrow a picker named after an
  /// unrelated "add a vault" flow. Returns null if the user backs out of
  /// the folder chooser.
  Future<({String uri, String displayName, bool looksLikeVault, String? format})?> pickFolderVaultForRepair() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(ChannelMethods.pickFolderVaultForRepair);
      if (res == null) return null;
      return (
        uri: res['uri'] as String,
        displayName: res['displayName'] as String,
        looksLikeVault: res['looksLikeVault'] as bool? ?? false,
        format: res['format'] as String?,
      );
    } on PlatformException catch (e) {
      logSwallowed('pickFolderVaultForRepair', e);
      return null;
    }
  }

  /// Runs the folder-vault Check tool against [target] -- see
  /// FolderVaultChecker.kt for what gets verified. Omitting [password] runs
  /// a structural-only scan; supplying one also AEAD-verifies every file's
  /// content, and -- for CryFS/Cryptomator, whose directory layout is
  /// itself encrypted -- walks the decrypted tree for missing/orphaned
  /// entries. If [target.isAlreadyMounted], [password] is ignored and the
  /// native side reuses that volume's already-open session key instead,
  /// always producing a full deep scan. Throws [FolderVaultInvalidException]
  /// if the folder doesn't look like a [target.format] vault at all (or, for
  /// an already-mounted target, if its session isn't active anymore), or
  /// [RepairIncorrectPasswordException] if a wrong password was supplied
  /// (never [RepairPasswordRequiredException] -- a password is always
  /// optional here, just less thorough without one).
  Future<FolderVaultCheckReport> checkFolderVault(
    FolderVaultTarget target, {
    String? password,
    int opId = -1,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        ChannelMethods.checkFolderVault,
        {
          'uri': target.treeUri,
          'format': target.format,
          'password': password,
          'volId': target.mountedVolId,
          'opId': opId,
        },
      );
      if (raw == null) throw const FolderVaultInvalidException('Could not read this vault.');
      return FolderVaultCheckReport.fromWire(raw);
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'INVALID_VAULT':
          throw FolderVaultInvalidException(e.message ?? 'This doesn\'t look like a valid vault.');
        case 'PASSWORD_INCORRECT':
          throw const RepairIncorrectPasswordException();
        default:
          rethrow;
      }
    }
  }

  // ── Header Backup tool ──────────────────────────────────────────────

  /// Reads [uri]'s header/keyslot region (see container_repair.cpp's
  /// "Header Backup / Restore" section) and returns the raw payload plus
  /// its wire-name format. Wrapping the result into a [HeaderBackupFile]
  /// (adding the checksum/timestamp/name envelope) is
  /// [ContainerToolService.exportContainerHeader]'s job, not this layer's.
  /// Throws [HeaderBackupUnrecognizedFileException],
  /// [RepairUnsupportedFormatException] (BitLocker/Plain), or
  /// [HeaderBackupUnreadableException] (recognized format, unparseable
  /// fields -- try Check & Repair first).
  Future<({String format, Uint8List bytes})> exportContainerHeader(String uri, {int opId = -1}) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        ChannelMethods.exportContainerHeader,
        {'uri': uri, 'opId': opId},
      );
      if (raw == null) throw const HeaderBackupUnrecognizedFileException();
      return (format: raw['format'] as String, bytes: raw['bytes'] as Uint8List);
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'UNRECOGNIZED_FILE':
          throw const HeaderBackupUnrecognizedFileException();
        case 'UNSUPPORTED_FORMAT':
          throw const RepairUnsupportedFormatException();
        case 'HEADER_UNREADABLE':
          throw const HeaderBackupUnreadableException();
        default:
          rethrow;
      }
    }
  }

  /// Verifies [bytes] is a genuine header for [format] (decrypt-and-CRC
  /// for VeraCrypt, needs [password]; checksum for LUKS2; field-sanity for
  /// LUKS1 -- see container_repair.cpp), then overwrites [uri]'s header
  /// region with it. [pim]/[cipherId]/[hashId] of 255 auto-detect, same
  /// defaults [restoreBackupHeaderUnmounted] uses. Pass [password] null on
  /// the first attempt for a VeraCrypt target and catch
  /// [RepairPasswordRequiredException] to know one is actually needed.
  /// Throws [RepairPasswordRequiredException]/[RepairIncorrectPasswordException]
  /// (VeraCrypt only), [HeaderBackupInvalidException],
  /// [HeaderBackupSizeMismatchException] (the target is smaller than the
  /// backup -- almost certainly the wrong file), or
  /// [RepairUnsupportedFormatException].
  Future<bool> restoreContainerHeaderRegion({
    required String uri,
    required String format,
    required Uint8List bytes,
    String? password,
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    int opId = -1,
  }) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.restoreContainerHeaderRegion,
        {
          'uri': uri,
          'format': format,
          'bytes': bytes,
          'password': password,
          'pim': pim,
          'cipherId': cipherId,
          'hashId': hashId,
          'opId': opId,
        },
      );
      return success ?? false;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'PASSWORD_REQUIRED':
          throw const RepairPasswordRequiredException();
        case 'PASSWORD_INCORRECT':
          throw const RepairIncorrectPasswordException();
        case 'BACKUP_INVALID':
          throw HeaderBackupInvalidException(e.message ?? 'This backup doesn\'t look genuine for this container.');
        case 'SIZE_MISMATCH':
          throw const HeaderBackupSizeMismatchException();
        case 'UNSUPPORTED_FORMAT':
          throw const RepairUnsupportedFormatException();
        default:
          rethrow;
      }
    }
  }

  /// Locates [format]'s config/masterkey file inside the folder vault at
  /// [uri] -- `fileName` is always returned (even if the file's currently
  /// missing) so a restore knows what to recreate; `uri` in the result is
  /// null in that case.
  Future<({String fileName, String? uri, bool exists})> resolveFolderVaultConfigFile({
    required String uri,
    required String format,
  }) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      ChannelMethods.resolveFolderVaultConfigFile,
      {'uri': uri, 'format': format},
    );
    if (raw == null) throw const RepairUnsupportedFormatException();
    return (
      fileName: raw['fileName'] as String,
      uri: raw['uri'] as String?,
      exists: raw['exists'] as bool? ?? false,
    );
  }

  /// Validates [bytes] structurally parses as a genuine [format]
  /// config/masterkey file, then replaces the vault's own copy at [uri]
  /// with it (creating it if currently missing). This does NOT verify the
  /// backup's password matches the vault's -- only that it's a
  /// well-formed file of the right shape; see HeaderBackupHandlers.kt's
  /// doc comment. Throws [HeaderBackupInvalidException] if validation
  /// fails (nothing is written in that case) or [RepairUnsupportedFormatException].
  Future<void> restoreFolderVaultConfig({
    required String uri,
    required String format,
    required Uint8List bytes,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        ChannelMethods.restoreFolderVaultConfig,
        {'uri': uri, 'format': format, 'bytes': bytes},
      );
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'BACKUP_INVALID':
          throw HeaderBackupInvalidException(e.message ?? 'This backup doesn\'t look genuine for this vault.');
        case 'UNSUPPORTED_FORMAT':
          throw const RepairUnsupportedFormatException();
        default:
          rethrow;
      }
    }
  }
}