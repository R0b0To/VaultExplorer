part of 'vault_explorer_api.dart';

/// Native diagnosis result: [diagnosisCode] matches RepairDiagnosis's
/// ordinal (0=healthy, 1=headerCorrupted, 2=filesystemDirty); [format] is
/// the wire-name container format ("veracrypt"/"luks1"/"luks2"/
/// "bitlocker") when known, or null (always null for the mounted-volume
/// variant, which only ever reports on filesystem health -- see
/// diagnoseMountedVolumeFilesystem in container_repair.cpp).
typedef RepairDiagnosisResult = ({int diagnosisCode, String? format});

mixin _RepairOps {
  /// [opId], here and on every other call below, identifies this call to
  /// the wizard's live log panel -- see [VaultExplorerApi.addRepairLogListener]
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
      _logSwallowed('pickFolderVaultForRepair', e);
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
}