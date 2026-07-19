import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/mounted_container.dart';
import '../models/vault_item.dart';
import 'vaultexplorer_api.dart';

class VaultItemsService {
  VaultItemsService._();
  static final instance = VaultItemsService._();


  Future<VaultItem?> loadItem(MountedContainer container, String path) async {
    try {
      final size = await vaultExplorerApi.getFileSize(container, path);
      if (size <= 0) return null;

      final bytes = await vaultExplorerApi.readFileChunk(container, path, 0, size);
      if (bytes == null || bytes.isEmpty) return null;

      final json = jsonDecode(utf8.decode(bytes));
      return VaultItem.fromJson(json);
    } catch (e) {
      debugPrint('VaultItemsService.loadItem error: $e');
      return null;
    }
  }

  Future<bool> saveItem(MountedContainer container, String path, VaultItem item) async {
    try {
      final jsonStr = jsonEncode(item.toJson());
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));

      final tmpPath = '$path.tmp';
      await vaultExplorerApi.deleteFile(container, tmpPath);
      
final ok = await vaultExplorerApi.writeFileChunk(container, tmpPath, 0, bytes);
if (!ok) return false;
final finished = await vaultExplorerApi.finishWriteIfCryptomator(container, tmpPath);
if (!finished) return false;

await vaultExplorerApi.deleteFile(container, path);
final renamed = await vaultExplorerApi.renameFile(container, tmpPath, path);
return renamed;
    } catch (e) {
      debugPrint('VaultItemsService.saveItem error: $e');
      return false;
    }
  }
}