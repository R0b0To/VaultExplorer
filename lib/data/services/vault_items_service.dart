import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';

part 'vault_items_service.g.dart';

/// No internal mutable state -> exposed as a pure keep-alive provider per
/// the migration plan's Phase 3 rule, not a Notifier.
@Riverpod(keepAlive: true)
VaultItemsService vaultItemsService(Ref ref) => VaultItemsService(
  ref.watch(vaultFileIoApiProvider),
  ref.watch(vaultLifecycleApiProvider),
);

/// Reads/writes a single JSON-encoded [VaultItem] inside a mounted
/// container. Was a hand-rolled `._()`/`.instance` singleton; now
/// constructor-injected with the two VaultXxxApi slices it needs.
///
/// [instance] is kept only until vault_item_edit_screen.dart,
/// vault_item_detail_screen.dart, and file_browser_screen.dart are migrated
/// to ConsumerWidget and read [vaultItemsServiceProvider] instead (Phase
/// 4/5) -- safe as a bridge because this class holds no state of its own,
/// so the two instances talk to the exact same native channel either way.
/// Delete [instance] once those three call sites are gone.
class VaultItemsService {
  final VaultFileIoApi _fileIo;
  final VaultLifecycleApi _lifecycle;
  const VaultItemsService(this._fileIo, this._lifecycle);

  static final instance = VaultItemsService(
    const VaultFileIoApi(MethodChannel('com.aeidolon.vaultexplorer/engine')),
    VaultLifecycleApi(
      const MethodChannel('com.aeidolon.vaultexplorer/engine'),
      VaultEngineEvents(),
    ),
  );

  Future<VaultItem?> loadItem(MountedContainer container, String path) async {
    try {
      final size = await _fileIo.getFileSize(container, path);
      if (size <= 0) return null;

      final bytes = await _fileIo.readFileChunk(container, path, 0, size);
      if (bytes == null || bytes.isEmpty) return null;

      final json = jsonDecode(utf8.decode(bytes));
      return VaultItem.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  Future<bool> saveItem(
    MountedContainer container,
    String path,
    VaultItem item,
  ) async {
    try {
      final jsonStr = jsonEncode(item.toJson());
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));

      final tmpPath = '$path.tmp';
      await _fileIo.deleteFile(container, tmpPath);

      final ok = await _fileIo.writeFileChunk(container, tmpPath, 0, bytes);
      if (!ok) return false;
      final finished = await _lifecycle.finishWrite(container, tmpPath);
      if (!finished) return false;

      await _fileIo.deleteFile(container, path);
      final renamed = await _fileIo.renameFile(container, tmpPath, path);
      return renamed;
    } catch (e) {
      return false;
    }
  }
}
