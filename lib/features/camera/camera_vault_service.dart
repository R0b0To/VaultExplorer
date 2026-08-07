import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

class CameraVaultService {
  final MountedContainer container;
  final String targetDirPath;

  CameraVaultService({required this.container, required this.targetDirPath});

  String get _normalizedTargetDir {
    return targetDirPath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }

  String buildVirtualPath(String name) {
    final target = _normalizedTargetDir;
    return target.isEmpty ? name : '$target/$name';
  }

  Future<String> nextAvailableName({required bool isPhoto}) async {
    final existing = await _getExistingNames();
    final now = DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    
    final prefix = isPhoto ? 'IMG_' : 'VID_';
    final ext = isPhoto ? '.jpg' : '.mp4';

    var candidate = '$prefix$stamp$ext';
    var counter = 1;
    while (existing.contains(candidate)) {
      candidate = '$prefix${stamp}_$counter$ext';
      counter++;
    }
    return candidate;
  }

  Future<void> finalizeVaultWrite(String virtualPath) async {
    if (['cryptomator', 'gocryptfs', 'cryfs'].contains(container.containerFormat)) {
      await vaultExplorerApi.finishWriteIfCryptomator(container, virtualPath);
    }
  }

  Future<Set<String>> _getExistingNames() async {
    try {
      final entries = await vaultExplorerApi.listDirectory(container, _normalizedTargetDir) ?? [];
      return entries
          .where((e) => !e.startsWith('System:'))
          .map((e) => RawEntry.parse(e).name)
          .toSet();
    } catch (e) {
      debugPrint('CameraVaultService: failed to list target directory, assuming empty.');
      return {};
    }
  }
}