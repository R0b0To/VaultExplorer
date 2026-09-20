import 'dart:async';
import 'dart:io';

import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/features/sync/domain/rule_watcher.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

/// What to watch for one live-watch rule.
class LiveWatchSpec {
  final String ruleId;
  final SyncIgnoreMatcher ignore;

  /// A device folder that can be watched with inotify, or null (document
  /// provider folders and other vaults have no change notifications in Dart).
  final String? hostDirectory;

  /// Vault ids whose finished in-app file operations count as a change: the
  /// rule's own vault, plus the target vault when the target is one.
  final Set<int> vaultVolIds;

  /// Base interval of the fallback poll. Document providers are slow to
  /// list (cloud providers can take seconds), so they get a longer one.
  final Duration pollInterval;

  const LiveWatchSpec({
    required this.ruleId,
    required this.ignore,
    required this.vaultVolIds,
    this.hostDirectory,
    this.pollInterval = const Duration(seconds: 60),
  });
}

class _Entry {
  final LiveWatchSpec spec;
  final RuleWatcher watcher;
  _Entry(this.spec, this.watcher);
}

/// Owns the [RuleWatcher]s of every unlocked vault and feeds them change
/// signals.
///
/// There is no native "files changed" event for vault content, so the
/// vault-side signal is the completion of an in-app file operation
/// ([FileOperationService]: copy, move, delete, import, extract...). Writes
/// that bypass it (camera, the text editor, another app writing through the
/// document provider) are caught by each watcher's poll.
///
/// The host-side signal is `Directory.watch` on device folders. On Android's
/// shared storage inotify does not report every change made by other apps,
/// which is the second reason the poll is not optional.
class LiveWatchService {
  final FileOperationService _fileOps;
  final Map<String, List<_Entry>> _byVault = {};
  final Set<int> _seenOperations = {};

  LiveWatchService({required FileOperationService fileOps}) : _fileOps = fileOps {
    _fileOps.addListener(_onFileOperations);
  }

  /// Starts watching [specs] for the vault at [vaultUri], replacing any
  /// watchers it already had.
  void start({
    required String vaultUri,
    required List<LiveWatchSpec> specs,
    required void Function(String ruleId) requestRun,
    required bool Function(String rel) wasRecentlyWrittenOnTarget,
  }) {
    stop(vaultUri);
    if (specs.isEmpty) return;

    final entries = <_Entry>[];
    for (final spec in specs) {
      final watcher = RuleWatcher(
        ruleId: spec.ruleId,
        ignore: spec.ignore,
        onTrigger: () => requestRun(spec.ruleId),
        wasRecentlyWrittenOnTarget: wasRecentlyWrittenOnTarget,
        hostPaths: _watchHost(spec.hostDirectory),
        hostRoot: spec.hostDirectory ?? '',
        basePoll: spec.pollInterval,
      )..start();
      entries.add(_Entry(spec, watcher));
    }
    _byVault[vaultUri] = entries;
  }

  void stop(String vaultUri) {
    final entries = _byVault.remove(vaultUri);
    if (entries == null) return;
    for (final e in entries) {
      e.watcher.stop();
    }
  }

  void noteRunFinished(String vaultUri, String ruleId, Duration took) {
    final entries = _byVault[vaultUri];
    if (entries == null) return;
    for (final e in entries) {
      if (e.spec.ruleId == ruleId) e.watcher.runFinished(took);
    }
  }

  void dispose() {
    _fileOps.removeListener(_onFileOperations);
    for (final uri in _byVault.keys.toList()) {
      stop(uri);
    }
  }

  Stream<String>? _watchHost(String? directory) {
    if (directory == null || directory.isEmpty) return null;
    try {
      final dir = Directory(directory);
      if (!dir.existsSync()) return null;
      return dir.watch(recursive: true).map((event) => event.path);
    } catch (_) {
      return null; // unsupported here: the poll covers it
    }
  }

  void _onFileOperations() {
    final live = <int>{};
    for (final op in _fileOps.operations) {
      live.add(op.id);
      if (_seenOperations.contains(op.id)) continue;
      final status = op.status;
      if (status == FileOperationStatus.pending ||
          status == FileOperationStatus.running) {
        continue; // not finished yet: look again on the next notification
      }
      _seenOperations.add(op.id);
      if (status == FileOperationStatus.cancelled) continue;
      _vaultsChanged(op.sourceVolId, op.destVolId);
    }
    _seenOperations.retainAll(live);
  }

  void _vaultsChanged(int a, int b) {
    for (final entries in _byVault.values) {
      for (final e in entries) {
        if (e.spec.vaultVolIds.contains(a) || e.spec.vaultVolIds.contains(b)) {
          e.watcher.vaultChanged();
        }
      }
    }
  }
}
