part of 'vault_explorer_api.dart';

/// Native diagnosis result: [diagnosisCode] matches RepairDiagnosis's
/// ordinal (0=healthy, 1=headerCorrupted, 2=filesystemDirty); [format] is
/// the wire-name container format ("veracrypt"/"luks1"/"luks2"/
/// "bitlocker") when known, or null (always null for the mounted-volume
/// variant, which only ever reports on filesystem health -- see
/// diagnoseMountedVolumeFilesystem in container_repair.cpp).
typedef RepairDiagnosisResult = ({int diagnosisCode, String? format});

mixin _RepairOps {
  Future<RepairDiagnosisResult> diagnoseUnmountedContainerFile(String uri) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      ChannelMethods.diagnoseUnmountedContainerFile,
      {'uri': uri},
    );
    return (
      diagnosisCode: raw?['diagnosisCode'] as int? ?? 1,
      format: raw?['format'] as String?,
    );
  }

  Future<RepairDiagnosisResult> diagnoseMountedVolumeFilesystem(int volId) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      ChannelMethods.diagnoseMountedVolumeFilesystem,
      {'volId': volId},
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

  Future<bool> runMountedVolumeFilesystemCheck(int volId) async {
    final success = await _channel.invokeMethod<bool>(
      ChannelMethods.runMountedVolumeFilesystemCheck,
      {'volId': volId},
    );
    return success ?? false;
  }
}