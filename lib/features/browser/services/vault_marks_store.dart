import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_marks_service.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

/// Where a container's marks live.
enum VaultMarksLocation {
  /// A writable vault keeps them in `/.vaultexplorer/marks.json`, inside the
  /// encrypted container: encrypted at rest, and they travel with the vault
  /// to another device. They are only readable while it is unlocked.
  inVault,

  /// A read-only vault cannot be written to, so edits are kept on this device
  /// in secure storage (Android Keystore). Until the first edit, the vault's
  /// own marks, if it has any, are shown.
  thisDevice,

  /// Phone storage and external storage locations aren't vaults and must not
  /// get a hidden folder dropped into the person's files, so their marks sit
  /// in the app's own small JSON file, one entry per location.
  phoneStorage,
}

/// Reads and writes the bookmarks and pins of one container, wherever they
/// live (see [VaultMarksLocation]).
///
/// This class only moves bytes. Which state is current, and in what order
/// changes are saved, is decided by `FileBrowserPinsBookmarks`: it is the one
/// place that writes marks.
class VaultMarksStore {
  static const String _tag = 'VaultMarksStore';
  static const String fileName = 'marks.json';
  static const String filePath = '$kVaultMetaDir/$fileName';

  final VaultFileIoApi _io;
  final AppSecureStorage _secure;
  final DecoyLocalMarksService _local;

  VaultMarksStore({
    required VaultFileIoApi io,
    required AppSecureStorage secure,
    required DecoyLocalMarksService local,
  }) : _io = io,
       _secure = secure,
       _local = local;

  static VaultMarksLocation locationFor(MountedContainer container) {
    if (container.isLocalStorage) return VaultMarksLocation.phoneStorage;
    if (container.readOnly) return VaultMarksLocation.thisDevice;
    return VaultMarksLocation.inVault;
  }

  /// The stored marks, or [VaultMarks.empty] when there are none yet.
  ///
  /// An unparseable file counts as empty (the next save replaces it); a
  /// failure to *reach* the storage throws, so the caller can tell "nothing
  /// saved" from "couldn't look" and avoid saving over something it never read.
  Future<VaultMarks> load(MountedContainer container) async {
    switch (locationFor(container)) {
      case VaultMarksLocation.phoneStorage:
        return _local.load(container.uri);
      case VaultMarksLocation.thisDevice:
        final own = await _readDevice(container);
        if (own != null) return own;
        return await _readVault(container) ?? VaultMarks.empty;
      case VaultMarksLocation.inVault:
        return await _readVault(container) ?? VaultMarks.empty;
    }
  }

  /// Returns whether the marks were stored.
  Future<bool> save(MountedContainer container, VaultMarks marks) async {
    try {
      switch (locationFor(container)) {
        case VaultMarksLocation.phoneStorage:
          return await _local.save(container.uri, marks);
        case VaultMarksLocation.thisDevice:
          // Written even when empty: an empty entry is what stops the vault's
          // own marks from reappearing after the last one was removed.
          return await _secure.writeVerified(
            key: ContainerRepository.marksKey(container.uri),
            value: jsonEncode(marks.toJson()),
          );
        case VaultMarksLocation.inVault:
          return await _writeVault(container, marks);
      }
    } catch (e) {
      VeLog.w(_tag, 'marks save failed', e);
      return false;
    }
  }

  // ── In the vault ─────────────────────────────────────────────────────────

  Future<VaultMarks?> _readVault(MountedContainer vault) async {
    // Ask the directory listing instead of trusting getFileSize on a path
    // that may not exist: "missing" is normal, "unreadable" is not.
    if (!await _vaultFileExists(vault)) return null;
    final bytes = await _io.readWholeFile(vault, filePath);
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return VaultMarks.fromJson(jsonDecode(utf8.decode(bytes)));
    } on FormatException catch (e) {
      VeLog.w(_tag, '$fileName is unreadable; starting empty', e);
      return null;
    }
  }

  Future<bool> _vaultFileExists(MountedContainer vault) async {
    final raw = await _io.listDirectory(vault, kVaultMetaDir);
    if (raw == null) return false;
    return RawEntry.parseAll(raw).any((e) => !e.isDir && e.name == fileName);
  }

  Future<bool> _writeVault(MountedContainer vault, VaultMarks marks) async {
    if (vault.readOnly) return false;
    // Fails harmlessly if the folder already exists.
    await _io.createDirectory(vault, kVaultMetaDir);
    final text = const JsonEncoder.withIndent('  ').convert(marks.toJson());
    return _io.writeWholeFile(
      vault,
      filePath,
      Uint8List.fromList(utf8.encode(text)),
    );
  }

  // ── On this device ───────────────────────────────────────────────────────

  Future<VaultMarks?> _readDevice(MountedContainer vault) async {
    final raw = await _secure.read(
      key: ContainerRepository.marksKey(vault.uri),
    );
    if (raw == null || raw.isEmpty) return null;
    try {
      return VaultMarks.fromJson(jsonDecode(raw));
    } on FormatException catch (e) {
      VeLog.w(_tag, 'device marks are unreadable; ignoring them', e);
      return null;
    }
  }
}

final vaultMarksStoreProvider = Provider<VaultMarksStore>(
  (ref) => VaultMarksStore(
    io: ref.watch(vaultFileIoApiProvider),
    secure: ref.watch(appSecureStorageProvider),
    local: DecoyLocalMarksService(),
  ),
);
