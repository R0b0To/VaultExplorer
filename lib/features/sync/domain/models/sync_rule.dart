import 'package:flutter/foundation.dart';

/// Which side may be written to by a rule.
///
/// NOTE: `features/tools/models/vault_sync_models.dart` already declares an
/// unrelated `SyncDirection` (twoWay / leftToRight / rightToLeft) for the
/// manual Vault Sync tool. Files that need both must import one of them
/// with a prefix (`import '...' as manual;`).
enum SyncDirection { twoWay, vaultToTarget, targetToVault }

enum ConflictStrategy { keepNewer, renameConflict, vaultWins, targetWins }

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is String) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
  }
  return fallback;
}

/// Trims and de-duplicates slashes: `"/Notes//2024/"` -> `"Notes/2024"`.
/// The empty string means "the root".
String normalizeSyncPath(String path) =>
    path.split('/').where((s) => s.isNotEmpty).join('/');

/// One configured sync relationship between a folder inside a vault and a
/// folder on a target (device storage, an SAF grant, or another unlocked
/// vault).
///
/// Rules live inside the vault (see `SyncConfigStore`), so they are
/// encrypted at rest and travel with the vault. [targetEndpointUri] is
/// therefore only the *portable* description of the target; a device may
/// override it with a locally stored grant (`SyncTargetBindingStore`),
/// because an SAF URI from one phone means nothing on another.
@immutable
class SyncRule {
  /// Default patterns applied to a new rule. The engine additionally
  /// always ignores its own `*.vexp_tmp` / `*.vexp_old` files and the
  /// vault's `.vaultexplorer` folder, whatever this list says.
  static const List<String> defaultIgnorePatterns = [
    '*.tmp',
    '*~',
    '.*.swp',
    '.DS_Store',
    'Thumbs.db',
    // Android media-store trash / half-written entries.
    '.trashed-*',
    '.pending-*',
  ];

  final String id;

  /// Folder inside the vault, e.g. `"Notes"`. `""` = the whole vault.
  final String vaultInternalPath;

  /// SAF tree URI, absolute device path, or the URI of another vault.
  final String targetEndpointUri;

  /// Folder below [targetEndpointUri] (usually empty: a picked SAF tree or
  /// path already *is* the folder).
  final String targetSubPath;

  /// Human label for banners and notifications ("Documents").
  final String targetDisplayName;

  final SyncDirection direction;
  final ConflictStrategy conflictStrategy;
  final bool autoSyncOnUnlock;
  final bool liveWatch;
  final bool deleteOrphans;
  final List<String> ignorePatterns;
  final DateTime? lastSyncedAt;

  const SyncRule({
    required this.id,
    required this.vaultInternalPath,
    required this.targetEndpointUri,
    this.targetSubPath = '',
    this.targetDisplayName = '',
    this.direction = SyncDirection.twoWay,
    this.conflictStrategy = ConflictStrategy.renameConflict,
    this.autoSyncOnUnlock = true,
    this.liveWatch = false,
    this.deleteOrphans = false,
    this.ignorePatterns = defaultIgnorePatterns,
    this.lastSyncedAt,
  });

  /// [vaultInternalPath] without surrounding slashes (`""` = root).
  String get vaultRelativePath => normalizeSyncPath(vaultInternalPath);

  String get targetRelativePath => normalizeSyncPath(targetSubPath);

