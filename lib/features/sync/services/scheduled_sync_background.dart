import 'dart:io';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
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
  ScheduledSyncBackgroundRunner({
    required this._io,
    required this._hash,
    this._platform = const MethodChannel('com.aeidolon.vaultexplorer/engine'),
  });

  final VaultFileIoApi _io;
  final VaultHashApi _hash;
  final MethodChannel _platform;
  SyncCancellationToken? _activeToken;
  int? _lastProgressOperationId;
  DateTime? _lastProgressPublishedAt;

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
      final targetStoragePath = args['targetRawPath'] as String? ?? targetUri;
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
    } catch (error) {
      return {
        'success': false,
        'reason': 'Scheduled sync failed (${error.runtimeType})',
      };
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

  /// Runs every rule configured to sync on unlock for a vault that the
  /// automation receiver has already mounted.
  Future<Map<String, Object?>> runAutoSyncOnUnlock(
    Map<Object?, Object?> args,
  ) async {
    if (_activeToken != null) {
      return const {'success': false, 'reason': 'A sync is already active'};
    }
    final vaultUri = args['vaultUri'] as String?;
    final volId = args['vaultVolId'] as int?;
    if (vaultUri == null || volId == null) {
      return const {'success': false, 'reason': 'Vault details are incomplete'};
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
    final progressOpId = args['progressOpId'] as int?;
    final token = SyncCancellationToken();
    _activeToken = token;
    VaultFileSyncLedger? ledger;
    try {
      final config = await SyncConfigStore(_io).load(vault);
      final rules =
          config?.rules
              .where((rule) => rule.autoSyncOnUnlock || rule.liveWatch)
              .toList() ??
          const <SyncRule>[];
      if (rules.isEmpty) return const {'success': true, 'syncedRules': 0};
      if (config == null) {
        return const {
          'success': false,
          'reason': 'The sync configuration is unavailable',
        };
      }

      ledger = VaultFileSyncLedger(_io, vault);
      await ledger.open();
      final stamps = <String, DateTime>{};
      var failedRules = 0;
      var unavailableRules = 0;

      for (var index = 0; index < rules.length; index++) {
        if (token.isCancelled) break;
        final rule = rules[index];
        final binding = await _platform.invokeMapMethod<String, Object?>(
          'getSyncTargetBinding',
          {'vaultUri': vaultUri, 'ruleId': rule.id},
        );
        final targetUri =
            (binding?['uri'] as String?) ?? rule.targetEndpointUri;
        final targetSubPath = normalizeSyncPath(
          (binding?['subPath'] as String?) ?? rule.targetRelativePath,
        );
        final targetName = [
          (binding?['displayName'] as String?) ?? '',
          rule.targetDisplayName,
        ].firstWhere((name) => name.isNotEmpty, orElse: () => 'Target');

        if (targetUri.isEmpty) {
          unavailableRules++;
          _publishProgress(
            progressOpId,
            '${index + 1}/${rules.length} · Target unavailable',
            null,
          );
          continue;
        }

        final mountedTargetId = await _platform.invokeMethod<int>(
          'getMountedVolumeId',
          {'vaultUri': targetUri},
        );
        final MountedContainer target;
        final targetIdentity = mountedTargetId == null
            ? targetUri
            : 'vault:$targetUri';
        if (mountedTargetId != null) {
          target = MountedContainer(
            uri: targetUri,
            displayName: targetName,
            volId: mountedTargetId,
            rootFiles: const [],
            mountedAt: DateTime.now(),
            totalSpace: 0,
            freeSpace: 0,
            containerFormat: 'unknown',
          );
        } else if (targetUri.startsWith('content://') ||
            await Directory(targetUri).exists()) {
          target = buildExternalStorageContainer(
            rootPath: targetUri,
            displayName: targetName,
            volId: -1000000 - (rule.id.hashCode & 0xFFFFF),
          );
          if (await findFolderVaultAlong(_io, target, targetSubPath) != null) {
            unavailableRules++;
            _publishProgress(
              progressOpId,
              '${index + 1}/${rules.length} · Target vault is locked',
              null,
            );
            continue;
          }
        } else {
          unavailableRules++;
          _publishProgress(
            progressOpId,
            '${index + 1}/${rules.length} · Target unavailable',
            null,
          );
          continue;
        }

        final effectiveRule = rule.copyWith(
          targetEndpointUri: targetUri,
          targetSubPath: targetSubPath,
          targetDisplayName: targetName,
        );
        if (effectiveRule.direction != SyncDirection.vaultToTarget &&
            !await _ensureVaultFolder(vault, effectiveRule.vaultRelativePath)) {
          failedRules++;
          continue;
        }

        _publishProgress(
          progressOpId,
          '${index + 1}/${rules.length} · Preparing',
          null,
        );
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
          label: targetName,
          failClosedListings: true,
        );
        final ledgerKey = syncLedgerKeyFor(
          effectiveRule,
          targetIdentity: targetIdentity,
          targetSubPath: targetSubPath,
        );
        final targetRawPath = await _platform.invokeMethod<String>(
          'getRawPath',
          {'uri': targetUri},
        );
        final vaultCiphertextPath =
            target.isLocalStorage && !target.isSafStorage
            ? SyncIgnoreMatcher.vaultCiphertextPathRelativeToTarget(
                vaultUri: args['vaultRawPath'] as String? ?? vaultUri,
                targetUri: targetRawPath ?? targetUri,
                targetSubPath: targetSubPath,
              )
            : null;

        try {
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
            onProgress: (progress) {
              final itemProgress = progress.totalActions > 0
                  ? (progress.doneActions * 1000 ~/ progress.totalActions)
                        .clamp(0, 1000)
                  : null;
              _publishProgress(
                progressOpId,
                '${index + 1}/${rules.length} · ${progress.doneActions}/${progress.totalActions} items',
                itemProgress,
              );
            },
          );
          final ledgerSaved = await ledger.flush();
          if (!ledgerSaved || !report.completedCleanly) {
            failedRules++;
          } else if (report.didWork || rule.lastSyncedAt == null) {
            stamps[rule.id] = DateTime.now();
          }
        } catch (_) {
          failedRules++;
        }
      }

      if (stamps.isNotEmpty) {
        await SyncConfigStore(_io).updateLastSynced(vault, stamps);
      }
      await ledger.flush();
      final succeeded =
          failedRules == 0 && unavailableRules == 0 && !token.isCancelled;
      return {
        'success': succeeded,
        'syncedRules': rules.length - failedRules - unavailableRules,
        'failedRules': failedRules,
        'unavailableRules': unavailableRules,
        if (!succeeded) 'reason': 'Some unlock sync rules did not complete',
      };
    } catch (error) {
      return {
        'success': false,
        'reason': 'Unlock sync failed (${error.runtimeType})',
      };
    } finally {
      try {
        await ledger?.close();
      } catch (_) {
        // The runner reports its result before this final flush is attempted.
      }
      if (identical(_activeToken, token)) _activeToken = null;
    }
  }

  void _publishProgress(int? opId, String text, int? progress) {
    if (opId == null) return;
    final now = DateTime.now();
    final last = _lastProgressPublishedAt;
    if (_lastProgressOperationId == opId &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 200)) {
      return;
    }
    _lastProgressOperationId = opId;
    _lastProgressPublishedAt = now;
    _platform
        .invokeMethod<void>('updateAutomationSyncProgress', {
          'opId': opId,
          'text': text,
          'progress': progress,
          'max': 1000,
          'indeterminate': progress == null,
        })
        .catchError((Object _) {});
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
