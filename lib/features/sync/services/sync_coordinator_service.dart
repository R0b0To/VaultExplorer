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
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';
import 'package:vaultexplorer/features/sync/domain/sync_rule_runner.dart';
import 'package:vaultexplorer/features/sync/domain/sync_rule_validation.dart';
import 'package:vaultexplorer/features/sync/domain/sync_run_scheduler.dart';
import 'package:vaultexplorer/features/sync/services/live_watch_service.dart';
import 'package:vaultexplorer/features/sync/services/sync_lock_barrier.dart';
import 'package:vaultexplorer/features/sync/services/sync_notification_bridge.dart';
import 'package:vaultexplorer/features/sync/services/sync_status.dart';

/// One unlocked vault's sync state. All of a vault's runs go through its
/// [scheduler], one at a time, because they share [ledger].
class _VaultSession {
  final MountedContainer vault;
  final SyncCancellationToken token = SyncCancellationToken();
  final VaultFileSyncLedger ledger;
  late final SyncRunScheduler scheduler;

  SyncConfig? config;
  bool ledgerOpen = false;

  /// The vault has been locked; the session only lingers until its
  /// (cancelled) work has wound down.
  bool locked = false;

  /// Config load + first runs being queued.
  Future<void>? starting;

  /// Rules that couldn't run because their target is another vault that
  /// wasn't unlocked yet: target uri -> rule ids.
  final Map<String, Set<String>> waitingOnTargets = {};

  /// Latest report per rule, for the banner and the rule editor.
  final Map<String, SyncRunReport> lastReports = {};

  _VaultSession(this.vault, VaultFileIoApi io)
    : ledger = VaultFileSyncLedger(io, vault);
}

class _ResolvedTarget {
  final MountedContainer container;
  final String displayName;

  /// The folder within [container] that is synced.
  final String subPath;

  /// Stable description of where this target really is; part of the
  /// ledger key, so a rule pointed at a different folder starts from a
  /// clean baseline instead of inheriting the old one.
  final String identity;

  const _ResolvedTarget(
    this.container,
    this.displayName,
    this.subPath,
    this.identity,
  );
}

/// Runs each unlocked vault's sync rules in the background and makes sure a
/// lock never tears one down mid-write.
///
/// * **Unlock** ([onVaultUnlocked]): loads `/.vaultexplorer/sync_config.json`
///   and queues every rule with `autoSyncOnUnlock` or `liveWatch` -- without
///   blocking the unlock. No extra isolate: the heavy work (listing,
///   copying, decrypting, hashing) already runs natively behind async
///   platform-channel calls, so the UI isolate is never blocked on it, and
///   the Dart-side diff is a pass of small comparisons over the file list.
///   A background isolate would need its own channel binding and gain
///   nothing.
/// * **While unlocked**: rules with `liveWatch` get a watcher
///   ([LiveWatchService]) that queues a run when something changes, and
///   the UI can queue one ([syncNow]) or tell the coordinator the config
///   changed ([reloadConfig]).
/// * **Lock**: `VaultLifecycleApi.lockContainer` calls [SyncLockBarrier],
///   which lands in [_cancelAndWait]: cancel the token, wait for the run to
///   clean up its temp files and flush the ledger, then let the unmount
///   proceed.
/// * **Panic / force-lock**: cannot wait. Everything is cancelled at once
///   and nothing further is written.
class SyncCoordinatorService {
  static const String _tag = 'SyncCoordinator';

  /// How long a lock waits for a sync to wind down. A lock must never hang
  /// on a stuck transfer; leftovers are repaired at the next unlock.
  static const Duration lockWaitLimit = Duration(seconds: 20);

  /// Fallback poll for document-provider folders: listing them can take
  /// seconds (cloud providers), so they are checked less often.
  static const Duration _safPoll = Duration(minutes: 5);

  final VaultFileIoApi _io;
  final VaultHashApi _hashApi;
  final VaultEngineEvents _events;
  final SyncLockBarrier _barrier;
  final SyncConfigStore _configStore;
  final SyncTargetBindingStore _bindings;
  final SyncRuleRunner _runner;
  final LiveWatchService _liveWatch;
  final SyncNotificationBridge _notifier;