  SyncRule copyWith({
    String? vaultInternalPath,
    String? targetEndpointUri,
    String? targetSubPath,
    String? targetDisplayName,
    SyncDirection? direction,
    ConflictStrategy? conflictStrategy,
    bool? autoSyncOnUnlock,
    bool? liveWatch,
    bool? deleteOrphans,
    List<String>? ignorePatterns,
    DateTime? lastSyncedAt,
  }) {
    return SyncRule(
      id: id,
      vaultInternalPath: vaultInternalPath ?? this.vaultInternalPath,
      targetEndpointUri: targetEndpointUri ?? this.targetEndpointUri,
      targetSubPath: targetSubPath ?? this.targetSubPath,
      targetDisplayName: targetDisplayName ?? this.targetDisplayName,
      direction: direction ?? this.direction,
      conflictStrategy: conflictStrategy ?? this.conflictStrategy,
      autoSyncOnUnlock: autoSyncOnUnlock ?? this.autoSyncOnUnlock,
      liveWatch: liveWatch ?? this.liveWatch,
      deleteOrphans: deleteOrphans ?? this.deleteOrphans,
      ignorePatterns: ignorePatterns ?? this.ignorePatterns,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'vaultInternalPath': vaultInternalPath,
    'targetEndpointUri': targetEndpointUri,
    if (targetSubPath.isNotEmpty) 'targetSubPath': targetSubPath,
    if (targetDisplayName.isNotEmpty) 'targetDisplayName': targetDisplayName,
    'direction': direction.name,
    'conflictStrategy': conflictStrategy.name,
    'autoSyncOnUnlock': autoSyncOnUnlock,
    'liveWatch': liveWatch,
    'deleteOrphans': deleteOrphans,
    'ignorePatterns': ignorePatterns,
    if (lastSyncedAt != null)
      'lastSyncedAt': lastSyncedAt!.millisecondsSinceEpoch,
  };

  /// Tolerant on purpose: a config written by a newer build (unknown enum
  /// value, extra keys) still loads, falling back to the safe defaults
  /// (`twoWay`, `renameConflict`) rather than dropping the whole rule.
  factory SyncRule.fromJson(Map<String, dynamic> json) {
    final patterns = json['ignorePatterns'];
    final lastSynced = json['lastSyncedAt'];
    return SyncRule(
      id: json['id'] as String,
      vaultInternalPath: json['vaultInternalPath'] as String? ?? '',
      targetEndpointUri: json['targetEndpointUri'] as String? ?? '',
      targetSubPath: json['targetSubPath'] as String? ?? '',
      targetDisplayName: json['targetDisplayName'] as String? ?? '',
      direction: _enumByName(
        SyncDirection.values,
        json['direction'],
        SyncDirection.twoWay,
      ),
      conflictStrategy: _enumByName(
        ConflictStrategy.values,
        json['conflictStrategy'],
        ConflictStrategy.renameConflict,
      ),
      autoSyncOnUnlock: json['autoSyncOnUnlock'] as bool? ?? true,
      liveWatch: json['liveWatch'] as bool? ?? false,
      deleteOrphans: json['deleteOrphans'] as bool? ?? false,
      ignorePatterns: patterns is List
          ? patterns.whereType<String>().toList()
          : defaultIgnorePatterns,
      lastSyncedAt: lastSynced is int
          ? DateTime.fromMillisecondsSinceEpoch(lastSynced)
          : null,
    );
  }
}

/// Contents of `/.vaultexplorer/sync_config.json`.
@immutable
class SyncConfig {
  static const int currentVersion = 1;

  /// Random id generated the first time a vault gets a config. It is the
  /// vault's stable identity for device-local bindings: a vault's mount
  /// `volId` changes every unlock and its URI changes if the file moves.
  final String vaultSyncId;
  final List<SyncRule> rules;

  const SyncConfig({required this.vaultSyncId, this.rules = const []});

  SyncConfig copyWith({List<SyncRule>? rules}) =>
      SyncConfig(vaultSyncId: vaultSyncId, rules: rules ?? this.rules);

  Map<String, dynamic> toJson() => {
    'version': currentVersion,
    'vaultSyncId': vaultSyncId,
    'rules': rules.map((r) => r.toJson()).toList(),
  };

  /// Throws [FormatException] if [json] has no usable `vaultSyncId`.
  factory SyncConfig.fromJson(Map<String, dynamic> json) {
    final id = json['vaultSyncId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('sync_config.json: missing vaultSyncId');
    }
    final rawRules = json['rules'];
    final rules = <SyncRule>[];
    if (rawRules is List) {
      for (final r in rawRules) {
        if (r is Map<String, dynamic>) {
          try {
            rules.add(SyncRule.fromJson(r));
          } catch (_) {
            // One unreadable rule must not take the others down with it.
          }
        }
      }
    }
    return SyncConfig(vaultSyncId: id, rules: rules);
  }
}
