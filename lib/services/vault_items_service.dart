import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/mounted_container.dart';
import '../models/vault_item.dart';
import 'vaultexplorer_api.dart';

class VaultItemsService {
  VaultItemsService._();
  static final instance = VaultItemsService._();

  /// Unpacks legacy single `.vault_items.json` into individual files 
  /// natively stored in the container, then removes the legacy file.
  Future<void> migrateIfNeeded(MountedContainer container) async {
    try {
      final size = await vaultExplorerApi.getFileSize(
        container,
        VaultItemStore.storeFileName,
      );
      if (size <= 0) return;

      final bytes = await vaultExplorerApi.readFileChunk(
        container,
        VaultItemStore.storeFileName,
        0,
        size,
      );
      if (bytes == null || bytes.isEmpty) return;

      final raw = utf8.decode(bytes);
      final items = VaultItemStore.decode(raw);

      for (final item in items) {
        String baseName = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        if (baseName.isEmpty) baseName = 'Untitled';
        
        String path = '$baseName.${item.type.name}';
        
        // Avoid naming collisions
        int c = 1;
        while (await vaultExplorerApi.getFileSize(container, path) > 0) {
          path = '$baseName ($c).${item.type.name}';
          c++;
        }
        
        await saveItem(container, path, item);
      }

      await vaultExplorerApi.deleteFile(container, VaultItemStore.storeFileName);
    } catch (e) {
      debugPrint('VaultItemsService migration error: $e');
    }
  }

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

      await vaultExplorerApi.deleteFile(container, path);
      await vaultExplorerApi.renameFile(container, tmpPath, path);
      return true;
    } catch (e) {
      debugPrint('VaultItemsService.saveItem error: $e');
      return false;
    }
  }
}