library;

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/password_exchange/exchange_record.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';
import 'package:vaultexplorer/features/tools/services/vault_file_scanner.dart';

class PasswordImportOutcome {
  final int imported;
  final int skipped;
  final List<String> errors;
  const PasswordImportOutcome({required this.imported, required this.skipped, this.errors = const []});
}

/// Thrown by [PasswordInterchangeService.importIntoVault] when [MountedContainer.readOnly]
/// is set -- mirrors the guard every other write path in this app
/// (see [VaultItemEditScreen]'s own readOnly check) already applies.
class VaultReadOnlyException implements Exception {
  const VaultReadOnlyException();
  @override
  String toString() => 'This container is open read-only.';
}

class PasswordInterchangeService {
  PasswordInterchangeService(this._fileIoApi, this._itemsService);

  final VaultFileIoApi _fileIoApi;
  final VaultItemsService _itemsService;

  VaultItemType? _typeForFileName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    for (final t in VaultItemType.values) {
      if (t.name.toLowerCase() == ext) return t;
    }
    return null;
  }

  /// Reads every Item Vault entry under [folderPath] (vault-relative; empty
  /// = vault root) as an [ExchangeRecord], ready for a codec's `encode`.
  /// Plain files that aren't Item Vault entries are ignored, same as the
  /// file browser's own share-sheet filter does.
  Future<List<ExchangeRecord>> collectFromVault({
    required MountedContainer container,
    required String folderPath,
    required bool recursive,
  }) async {
    final scanner = VaultFileScanner(_fileIoApi);
    final records = <ExchangeRecord>[];
    final normalizedRoot = folderPath.isEmpty ? '' : folderPath;

    await for (final file in scanner.scan(
      container,
      rootPath: normalizedRoot,
      maxDepth: recursive ? kVaultScanDefaultMaxDepth : 0,
    )) {
      final type = _typeForFileName(file.name);
      if (type == null) continue;

      final item = await _itemsService.loadItem(container, file.relativePath);
      if (item == null) continue;

      final slash = file.relativePath.lastIndexOf('/');
      final dirPath = slash == -1 ? '' : file.relativePath.substring(0, slash);
      final rootPrefix = normalizedRoot.isEmpty ? '' : '$normalizedRoot/';
      final relativeDir = dirPath.startsWith(rootPrefix) ? dirPath.substring(rootPrefix.length) : (dirPath == normalizedRoot ? '' : dirPath);
      final segments = relativeDir.isEmpty ? const <String>[] : relativeDir.split('/');

      records.add(ExchangeRecord.fromVaultItem(item, folderPath: segments));
    }
    return records;
  }

  /// Writes [records] into the Item Vault under [destFolderPath]. When
  /// [mirrorFolders] is true (the default), each record's
  /// [ExchangeRecord.folderPath] is recreated as subfolders under
  /// [destFolderPath] -- matching what a KDBX/Bitwarden-JSON import
  /// recovered from the source file's own groups/folders; when false,
  /// every record lands directly in [destFolderPath], which import screens
  /// offer as a simpler option for a small, flat CSV.
  Future<PasswordImportOutcome> importIntoVault({
    required MountedContainer container,
    required String destFolderPath,
    required List<ExchangeRecord> records,
    bool mirrorFolders = true,
  }) async {
    if (container.readOnly) throw const VaultReadOnlyException();

    var imported = 0;
    var skipped = 0;
    final errors = <String>[];
    final existingNamesByDir = <String, Set<String>>{};
    final createdDirs = <String>{};

    Future<Set<String>> existingNamesFor(String dirPath) async {
      final cached = existingNamesByDir[dirPath];
      if (cached != null) return cached;
      final raw = await _fileIoApi.listDirectory(container, dirPath) ?? const [];
      final names = RawEntry.parseAll(raw).map((e) => e.name.toLowerCase()).toSet();
      existingNamesByDir[dirPath] = names;
      return names;
    }

    for (final record in records) {
      try {
        final segments = mirrorFolders ? record.folderPath : const <String>[];
        final dirPath = [
          if (destFolderPath.isNotEmpty) destFolderPath,
          ...segments,
        ].join('/');

        if (segments.isNotEmpty && createdDirs.add(dirPath)) {
          // Best-effort: if the folder already exists this is a harmless
          // no-op on every backend VaultFileIoApi wraps (SAF, local, native).
          await _fileIoApi.createDirectory(container, dirPath);
        }

        final names = await existingNamesFor(dirPath);
        final desiredName = '${record.title.isEmpty ? '(untitled)' : record.title}.${record.type.name}';
        final uniqueName = FileOperationService.makeUniqueName(desiredName, names);
        names.add(uniqueName.toLowerCase());
        final finalPath = dirPath.isEmpty ? uniqueName : '$dirPath/$uniqueName';

        final ok = await _itemsService.saveItem(container, finalPath, record.toVaultItem());
        if (ok) {
          imported++;
        } else {
          skipped++;
          errors.add('Could not save "${record.title}".');
        }
      } catch (e) {
        skipped++;
        errors.add('Could not save "${record.title}": $e');
      }
    }

    return PasswordImportOutcome(imported: imported, skipped: skipped, errors: errors);
  }
}
