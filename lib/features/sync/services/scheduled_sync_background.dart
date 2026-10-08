import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_channel.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/sync/data/config/sync_config_store.dart';
import 'package:vaultexplorer/features/sync/data/ledger/sync_ledger_repository.dart';
import 'package:vaultexplorer/features/sync/domain/endpoints/container_sync_endpoint.dart';
import 'package:vaultexplorer/features/sync/domain/folder_vault_detector.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/sync_cancellation.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ledger_key.dart';
import 'package:vaultexplorer/features/sync/domain/sync_rule_runner.dart';

/// Headless runner called by ScheduledVaultSyncWorker's FlutterEngine.
class ScheduledSyncBackgroundRunner {
  final VaultFileIoApi _io = VaultFileIoApi(kVaultEngineChannel);
  final VaultHashApi _hash = VaultHashApi(kVaultEngineChannel);
  SyncCancellationToken? _activeToken;

  void cancel() => _activeToken?.cancel();

  Future<Map<String, Object?>> run(Map<Object?, Object?> args) async {
    if (_activeToken != null) {
      return const {
        'success': false,
        'reason': 'A scheduled sync is already active',
      };
    }
    final vaultUri = args['vaultUri'] as String?;
    final targetUri = args['targetUri'] as String?;
    final ruleId = args['ruleId'] as String?;
    final volId = args['vaultVolId'] as int?;
    if (vaultUri == null ||
        targetUri == null ||
        ruleId == null ||
        volId == null) {
      return const {
        'success': false,
        'reason': 'Scheduled sync details are incomplete',
      };
    }

    final vault = MountedContainer(
      uri: vaultUri,
      displayName: args['vaultName'] as String? ?? 'Vault',
      volId: volId,
      rootFiles: const [],
      mountedAt: DateTime.now(),
      totalSpace: 0,
      freeSpace: 0,
      containerFormat: 'unknown',
    );
    final targetSubPath = normalizeSyncPath(
      args['targetSubPath'] as String? ?? '',
    );
    final target = buildExternalStorageContainer(
      rootPath: targetUri,
      displayName: args['targetName'] as String? ?? 'Folder',
      volId: -1000000 - (ruleId.hashCode & 0xFFFFF),
    );

    VaultFileSyncLedger? ledger;
    final token = SyncCancellationToken();
    _activeToken = token;
    try {
      final config = await SyncConfigStore(_io).load(vault);
      final rule = config?.rules.where((rule) => rule.id == ruleId).firstOrNull;
      if (config == null || rule == null) {
        return const {
          'success': false,
          'reason': 'The sync rule is no longer available',
        };
      }
      final effectiveRule = rule.copyWith(
        targetEndpointUri: targetUri,
        targetSubPath: targetSubPath,
        targetDisplayName:
            args['targetName'] as String? ?? rule.targetDisplayName,
      );

      // Never use another folder vault's ciphertext as a plain sync target.
      if (await findFolderVaultAlong(_io, target, targetSubPath) != null) {
        return const {
          'success': false,
          'reason': 'The target is an encrypted vault folder',
        };
      }
      if (effectiveRule.direction != SyncDirection.vaultToTarget &&
          !await _ensureVaultFolder(vault, effectiveRule.vaultRelativePath)) {
        return const {
          'success': false,
          'reason': 'Could not prepare the vault sync folder',
        };
      }

      ledger = VaultFileSyncLedger(_io, vault);
      await ledger.open();
      final vaultEndpoint = ContainerSyncEndpoint(
        io: _io,
        hashApi: _hash,
        container: vault,
        rootPath: effectiveRule.vaultRelativePath,
        label: vault.displayName,
      );
      final targetEndpoint = ContainerSyncEndpoint(
        io: _io,
        hashApi: _hash,
        container: target,
        rootPath: targetSubPath,
        label: target.displayName,
        failClosedListings: true,
      );
      final ledgerKey = syncLedgerKeyFor(
        effectiveRule,
        targetIdentity: targetUri,
        targetSubPath: targetSubPath,
      );
      final targetStoragePath =
          args['targetRawPath'] as String? ?? targetUri;
      final vaultStoragePath = args['vaultRawPath'] as String? ?? vaultUri;
      final vaultCiphertextPath = target.isLocalStorage
          ? SyncIgnoreMatcher.vaultCiphertextPathRelativeToTarget(
              vaultUri: vaultStoragePath,
              targetUri: targetStoragePath,
              targetSubPath: targetSubPath,
            )
          : null;

      final report = await SyncRuleRunner().run(
        rule: effectiveRule,
        vault: vaultEndpoint,
        target: targetEndpoint,
        ledger: ledger,
        token: token,
        ledgerKey: ledgerKey,
        failOnIncompleteScan: true,
        abortOnFirstFailure: true,
        protectedPaths: [?vaultCiphertextPath],
      );
      final ledgerSaved = await ledger.flush();
      if (!ledgerSaved || !report.completedCleanly) {
        return const {
          'success': false,
          'reason': 'The scheduled sync did not complete cleanly',
        };
      }
      if (report.didWork || rule.lastSyncedAt == null) {
        await SyncConfigStore(
          _io,
        ).updateLastSynced(vault, {rule.id: DateTime.now()});
      }
      return const {'success': true};
    } catch (_) {
      return const {'success': false, 'reason': 'The scheduled sync failed'};
    } finally {
      try {
        await ledger?.close();
      } catch (_) {
        // The worker reports failure based on the run/flush; close is a final best-effort.
      }
      if (identical(_activeToken, token)) {
        _activeToken = null;
      }
    }
  }

  Future<bool> _ensureVaultFolder(
    MountedContainer vault,
    String relativePath,
  ) async {
    if (relativePath.isEmpty) return true;
    var current = '';
    for (final segment in normalizeSyncPath(relativePath).split('/')) {
      if (segment.isEmpty) continue;
      current = current.isEmpty ? segment : '$current/$segment';
      if (await _io.canListDirectory(vault, current)) continue;
      try {
        final created = await _io.createDirectory(vault, current);
        if (!created && !await _io.canListDirectory(vault, current)) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    return true;
  }
}
