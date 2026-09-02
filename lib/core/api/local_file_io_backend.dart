// Local-storage counterpart to the native-channel calls in
// [VaultFileIoApi] (vault_file_io_api.dart). Every method here operates on
// a real, plain, already-decrypted absolute path via dart:io/dart:ui --
// there is no container, no session, and nothing to decrypt. [VaultFileIoApi]
// delegates to this class for any call whose [MountedContainer] is
// [kDecoyLocalVolId] (see local_storage_container.dart), the same split
// already established for delete/copy/move in
// [FileOperationService.enqueueLocalTransfer] and for open/share in
// [VaultLocalShareApi].
//
// Paths handed in by callers (file_browser_screen.dart, browser_dialogs.dart,
// etc.) are always relative to the container root -- '' at the root, or a
// slash-joined relative path like 'DCIM/Camera/photo.jpg', never with a
// leading slash (see browser_dialogs.dart's `'$currentDirPath/$name'`
// construction). [_resolve] joins that onto the container's real root path.
import 'dart:io';
import 'dart:typed_data';


import 'package:path/path.dart' as p;
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';

class LocalFileIoBackend {
  const LocalFileIoBackend();

  static const DecoyLocalRepository _repo = DecoyLocalRepository();

  String _resolve(String rootPath, String relativePath) =>
      relativePath.isEmpty ? rootPath : p.join(rootPath, relativePath);

  Future<List<String>> listDirectory(String rootPath, String dirPath) async {
    final entries = await _repo.listDirectory(_resolve(rootPath, dirPath));
    return entries.map((e) => e.raw).toList();
  }

  Future<int> getFileSize(String rootPath, String fileName) async {
    try {
      final file = File(_resolve(rootPath, fileName));
      if (!await file.exists()) return -1;
      return await file.length();
    } catch (_) {
      return -1;
    }
  }

  Future<int> getFolderSize(String rootPath, String dirPath) =>
      _repo.folderSize(_resolve(rootPath, dirPath));

  Future<Uint8List?> readFileChunk(
    String rootPath,
    String fileName,
    int offset,
    int length,
  ) async {
    RandomAccessFile? raf;
    try {
      raf = await File(_resolve(rootPath, fileName)).open(mode: FileMode.read);
      await raf.setPosition(offset);
      return await raf.read(length);
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  /// Writes [data] at [offset]. `offset == 0` (re)creates/truncates the
  /// file -- matching the semantics [VaultFileIoApi.writeWholeFile]'s
  /// chunk loop and [VaultFileIoApi.createEmptyFile] already rely on for
  /// every other backend -- any later offset opens without truncating and
  /// explicitly seeks, so out-of-order or sparse writes still land
  /// correctly rather than merely appending.
  Future<bool> writeFileChunk(
    String rootPath,
    String fileName,
    int offset,
    Uint8List data,
  ) async {
    RandomAccessFile? raf;
    try {
      final file = File(_resolve(rootPath, fileName));
      await file.parent.create(recursive: true);
      raf = await file.open(mode: offset == 0 ? FileMode.write : FileMode.append);
      await raf.setPosition(offset);
      await raf.writeFrom(data);
      await raf.flush();
      return true;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  /// Fails rather than overwriting -- an already-occupied target name must
  /// fail, never silently replace what's there (same rule the native
  /// backends already enforce for createDirectory/renameFile).
  Future<bool> createDirectory(String rootPath, String dirPath) async {
    try {
      final path = _resolve(rootPath, dirPath);
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        return false;
      }
      await Directory(path).create(recursive: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> renameFile(
    String rootPath,
    String oldPath,
    String newPath,
  ) async {
    try {
      final from = _resolve(rootPath, oldPath);
      final to = _resolve(rootPath, newPath);
      if (await FileSystemEntity.type(to) != FileSystemEntityType.notFound) {
        return false;
      }
      final isDir = await FileSystemEntity.isDirectory(from);
      if (isDir) {
        await Directory(from).rename(to);
      } else {
        await File(from).rename(to);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteFile(String rootPath, String fileName) async {
    try {
      await _repo.delete(_resolve(rootPath, fileName));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setLastModifiedTime(
    String rootPath,
    String fileName,
    int epochSeconds,
  ) async {
    try {
      await File(_resolve(rootPath, fileName))
          .setLastModified(DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000));
      return true;
    } catch (_) {
      return false;
    }
  }

}