import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/sync/data/config/sync_config_store.dart';
import 'package:vaultexplorer/features/sync/data/ledger/sync_ledger_repository.dart';
import 'package:vaultexplorer/features/sync/domain/endpoints/container_sync_endpoint.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_plan.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/sync_cancellation.dart';
import 'package:vaultexplorer/features/sync/domain/sync_rule_runner.dart';
import 'package:vaultexplorer/features/sync/services/sync_lock_barrier.dart';

/// What the UI (dashboard banner, notification) shows about running syncs.
@immutable
class SyncStatus {
  final bool running;
  final String targetLabel;
  final int doneActions;
  final int totalActions;
  final int failedActions;

  const SyncStatus({
    this.running = false,
    this.targetLabel = '',
    this.doneActions = 0,
    this.totalActions = 0,
    this.failedActions = 0,
  });
}

class _VaultSession {
  final MountedContainer vault;
  final SyncCancellationToken token = SyncCancellationToken();
  Future<void>? running;

  /// The vault has been locked; the session only lingers until its
  /// (cancelled) run has finished winding down.
  bool locked = false;

  /// Uris of *other vaults* some rule targets that weren't unlocked yet.
  final Set<String> waitingOnTargets = {};

  _VaultSession(this.vault);
}

class _ResolvedTarget {
  final MountedContainer container;
  final String displayName;

  /// Stable description of where this target really is; part of the
  /// ledger key, so a rule pointed at a different folder starts from a
  /// clean baseline instead of inheriting the old one.
  final String identity;

  const _ResolvedTarget(this.container, this.displayName, this.identity);
}

/// Runs each unlocked vault's auto-sync rules in the background and makes
/// sure a lock never tears one down mid-write.
///
/// * **Unlock** ([onVaultUnlocked]): loads `/.vaultexplorer/sync_config.json`
///   from the vault and runs every rule with `autoSyncOnUnlock` -- without
///   blocking the unlock. No extra isolate: the heavy work (listing,
///   copying, decrypting, hashing) already runs natively behind async
///   platform-channel calls, so the UI isolate is never blocked on it, and
///   the Dart-side diff is a pass of small comparisons over the file list.
///   A background isolate would need its own channel binding and gain
///   nothing.
/// * **Lock**: `VaultLifecycleApi.lockContainer` calls [SyncLockBarrier],
///   which lands in [_cancelAndWait]: cancel the token, wait for the run to
///   clean up its temp files and flush the ledger, then let the unmount
///   proceed.
/// * **Panic / force-lock**: cannot wait. Tokens are cancelled at once and
///   nothing further is written.
///
/// Live watching (continuous sync while mounted) is a separate service and
/// not part of this class.
class SyncCoordinatorService {
  static const String _tag = 'SyncCoordinator';

  /// How long a lock waits for a sync to wind down. A lock must never hang
  /// on a stuck transfer; leftovers are repaired at the next unlock.
  static const Duration lockWaitLimit = Duration(seconds: 20);

  final VaultFileIoApi _io;
  final VaultHashApi _hashApi;
  final VaultEngineEvents _events;
  final SyncLockBarrier _barrier;
  final SyncConfigStore _configStore;
  final SyncTargetBindingStore _bindings;
  final SyncRuleRunner _runner;

  final Map<String, _VaultSession> _sessions = {};
  final Map<String, MountedContainer> _unlocked = {};

