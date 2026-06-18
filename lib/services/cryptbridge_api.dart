import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../models/mounted_container.dart';

class CryptBridgeApi {
  static const _channel = MethodChannel('com.example.cryptbridge/engine');

  static Future<String?> pickContainer() =>
      _channel.invokeMethod<String>('pickContainer');

  static Future<({int volId, List<String> files})?> unlockContainer(
      String filePath, String password, int pim) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('unlockContainer', {
      'filePath': filePath,
      'password': password,
      'pim': pim,
    });
    if (raw == null) return null;
    final volId = raw['volId'] as int;
    final files = (raw['files'] as List<Object?>).cast<String>();
    return (volId: volId, files: files);
  }

  static Future<bool> lockContainer(String filePath) async {
    final result = await _channel.invokeMethod<bool>('lockContainer', {
      'filePath': filePath,
    });
    return result ?? false;
  }
static Future<bool> openWithApp(MountedContainer container, String fileName) async {
    final result = await _channel.invokeMethod<bool>('openWithApp', {
      'filePath': container.uri,
      'fileName': fileName,
    });
    return result ?? false;
  }
  static Future<bool> decryptFile(
      MountedContainer container, String fileName, String destPath) async {
    final result = await _channel.invokeMethod<bool>('decryptFile', {
      'filePath': container.uri,
      'password': container.password,
      'pim': container.pim,
      'fileName': fileName,
      'destPath': destPath,
    });
    return result ?? false;
  }

  static Future<int> getFileSize(MountedContainer container, String fileName) async {
    final result = await _channel.invokeMethod<int>('getFileSize', {
      'filePath': container.uri,
      'password': container.password,
      'pim': container.pim,
      'fileName': fileName,
    });
    return result ?? 0;
  }

  static Future<Uint8List?> readFileChunk(
      MountedContainer container, String fileName, int offset, int length) async {
    final result = await _channel.invokeMethod<Uint8List>('readFileChunk', {
      'filePath': container.uri,
      'password': container.password,
      'pim': container.pim,
      'fileName': fileName,
      'offset': offset,
      'length': length,
    });
    return result;
  }

  static Future<List<String>?> listDirectory(MountedContainer container, String dirPath) async {
    final result = await _channel.invokeMethod<List<Object?>>('listDirectory', {
      'filePath': container.uri,
      'password': container.password,
      'pim': container.pim,
      'dirPath': dirPath,
    });
    return result?.cast<String>();
  }

  static Future<bool> createDirectory(MountedContainer container, String dirPath) async {
    final result = await _channel.invokeMethod<bool>('createDirectory', {
      'filePath': container.uri,
      'password': container.password,
      'pim': container.pim,
      'dirPath': dirPath,
    });
    return result ?? false;
  }

  static Future<bool> renameFile(MountedContainer container, String oldPath, String newPath) async {
    final result = await _channel.invokeMethod<bool>('renameFile', {
      'filePath': container.uri,
      'password': container.password,
      'pim': container.pim,
      'oldPath': oldPath,
      'newPath': newPath,
    });
    return result ?? false;
  }

  static Future<bool> deleteFile(MountedContainer container, String fileName) async {
    final result = await _channel.invokeMethod<bool>('deleteFile', {
      'filePath': container.uri,
      'password': container.password,
      'pim': container.pim,
      'fileName': fileName,
    });
    return result ?? false;
  }

  static Future<bool> writeBackFile(
      MountedContainer container, String fileName, String sourcePath) async {
    final result = await _channel.invokeMethod<bool>('writeBackFile', {
      'filePath': container.uri,
      'password': container.password,
      'pim': container.pim,
      'fileName': fileName,
      'sourcePath': sourcePath,
    });
    return result ?? false;
  }

  // Helper method to write an empty text file into the VeraCrypt partition on-demand
  static Future<bool> createEmptyFile(MountedContainer container, String fileName) async {
    final tempFile = File('${Directory.systemTemp.path}/cb_empty');
    if (!await tempFile.exists()) {
      await tempFile.create();
    }
    return writeBackFile(container, fileName, tempFile.path);
  }
}