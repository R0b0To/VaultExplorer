import 'dart:io';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/filesystem/file_size.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

class CameraVaultService {
  final MountedContainer container;
  final String targetDirPath;
  final VaultFileIoApi _fileIoApi;
  final VaultLifecycleApi _lifecycleApi;

  CameraVaultService({
    required this.container,
    required this.targetDirPath,
    required this._fileIoApi,
    required this._lifecycleApi,
  });

  String get _normalizedTargetDir {
    return targetDirPath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }

  String buildVirtualPath(String name) {
    final target = _normalizedTargetDir;
    return target.isEmpty ? name : '$target/$name';
  }

  /// Name for a captured photo or video.
  ///
  /// [reserved] lists names that are spoken for but not in the folder yet,
  /// such as a video that is still being written in the background. Without
  /// it two captures saved within the same second would be given one name.
  Future<String> nextAvailableName({
    required bool isPhoto,
    Set<String> reserved = const {},
  }) {
    return _nextAvailableName(
      prefix: isPhoto ? 'IMG_' : 'VID_',
      ext: isPhoto ? '.jpg' : '.mp4',
      reserved: reserved,
    );
  }

  /// Name for a page from the document scanner: `SCAN_<timestamp>.jpg`.
  Future<String> nextAvailableScanImageName() {
    return _nextAvailableName(prefix: 'SCAN_', ext: '.jpg');
  }

  /// Name for a scanned document saved as one PDF: `SCAN_<timestamp>.pdf`.
  Future<String> nextAvailableScanPdfName() {
    return _nextAvailableName(prefix: 'SCAN_', ext: '.pdf');
  }

  /// Name for an audio-only recording: `AUD_<timestamp>.m4a` (AAC in an
  /// MPEG-4 container, which is what the native recorder produces).
  ///
  /// [at] stamps the name with when the recording started rather than when
  /// it is saved, which can be minutes later after review.
  Future<String> nextAvailableAudioName({DateTime? at}) {
    return _nextAvailableName(prefix: 'AUD_', ext: '.m4a', at: at);
  }

  Future<String> _nextAvailableName({
    required String prefix,
    required String ext,
    DateTime? at,
    Set<String> reserved = const {},
  }) async {
    final existing = {...await _getExistingNames(), ...reserved};
    final now = at ?? DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    var candidate = '$prefix$stamp$ext';
    var counter = 1;
    while (existing.contains(candidate)) {
      candidate = '$prefix${stamp}_$counter$ext';
      counter++;
    }
    return candidate;
  }

  Future<bool> hasEnoughSpaceFor(int requiredBytes) async {
    if (requiredBytes <= 0) return true;
    try {
      final info = await _fileIoApi.getSpaceInfo(container);
      if (info == null || info.length < 2 || info[1] < 0) return true;
      return fitsWithinSpaceSafetyMargin(requiredBytes, info[1]);
    } catch (_) {
      // Space information is best effort. The write itself remains the
      // authoritative check when the mounted vault cannot report capacity.
      return true;
    }
  }

  Future<int?> localFileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  Future<bool> finalizeVaultWrite(String virtualPath) async {
    if (['cryptomator', 'gocryptfs', 'cryfs'].contains(container.containerFormat)) {
      return _lifecycleApi.finishWrite(container, virtualPath);
    }
    return true;
  }

  Future<bool> deleteFile(String virtualPath) async {
    try {
      return await _fileIoApi.deleteFile(container, virtualPath);
    } catch (_) {
      return false;
    }
  }

  Future<Set<String>> _getExistingNames() async {
    try {
      final entries = await _fileIoApi.listDirectory(container, _normalizedTargetDir) ?? [];
      return entries
          .where((e) => !e.startsWith('System:'))
          .map((e) => RawEntry.parse(e).name)
          .toSet();
    } catch (e) {
      return {};
    }
  }
}