  final Map<String, _VaultSession> _sessions = {};
  final Map<String, MountedContainer> _unlocked = {};
  final Set<String> _explicitSyncRules = <String>{};
  Timer? _completedLingerTimer;
  int _runningCount = 0;

  /// Progress of the run currently transferring files (idle otherwise).
  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());

  SyncCoordinatorService({
    required VaultFileIoApi fileIo,
    required VaultHashApi hashApi,
    required VaultEngineEvents events,
    required SyncLockBarrier barrier,
    required SyncTargetBindingStore bindings,
    required LiveWatchService liveWatch,
    required SyncNotificationBridge notifier,
    SyncRuleRunner? runner,
  }) : _io = fileIo,
       _hashApi = hashApi,
       _events = events,
       _barrier = barrier,
       _configStore = SyncConfigStore(fileIo),
       _bindings = bindings,
       _liveWatch = liveWatch,
       _notifier = notifier,
       _runner = runner ?? SyncRuleRunner() {
    _events.addContainerLockedListener(_onContainerLocked);
    _events.addPanicSessionPurgedListener(_onPanic);
  }

  void dispose() {
    _completedLingerTimer?.cancel();
    _events.removeContainerLockedListener(_onContainerLocked);
    _events.removePanicSessionPurgedListener(_onPanic);
    _onPanic();
    _liveWatch.dispose();
    status.dispose();
  }

  // ── entry points for the rest of the app ────────────────────────────

  /// Call when a vault has just been unlocked. Returns immediately; the
  /// sync runs in the background.
  Future<void> onVaultUnlocked(MountedContainer vault) async {
    // Device-storage / SAF pseudo-containers hold no config.
    if (vault.isLocalStorage) return;

    _unlocked[vault.uri] = vault;

    if (!vault.readOnly) {
      final previous = _sessions[vault.uri];
      if (previous == null || previous.locked) {
        final session = _VaultSession(vault, _io);
        session.scheduler = SyncRunScheduler((ruleId) => _runOne(session, ruleId));
        _sessions[vault.uri] = session;
        _barrier.register(vault.uri, () => _cancelAndWait(session));
        // If the previous mount of this same vault is still winding down,
        // start only after it: its calls are addressed by container path,
        // so they could otherwise land in this new mount.
        session.starting = _start(
          session,
          after: previous == null ? null : _quiesce(previous),
        );
      }
    } else {
      VeLog.d(_tag, 'vault is read-only; sync skipped (the ledger can\'t be saved)');
    }

    // Rules in other vaults that were waiting for this one to unlock.
    for (final other in _sessions.values.toList()) {
      if (other.locked) continue;
      final ids = other.waitingOnTargets.remove(vault.uri);
      if (ids == null) continue;
      for (final id in ids) {
        other.scheduler.request(id);
      }
    }
  }

  /// The rule editor saved (or removed) a rule in [vault]: re-read the
  /// config, restart the watchers, and drop ledger rows of removed rules.
  Future<void> reloadConfig(MountedContainer vault) async {
    final session = _sessions[vault.uri];
    if (session == null || session.locked) return;
    final config = await _loadConfig(session);
    if (session.locked || session.token.isCancelled) return;
    if (config == null) {
      session.config = null;
      _liveWatch.stop(vault.uri);
      return;
    }
    await _applyConfig(session, config, initial: false);
  }

  /// Queues a run of [ruleId] now. False when the vault has no sync session
  /// (locked, or read-only -- a read-only vault can't keep a ledger).
  bool syncNow(MountedContainer vault, String ruleId) {
    final session = _sessions[vault.uri];
    if (session == null || session.locked) return false;
    _explicitSyncRules.add(ruleId);
    session.scheduler.request(ruleId);
    return true;
  }

  /// True while [ruleId] is running or waiting for its turn.
  bool isRuleBusy(MountedContainer vault, String ruleId) =>
      _sessions[vault.uri]?.scheduler.isActive(ruleId) ?? false;

  /// The result of the latest run of [ruleId] in this session, if any.
  SyncRunReport? lastReportFor(MountedContainer vault, String ruleId) =>
      _sessions[vault.uri]?.lastReports[ruleId];

  // ── lock / panic ─────────────────────────────────────────────────────

  void _onContainerLocked(int volId) {
    _unlocked.removeWhere((_, c) => c.volId == volId);
    for (final entry in _sessions.entries.toList()) {
      final session = entry.value;
      if (session.vault.volId != volId || session.locked) continue;
      _retire(session);
      unawaited(
        _quiesce(session).whenComplete(() {
          if (identical(_sessions[entry.key], session)) {
            _sessions.remove(entry.key);
            // Another vault's run may still be showing progress.
            if (_runningCount == 0) {
              _publishIdle();
            } else {
              _refreshAttention();
            }
          }
        }),
      );
    }
  }

  void _onPanic() {
    for (final session in _sessions.values) {
      _retire(session);
    }
    _sessions.clear();
    _unlocked.clear();
    _runningCount = 0;
    status.value = const SyncStatus();
    unawaited(_notifier.clear());
  }

  /// Stops a session's work without waiting for it.
  void _retire(_VaultSession session) {
    session.locked = true;
    session.token.cancel();
    session.scheduler.close();
    _liveWatch.stop(session.vault.uri);
    _barrier.unregister(session.vault.uri);
  }

  Future<void> _cancelAndWait(_VaultSession session) async {
    session.token.cancel();
    session.scheduler.close();
    _liveWatch.stop(session.vault.uri);
    try {
      await _quiesce(session).timeout(lockWaitLimit);
    } catch (_) {
      VeLog.w(_tag, 'sync did not stop within ${lockWaitLimit.inSeconds}s; locking anyway', 'timeout');
    }
  }

  Future<void> _quiesce(_VaultSession session) async {
    try {
      await session.starting;
    } catch (e) {
      VeLog.w(_tag, 'Session start failed before quiesce; locking anyway', e);
    }
    await session.scheduler.idle;
  }

  // ── a session's life ─────────────────────────────────────────────────

  Future<void> _start(_VaultSession session, {Future<void>? after}) async {
    try {
      if (after != null) await after;
      if (session.token.isCancelled) return;
      final config = await _loadConfig(session);
      if (config == null || session.token.isCancelled) return;
      await _applyConfig(session, config, initial: true);
    } catch (e) {
      VeLog.w(_tag, 'sync start failed', e);
    }
  }

  /// Unreadable config: leave it alone and sync nothing.
  Future<SyncConfig?> _loadConfig(_VaultSession session) async {
    try {
      return await _configStore.load(session.vault);
    } catch (e) {
      VeLog.w(_tag, 'sync config unreadable', e);
      return null;
    }
  }

  Future<void> _applyConfig(
    _VaultSession session,
    SyncConfig config, {
    required bool initial,
  }) async {
    final uri = session.vault.uri;
    session.config = config;
    _liveWatch.stop(uri);
    if (config.rules.isEmpty) return;

    if (!session.ledgerOpen) {
      await session.ledger.open();
      session.ledgerOpen = true;
    }
    if (session.token.isCancelled) return;

    // Forget what belonged to rules that no longer exist.
    final known = config.rules.map((r) => r.id).toSet();
    for (final key in session.ledger.ruleKeys.toList()) {
      if (!known.contains(key.split('#').first)) session.ledger.clearRule(key);
    }
    session.lastReports.removeWhere((id, _) => !known.contains(id));

    final specs = <LiveWatchSpec>[];
    for (final rule in config.rules.where((r) => r.liveWatch)) {
      specs.add(await _watchSpec(session, config, rule));
    }
    if (session.token.isCancelled) return;
    _liveWatch.start(
      vaultUri: uri,
      specs: specs,
      requestRun: session.scheduler.request,
      wasRecentlyWrittenOnTarget: (rel) =>
          _runner.executor.wasRecentlyWritten(SyncSide.target, rel),
    );

    if (initial) {
      for (final rule in config.rules) {
        if (rule.autoSyncOnUnlock || rule.liveWatch) {
          session.scheduler.request(rule.id);
        }
      }
    }
  }

  Future<LiveWatchSpec> _watchSpec(
    _VaultSession session,
    SyncConfig config,
    SyncRule rule,
  ) async {
    final volIds = <int>{session.vault.volId};
    String? hostDirectory;
    var poll = const Duration(seconds: 60);

    final target = await _resolveTarget(session, config.vaultSyncId, rule);
    if (target != null) {
      final c = target.container;
      if (!c.isLocalStorage) {
        volIds.add(c.volId); // another unlocked vault
      } else if (c.isSafStorage) {
        poll = _safPoll;
      } else {
        final root = c.uri.endsWith('/') ? c.uri.substring(0, c.uri.length - 1) : c.uri;
        hostDirectory = target.subPath.isEmpty ? root : '$root/${target.subPath}';
      }
    }
    return LiveWatchSpec(
      ruleId: rule.id,
      ignore: SyncIgnoreMatcher(rule.ignorePatterns),
      vaultVolIds: volIds,
      hostDirectory: hostDirectory,
      pollInterval: poll,
    );
  }

  // ── one run (the scheduler calls this, one rule at a time) ───────────

  Future<void> _runOne(_VaultSession session, String ruleId) async {
    if (session.token.isCancelled || session.locked) return;
    final config = session.config;
    final rule = config?.rules.where((r) => r.id == ruleId).firstOrNull;
    if (config == null || rule == null) return;

    final watch = Stopwatch()..start();
    SyncRunReport? report;
    try {
      report = await _runRule(session, config, rule);
    } catch (e) {
      VeLog.w(_tag, 'sync run failed', e);
    } finally {
      // Commit what the run learned, also after a cancellation.
      try {
        await session.ledger.flush();
      } catch (e) {
        VeLog.e(_tag, 'Ledger flush failed after sync run', e);
      }
    }
    watch.stop();
    _liveWatch.noteRunFinished(session.vault.uri, ruleId, watch.elapsed);
    if (report == null) return;

    session.lastReports[ruleId] = report;
    _refreshAttention();

    // Stamp the config only when something changed: live watching runs
    // often, and idle runs shouldn't rewrite it each time.
    if (report.completedCleanly && (report.didWork || rule.lastSyncedAt == null)) {
      final now = DateTime.now();
      await _configStore.updateLastSynced(session.vault, {ruleId: now});
      // Build on the session's *current* config: the editor may have
      // reloaded it while this run was in progress.
      final current = session.config ?? config;
      session.config = current.copyWith(
        rules: [
          for (final r in current.rules) r.id == ruleId ? r.copyWith(lastSyncedAt: now) : r,
        ],
      );
    }
  }

  Future<SyncRunReport?> _runRule(
    _VaultSession session,
    SyncConfig config,
    SyncRule rule,
  ) async {
    final vault = session.vault;
    final target = await _resolveTarget(session, config.vaultSyncId, rule);
    if (target == null) return null;

    if (target.container.uri == vault.uri &&
        syncPathsOverlap(rule.vaultRelativePath, target.subPath)) {
      VeLog.w(_tag, 'rule skipped: source and target folders overlap', 'overlap');
      return null;
    }

    // A two-way / target-to-vault rule may be the first thing ever to
    // create its vault folder.
    if (rule.direction != SyncDirection.vaultToTarget &&
        rule.vaultRelativePath.isNotEmpty) {
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
      rootPath: target.subPath,
      label: target.displayName,
    );

    final ledgerKey =
        '${rule.id}#${_fingerprint('${rule.vaultRelativePath}|${target.identity}|${target.subPath}')}';

    final isExplicit = _explicitSyncRules.remove(rule.id);

    var announced = false;
    if (isExplicit) {
      announced = true;
      _runningCount++;
      _publish(
        SyncStatus(
          running: true,
          targetLabel: target.displayName,
          doneActions: 0,
          totalActions: 0,
          failedActions: 0,
          attention: _attentionCount,
        ),
      );
    }

    void onProgress(SyncProgress p) {
      if (p.totalActions == 0 && !isExplicit) return; // scanning, or nothing to do: stay quiet
      if (!announced) {
        announced = true;
        _runningCount++;
      }
      _publish(
        SyncStatus(
          running: true,
          targetLabel: target.displayName,
          doneActions: p.doneActions,
          totalActions: p.totalActions,
          failedActions: p.failedActions,
          attention: _attentionCount,
        ),
      );
    }

    SyncRunReport? report;
    try {
      report = await _runner.run(
        rule: rule,
        vault: vaultEndpoint,
        target: targetEndpoint,
        ledger: session.ledger,
        token: session.token,
        ledgerKey: ledgerKey,
        onProgress: onProgress,
      );
      return report;
    } finally {
      if (announced) {
        _runningCount--;
        if (_runningCount <= 0) {
          _runningCount = 0;
          final rep = report;
          if (rep != null && (isExplicit || rep.didWork)) {
            _publishCompleted(rep, target.displayName);
          } else {
            _publishIdle();
          }
        }
      }
    }
  }

  // ── status ───────────────────────────────────────────────────────────

  int get _attentionCount => _sessions.values
      .expand((s) => s.lastReports.values)
      .where((r) => r.needsAttention)
      .length;

  void _publish(SyncStatus next) {
    _completedLingerTimer?.cancel();
    status.value = next;
    unawaited(_notifier.update(next));
  }

  void _publishCompleted(SyncRunReport report, String targetLabel) {
    status.value = SyncStatus(
      running: false,
      attention: _attentionCount,
      lastCompletedReport: report,
      lastCompletedTargetLabel: targetLabel,
    );
    unawaited(_notifier.clear());
    _completedLingerTimer?.cancel();
    _completedLingerTimer = Timer(const Duration(seconds: 4), () {
      if (!status.value.running) {
        status.value = SyncStatus(attention: _attentionCount);
        unawaited(_notifier.clear());
      }
    });
  }

  void _publishIdle() {
    _completedLingerTimer?.cancel();
    status.value = SyncStatus(attention: _attentionCount);
    unawaited(_notifier.clear());
  }

  /// Updates only the attention count, leaving progress fields alone.
  void _refreshAttention() {
    status.value = status.value.copyWith(attention: _attentionCount);
  }

  // ── target resolution ────────────────────────────────────────────────

  Future<_ResolvedTarget?> _resolveTarget(
    _VaultSession session,
    String vaultSyncId,
    SyncRule rule,
  ) async {
    // The choice made on THIS device wins over the config's portable default.
    final binding = await _bindings.read(vaultSyncId, rule.id);
    final uri = binding?.uri ?? rule.targetEndpointUri;
    if (uri.isEmpty) return null; // not linked to a folder on this device
    final subPath = binding != null
        ? normalizeSyncPath(binding.subPath)
        : rule.targetRelativePath;

    final label = [
      binding?.displayName ?? '',
      rule.targetDisplayName,
    ].firstWhere((s) => s.isNotEmpty, orElse: () => 'Target');

    // Another vault that is unlocked right now.
    final mountedVault = _unlocked[uri];
    if (mountedVault != null) {
      return _ResolvedTarget(mountedVault, label, subPath, 'vault:$uri');
    }

    if (uri.startsWith('content://')) {
      // SAF tree. Whether the grant is still valid can't be probed here;
      // a dead grant lists as unreadable and the run skips everything.
      return _ResolvedTarget(_folderContainer(rule, uri, label), label, subPath, uri);
    }

    if (await Directory(uri).exists()) {
      return _ResolvedTarget(_folderContainer(rule, uri, label), label, subPath, uri);
    }

    // Not a folder we can see: most likely a vault that isn't unlocked
    // yet, or a drive that isn't attached. Try again when a vault unlocks
    // (and, for live-watch rules, at the next poll).
    session.waitingOnTargets.putIfAbsent(uri, () => <String>{}).add(rule.id);
    VeLog.d(_tag, 'rule target unavailable; will retry');
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
