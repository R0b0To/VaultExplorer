import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
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

  String _buildFatPath(String fatName) {
    final target = _normalizedTargetDir;
    return target.isEmpty ? fatName : '$target/$fatName';
  }

  Future<({String? savedName, String? error})> saveToVault(XFile xfile, bool isPhoto) async {
    try {
      final tempFile = await _resolveCameraFile(xfile, isPhoto);
      final fatName = await _nextAvailableName(isPhoto: isPhoto);
      final fatPath = _buildFatPath(fatName);

      // Write into the container
      final ok = await vaultExplorerApi.writeBackFile(container, fatPath, tempFile.path);

      // Ensure open write handles are finished if it's a folder vault
      if (['cryptomator', 'gocryptfs', 'cryfs'].contains(container.containerFormat)) {
        await vaultExplorerApi.finishWriteIfCryptomator(container, fatPath);
      }

      await _secureDelete(tempFile);

      if (ok) return (savedName: fatName, error: null);
      return (savedName: null, error: "Couldn't save to the vault");
    } catch (e) {
      return (savedName: null, error: e.toString());
    }
  }

  Future<Set<String>> _getExistingNames() async {
    try {
      final entries = await vaultExplorerApi.listDirectory(container, _normalizedTargetDir) ?? [];
      return entries
          .where((e) => !e.startsWith('System:'))
          .map((e) => RawEntry.parse(e).name)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<String> _nextAvailableName({required bool isPhoto}) async {
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

  Future<File> _resolveCameraFile(XFile xfile, bool isPhoto) async {
    String cleanPath = xfile.path.startsWith('file://') ? Uri.parse(xfile.path).path : xfile.path;
    final directFile = File(cleanPath);
    if (await directFile.exists() && (await directFile.length()) > 0) return directFile;

    final tempDir = await getTemporaryDirectory();
    final ext = isPhoto ? '.jpg' : '.mp4';
    final targetPath = '${tempDir.path}/cam_${DateTime.now().microsecondsSinceEpoch}$ext';

    try {
      await xfile.saveTo(targetPath);
      final savedFile = File(targetPath);
      if (await savedFile.exists() && (await savedFile.length()) > 0) return savedFile;
    } catch (_) {}

    final bytes = await xfile.readAsBytes();
    final fallbackFile = File(targetPath);
    await fallbackFile.writeAsBytes(bytes, flush: true);
    return fallbackFile;
  }

  Future<void> _secureDelete(File file) async {
    try {
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0) {
          final sink = file.openWrite(mode: FileMode.write);
          final zeros = Uint8List(64 * 1024);
          int remaining = len;
          while (remaining > 0) {
            final writeSize = remaining < zeros.length ? remaining : zeros.length;
            sink.add(zeros.sublist(0, writeSize));
            remaining -= writeSize;
          }
          await sink.flush();
          await sink.close();
        }
        await file.delete();
      }
    } catch (_) {
      try { if (await file.exists()) await file.delete(); } catch (_) {}
    }
  }
}