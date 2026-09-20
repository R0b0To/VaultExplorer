import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

/// A random RFC 4122 version-4 UUID. (The app has no `uuid` dependency and
/// doesn't need one for this.)
String generateSyncId() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Reads and writes `/.vaultexplorer/sync_config.json` -- the rules, kept
/// inside the encrypted vault so they are encrypted at rest and travel
/// with it.
class SyncConfigStore {
  static const String _tag = 'SyncConfigStore';
  static const String fileName = 'sync_config.json';
  static const String filePath = '$kVaultMetaDir/$fileName';

  final VaultFileIoApi _io;
  const SyncConfigStore(this._io);

  /// The vault's config, or null if it has none yet.
  ///
  /// Throws [FormatException] if the file exists but can't be understood:
  /// callers must not "repair" that by writing a fresh config over it.
  Future<SyncConfig?> load(MountedContainer vault) async {
    // Ask the directory listing rather than trusting getFileSize for a
    // path that may not exist: "missing" must not be confused with
    // "unreadable", because only the latter is an error.
    if (!await _exists(vault)) return null;
    final bytes = await _io.readWholeFile(vault, filePath);
    if (bytes == null || bytes.isEmpty) return null;
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('sync_config.json: not an object');
    }
    return SyncConfig.fromJson(json);
  }

  Future<bool> _exists(MountedContainer vault) async {
    try {
      final raw = await _io.listDirectory(vault, kVaultMetaDir);
      if (raw == null) return false;
      return RawEntry.parseAll(raw).any((e) => !e.isDir && e.name == fileName);
    } catch (_) {
      return false;
    }
  }

  /// [load], or a brand-new empty config (fresh `vaultSyncId`) when there
  /// isn't one. Nothing is written until [save].
  Future<SyncConfig> loadOrCreate(MountedContainer vault) async {
    return await load(vault) ?? SyncConfig(vaultSyncId: generateSyncId());
  }

  Future<bool> save(MountedContainer vault, SyncConfig config) async {
    if (vault.readOnly) return false;
    try {
      // Fails harmlessly if the folder already exists.
      await _io.createDirectory(vault, kVaultMetaDir);
      final text = const JsonEncoder.withIndent('  ').convert(config.toJson());
      return await _io.writeWholeFile(
        vault,
        filePath,
        Uint8List.fromList(utf8.encode(text)),
      );
    } catch (e) {
      VeLog.w(_tag, 'config save failed', e);
      return false;
    }
  }

  /// Stamps `lastSyncedAt` on the given rules. Re-reads the file first so
  /// a rule edited in the UI while a sync was running isn't overwritten
  /// with the copy the run started from.
  Future<void> updateLastSynced(
    MountedContainer vault,
    Map<String, DateTime> stamps,
  ) async {
    if (stamps.isEmpty) return;
    try {
      final current = await load(vault);
      if (current == null) return;
      final updated = [
        for (final r in current.rules)
          stamps.containsKey(r.id) ? r.copyWith(lastSyncedAt: stamps[r.id]) : r,
      ];
      await save(vault, current.copyWith(rules: updated));
    } catch (e) {
      VeLog.w(_tag, 'lastSyncedAt update failed', e);
    }
  }
}

/// The device-specific half of a rule's target: which folder on *this*
/// phone the rule points at.
///
/// An SAF tree URI (and the persistable permission behind it) belongs to
/// one device, so it is kept in the app's secure storage rather than in
/// the vault, keyed by `vaultSyncId` + rule id. The URI stored in the
/// vault's own config is only the portable default; a binding, when
/// present, wins.
///
/// The folder *within* the target ([subPath]) is part of the binding too,
/// not just the tree: two devices that picked different folders for the
/// same rule must not rewrite each other's choice through the shared,
/// in-vault config.
///
/// The persistable-permission grant itself is taken natively when the
/// folder is picked (`VaultPickerHandlers.pickExtractFolder` calls
/// `takePersistableUriPermission` with read+write), so nothing more is
/// needed here.
@immutable
class SyncTargetBinding {
  final String uri;
  final String displayName;
  final String subPath;

  const SyncTargetBinding({
    required this.uri,
    this.displayName = '',
    this.subPath = '',
  });

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'displayName': displayName,
    if (subPath.isNotEmpty) 'subPath': subPath,
  };

  static SyncTargetBinding? tryParse(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final json = jsonDecode(source);
      if (json is! Map) return null;
      final uri = json['uri'];
      if (uri is! String || uri.isEmpty) return null;
      final name = json['displayName'];
      final sub = json['subPath'];
      return SyncTargetBinding(
        uri: uri,
        displayName: name is String ? name : '',
        subPath: sub is String ? sub : '',
      );
    } catch (_) {
      return null;
    }
  }
}

class SyncTargetBindingStore {
  final AppSecureStorage _storage;
  const SyncTargetBindingStore(this._storage);

  static String _key(String vaultSyncId, String ruleId) =>
      'vexp_sync_target:$vaultSyncId:$ruleId';

  Future<SyncTargetBinding?> read(String vaultSyncId, String ruleId) async {
    try {
      return SyncTargetBinding.tryParse(
        await _storage.read(key: _key(vaultSyncId, ruleId)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String vaultSyncId,
    String ruleId,
    SyncTargetBinding binding,
  ) => _storage.write(
    key: _key(vaultSyncId, ruleId),
    value: jsonEncode(binding.toJson()),
  );

  Future<void> delete(String vaultSyncId, String ruleId) =>
      _storage.delete(key: _key(vaultSyncId, ruleId));
}