  /// Progress of the rule currently running (idle when nothing is).
  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());

  SyncCoordinatorService({
    required VaultFileIoApi fileIo,
    required VaultHashApi hashApi,
    required VaultEngineEvents events,
    required SyncLockBarrier barrier,
    required SyncTargetBindingStore bindings,
    SyncRuleRunner? runner,
  }) : _io = fileIo,
       _hashApi = hashApi,
       _events = events,
       _barrier = barrier,
       _configStore = SyncConfigStore(fileIo),
       _bindings = bindings,
       _runner = runner ?? SyncRuleRunner() {
    _events.addContainerLockedListener(_onContainerLocked);
    _events.addPanicSessionPurgedListener(_onPanic);
  }

  void dispose() {
    _events.removeContainerLockedListener(_onContainerLocked);
    _events.removePanicSessionPurgedListener(_onPanic);
    _onPanic();
    status.dispose();
  }

  // ── lifecycle hooks ──────────────────────────────────────────────────

  /// Call when a vault has just been unlocked. Returns immediately; the
  /// sync runs in the background.
  Future<void> onVaultUnlocked(MountedContainer vault) async {
    // Device-storage / SAF pseudo-containers hold no config.
    if (vault.isLocalStorage) return;

    _unlocked[vault.uri] = vault;

    if (!vault.readOnly) {
      final previous = _sessions[vault.uri];
      if (previous == null || previous.locked) {
        final session = _VaultSession(vault);
        _sessions[vault.uri] = session;
        _barrier.register(vault.uri, () => _cancelAndWait(session));
        // If the previous mount of this same vault is still winding down,
        // start only after it: its calls are addressed by container path,
        // so they could otherwise land in this new mount.
        session.running = _runAutoSync(session, after: previous?.running);
      }
    } else {
      VeLog.d(_tag, 'vault is read-only; auto-sync skipped (ledger can\'t be saved)');
    }

    // Another vault's rules may have been waiting for this one to unlock.
    for (final other in _sessions.values) {
      if (other.locked || other.running != null) continue;
      if (other.waitingOnTargets.remove(vault.uri)) {
        other.running = _runAutoSync(other);
      }
    }
  }

  void _onContainerLocked(int volId) {
    _unlocked.removeWhere((_, c) => c.volId == volId);
    for (final entry in _sessions.entries.toList()) {
      final session = entry.value;
      if (session.vault.volId != volId || session.locked) continue;
      session.locked = true;
      session.token.cancel();
      _barrier.unregister(entry.key);
      final running = session.running;
      if (running == null) {
        _sessions.remove(entry.key);
      } else {
        unawaited(
          running.whenComplete(() {
            if (identical(_sessions[entry.key], session)) {
              _sessions.remove(entry.key);
            }
          }),
        );
      }
    }
  }

  void _onPanic() {
    for (final session in _sessions.values) {
      session.locked = true;
      session.token.cancel();
    }
    for (final uri in _sessions.keys) {
      _barrier.unregister(uri);
    }
    _sessions.clear();
    _unlocked.clear();
    status.value = const SyncStatus();
  }

  Future<void> _cancelAndWait(_VaultSession session) async {
    session.token.cancel();
    final running = session.running;
    if (running == null) return;
    try {
      await running.timeout(lockWaitLimit);
    } catch (_) {
      VeLog.w(_tag, 'sync did not stop within ${lockWaitLimit.inSeconds}s; locking anyway', 'timeout');
    }
  }

  // ── a session's run ──────────────────────────────────────────────────

  Future<void> _runAutoSync(_VaultSession session, {Future<void>? after}) async {
    final vault = session.vault;
    final token = session.token;
    final ledger = VaultFileSyncLedger(_io, vault);

    try {
      if (after != null) {
        try {
          await after;
        } catch (_) {}
      }
      if (token.isCancelled) return;

      SyncConfig? config;
      try {
        config = await _configStore.load(vault);
      } catch (e) {
        // Unreadable config: leave it alone, sync nothing.
        VeLog.w(_tag, 'sync config unreadable', e);
        return;
      }
      if (config == null) return;
      final rules = config.rules.where((r) => r.autoSyncOnUnlock).toList();
      if (rules.isEmpty || token.isCancelled) return;

      await ledger.open();
      final knownRuleIds = config.rules.map((r) => r.id).toSet();
      for (final key in ledger.ruleKeys) {
        if (!knownRuleIds.contains(key.split('#').first)) ledger.clearRule(key);
      }

      final stamps = <String, DateTime>{};
      for (final rule in rules) {
        if (token.isCancelled) break;
        final report = await _runRule(session, config, rule, ledger);
        if (report == null) continue;
        await ledger.flush();
        if (report.completedCleanly) stamps[rule.id] = DateTime.now();
      }
      if (stamps.isNotEmpty && !token.isCancelled) {
        await _configStore.updateLastSynced(vault, stamps);
      }
    } catch (e) {
      VeLog.w(_tag, 'auto-sync failed', e);
    } finally {
      // Commit whatever the run learned, also after a cancellation.
      try {
        await ledger.flush();
      } catch (_) {}
      session.running = null;
      status.value = const SyncStatus();

      // A target vault may have unlocked while this run was in flight.
      final ready = session.waitingOnTargets.where(_unlocked.containsKey).toList();
      if (ready.isNotEmpty && !session.locked && !token.isCancelled) {
        session.waitingOnTargets.removeAll(ready);
        session.running = _runAutoSync(session);
      }
    }
  }

  Future<SyncRunReport?> _runRule(
    _VaultSession session,
    SyncConfig config,
    SyncRule rule,
    SyncLedgerRepository ledger,
  ) async {
    final vault = session.vault;
    final target = await _resolveTarget(session, config.vaultSyncId, rule);
    if (target == null) return null;

    if (target.container.uri == vault.uri && _pathsOverlap(rule.vaultRelativePath, rule.targetRelativePath)) {
      VeLog.w(_tag, 'rule skipped: source and target folders overlap', 'overlap');
      return null;
    }

    // A two-way / target-to-vault rule may be the first thing ever to
    // create its vault folder.
    if (rule.direction != SyncDirection.vaultToTarget && rule.vaultRelativePath.isNotEmpty) {
      await _ensureVaultFolder(vault, rule.vaultRelativePath);
    }

    final vaultEndpoint = ContainerSyncEndpoint(
      io: _io,
      hashApi: _hashApi,
      container: vault,
      rootPath: rule.vaultRelativePath,
      label: vault.displayName,
    );
    final targetEndpoint = ContainerSyncEndpoint(
      io: _io,
      hashApi: _hashApi,
      container: target.container,
      rootPath: rule.targetRelativePath,
      label: target.displayName,
    );

    final ledgerKey =
        '${rule.id}#${_fingerprint('${rule.vaultRelativePath}|${target.identity}|${rule.targetRelativePath}')}';

    status.value = SyncStatus(running: true, targetLabel: target.displayName);
    return _runner.run(
      rule: rule,
      vault: vaultEndpoint,
      target: targetEndpoint,
      ledger: ledger,
      token: session.token,
      ledgerKey: ledgerKey,
      onProgress: (p) {
        status.value = SyncStatus(
          running: true,
          targetLabel: target.displayName,
          doneActions: p.doneActions,
          totalActions: p.totalActions,
          failedActions: p.failedActions,
        );
      },
    );
  }

  // ── target resolution ────────────────────────────────────────────────

  Future<_ResolvedTarget?> _resolveTarget(
    _VaultSession session,
    String vaultSyncId,
    SyncRule rule,
  ) async {
    final binding = await _bindings.read(vaultSyncId, rule.id);
    final uri = binding?.uri ?? rule.targetEndpointUri;
    if (uri.isEmpty) return null; // not linked to a folder on this device

    final label = [
      binding?.displayName ?? '',
      rule.targetDisplayName,
    ].firstWhere((s) => s.isNotEmpty, orElse: () => 'Target');

    // Another vault that is unlocked right now.
    final mountedVault = _unlocked[uri];
    if (mountedVault != null) {
      return _ResolvedTarget(mountedVault, label, 'vault:$uri');
    }

    if (uri.startsWith('content://')) {
      // SAF tree. Whether the grant is still valid can't be probed here;
      // a dead grant lists as unreadable and the run skips everything.
      return _ResolvedTarget(_folderContainer(rule, uri, label), label, uri);
    }

    if (await Directory(uri).exists()) {
      return _ResolvedTarget(_folderContainer(rule, uri, label), label, uri);
    }

    // Not a folder we can see: most likely a vault that isn't unlocked
    // yet, or a drive that isn't attached. Try again when a vault unlocks.
    session.waitingOnTargets.add(uri);
    VeLog.d(_tag, 'rule target unavailable; will retry when a vault unlocks');
    return null;
  }

  MountedContainer _folderContainer(SyncRule rule, String uri, String label) =>
      buildExternalStorageContainer(
        rootPath: uri,
        displayName: label,
        // Any negative id marks "not a vault"; this range stays clear of
        // the ids ExternalStorageLocationsNotifier hands out (-100, -101, ...).
        volId: -1000000 - (rule.id.hashCode & 0xFFFFF),
      );

  Future<void> _ensureVaultFolder(MountedContainer vault, String relPath) async {
    try {
      final existing = await _io.listDirectory(vault, relPath);
      // Some engines answer "no such folder" with an empty list rather
      // than null, so only a non-empty listing proves it exists.
      if (existing != null && existing.isNotEmpty) return;
    } catch (_) {
      // fall through and create it
    }
    var current = '';
    for (final segment in relPath.split('/').where((s) => s.isNotEmpty)) {
      current = current.isEmpty ? segment : '$current/$segment';
      try {
        // Fails harmlessly for folders that already exist.
        await _io.createDirectory(vault, current);
      } catch (_) {}
    }
  }

  static bool _pathsOverlap(String a, String b) {
    if (a.isEmpty || b.isEmpty || a == b) return true;
    return a.startsWith('$b/') || b.startsWith('$a/');
  }

  /// FNV-1a: a short, stable, non-secret fingerprint.
  static String _fingerprint(String input) {
    var h = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
