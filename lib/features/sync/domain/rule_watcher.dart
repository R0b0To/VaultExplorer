import 'dart:async';

import 'package:vaultexplorer/features/sync/domain/sync_debouncer.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

/// Decides *when* one live-watch rule should be synced.
///
/// Three things can ask for a run, and all of them end in [onTrigger]:
///
/// * a change signal from the vault side ([vaultChanged]), or from the host
///   folder ([hostPaths]) -- both debounced, so a burst becomes one run;
/// * the poll timer. Change signals are only an accelerator: nothing in
///   Android or in the engine reports every write (another app writing into
///   an exposed folder, the camera, and SAF providers without change
///   notifications all slip past), so a periodic run is what guarantees the
///   two sides converge;
///
/// A run is a full scan + reconcile, which is idempotent and writes nothing
/// when nothing changed, so a spurious trigger costs a scan and no more --
/// and can't loop, because an idle run produces no writes and therefore no
/// new change signals.
///
/// The poll is one-shot and re-armed by [runFinished], never while a run is
/// pending, so polls can't pile up. Its interval scales with how long the
/// last run took ([pollCostFactor] x), so a huge tree isn't rescanned more
/// than a few percent of the time.
class RuleWatcher {
  final String ruleId;
  final SyncIgnoreMatcher ignore;
  final void Function() onTrigger;

  /// Whether the engine itself just wrote [rel] on the host side (so the
  /// resulting change event isn't a change to react to).
  final bool Function(String rel) wasRecentlyWrittenOnTarget;

  /// Absolute paths reported by a host-folder watcher, or null when the
  /// target can't be watched (a document-provider folder, another vault).
  final Stream<String>? hostPaths;

  /// Absolute path of the watched host folder, used to turn [hostPaths]
  /// into paths relative to the sync root.
  final String hostRoot;

  final Duration basePoll;
  final Duration maxPoll;
  final int pollCostFactor;

  late final SyncDebouncer _debouncer;
  StreamSubscription<String>? _hostSub;
  Timer? _pollTimer;
  bool _started = false;

  RuleWatcher({
    required this.ruleId,
    required this.ignore,
    required this.onTrigger,
    required this.wasRecentlyWrittenOnTarget,
    this.hostPaths,
    this.hostRoot = '',
    Duration quiet = const Duration(seconds: 4),
    Duration maxWait = const Duration(seconds: 30),
    this.basePoll = const Duration(seconds: 60),
    this.maxPoll = const Duration(minutes: 30),
    this.pollCostFactor = 20,
  }) {
    _debouncer = SyncDebouncer(quiet: quiet, maxWait: maxWait, onFire: _trigger);
  }

  bool get isStarted => _started;

  /// True while a host-folder subscription is live.
  bool get isWatchingHost => _hostSub != null;

  void start() {
    if (_started) return;
    _started = true;
    try {
      _hostSub = hostPaths?.listen(
        _onHostPath,
        // A watcher that dies (inotify limits, folder removed) just stops
        // accelerating; the poll keeps the rule converging.
        onError: (Object _) => _dropHostSubscription(),
        onDone: _dropHostSubscription,
        cancelOnError: true,
      );
    } catch (_) {
      // Directory.watch() on Android can throw a dart:io assertion inside the
      // internal _MultiplexingFileSystemWatcher._startWatching when .listen()
      // is first called (e.g. paths with special characters or certain storage
      // providers). Fall back to poll-only; _hostSub stays null.
    }
    _armPoll(basePoll);
  }

  /// A change on the vault side (an in-app file operation finished there).
  void vaultChanged() {
    if (!_started) return;
    _debouncer.poke();
  }

  /// Call after each run of this rule, with how long it took.
  void runFinished(Duration took) {
    if (!_started) return;
    _armPoll(_pollAfter(took));
  }

  void stop() {
    _started = false;
    _debouncer.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
    _dropHostSubscription();
  }

  Duration _pollAfter(Duration took) {
    var next = took * pollCostFactor;
    if (next < basePoll) next = basePoll;
    if (next > maxPoll) next = maxPoll;
    return next;
  }

  void _armPoll(Duration after) {
    _pollTimer?.cancel();
    _pollTimer = Timer(after, () {
      _pollTimer = null;
      _trigger();
    });
  }

  void _trigger() {
    if (!_started) return;
    _debouncer.cancel();
    // Re-armed by runFinished once the run this starts is over.
    _pollTimer?.cancel();
    _pollTimer = null;
    onTrigger();
  }

  void _onHostPath(String absolutePath) {
    final rel = _relative(absolutePath);
    if (rel == null) return;
    if (rel.isNotEmpty) {
      if (isSyncArtifact(rel) || ignore.isIgnored(rel)) return;
      if (wasRecentlyWrittenOnTarget(rel)) return;
    }
    _debouncer.poke();
  }

  /// [absolutePath] relative to [hostRoot] ('' for the root itself), or null
  /// if it is outside it.
  String? _relative(String absolutePath) {
    if (hostRoot.isEmpty) return absolutePath;
    var root = hostRoot;
    while (root.length > 1 && root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (absolutePath == root) return '';
    if (absolutePath.startsWith('$root/')) {
      return absolutePath.substring(root.length + 1);
    }
    return null;
  }

  void _dropHostSubscription() {
    final sub = _hostSub;
    _hostSub = null;
    if (sub != null) unawaited(sub.cancel());
  }
}
