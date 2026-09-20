import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/rule_watcher.dart';
import 'package:vaultexplorer/features/sync/domain/sync_debouncer.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';
import 'package:vaultexplorer/features/sync/domain/sync_rule_validation.dart';
import 'package:vaultexplorer/features/sync/domain/sync_run_scheduler.dart';

const _s = Duration(seconds: 1);

RuleWatcher watcher({
  required void Function() onTrigger,
  Stream<String>? host,
  String root = '/sdcard/Docs',
  bool Function(String rel)? recent,
  List<String> ignore = const ['*.tmp'],
}) => RuleWatcher(
  ruleId: 'r',
  ignore: SyncIgnoreMatcher(ignore),
  onTrigger: onTrigger,
  wasRecentlyWrittenOnTarget: recent ?? (_) => false,
  hostPaths: host,
  hostRoot: root,
  quiet: _s,
  maxWait: const Duration(seconds: 5),
  basePoll: const Duration(seconds: 10),
);

void main() {
  group('SyncDebouncer', () {
    test('fires once, only after the quiet period', () {
      fakeAsync((async) {
        var fired = 0;
        final d = SyncDebouncer(quiet: _s, maxWait: const Duration(seconds: 5), onFire: () => fired++);

        d.poke();
        expect(d.isPending, isTrue);
        async.elapse(const Duration(milliseconds: 999));
        expect(fired, 0);
        async.elapse(const Duration(milliseconds: 2));
        expect(fired, 1);
        expect(d.isPending, isFalse);
        async.elapse(const Duration(minutes: 1));
        expect(fired, 1);
      });
    });

    test('every new poke restarts the quiet period', () {
      fakeAsync((async) {
        var fired = 0;
        final d = SyncDebouncer(quiet: _s, maxWait: const Duration(seconds: 30), onFire: () => fired++);

        d.poke();
        async.elapse(const Duration(milliseconds: 800));
        d.poke();
        async.elapse(const Duration(milliseconds: 800));
        expect(fired, 0, reason: 'the second poke pushed the deadline out');
        async.elapse(const Duration(milliseconds: 300));
        expect(fired, 1);
      });
    });

    test('maxWait stops a never-ending burst from postponing the run forever', () {
      fakeAsync((async) {
        var fired = 0;
        final d = SyncDebouncer(
          quiet: const Duration(seconds: 2),
          maxWait: const Duration(seconds: 5),
          onFire: () => fired++,
        );

        for (final ms in [0, 1500, 3000, 4500]) {
          async.elapse(Duration(milliseconds: ms == 0 ? 0 : 1500));
          d.poke();
        }
        expect(fired, 0);
        async.elapse(const Duration(milliseconds: 600)); // t = 5.1s
        expect(fired, 1);
      });
    });

    test('cancel drops a pending trigger; a later burst starts fresh', () {
      fakeAsync((async) {
        var fired = 0;
        final d = SyncDebouncer(quiet: _s, maxWait: const Duration(seconds: 5), onFire: () => fired++);

        d.poke();
        d.cancel();
        async.elapse(const Duration(seconds: 10));
        expect(fired, 0);

        d.poke();
        async.elapse(const Duration(seconds: 2));
        expect(fired, 1);
      });
    });
  });

  group('SyncRunScheduler', () {
    test('runs requests one at a time, in order', () async {
      final log = <String>[];
      final gates = <String, Completer<void>>{
        'a': Completer<void>(),
        'b': Completer<void>(),
      };
      final s = SyncRunScheduler((id) async {
        log.add('start $id');
        await gates[id]!.future;
        log.add('end $id');
      });

      s.request('a');
      s.request('b');
      await Future<void>.delayed(Duration.zero);
      expect(log, ['start a'], reason: 'b waits for a');
      expect(s.current, 'a');
      expect(s.isActive('b'), isTrue);

      gates['a']!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(log, ['start a', 'end a', 'start b']);
      gates['b']!.complete();
      await s.idle;
      expect(log.last, 'end b');
      expect(s.isBusy, isFalse);
    });

    test('a burst of requests for a queued rule costs one run', () async {
      var runs = 0;
      final gate = Completer<void>();
      final s = SyncRunScheduler((id) async {
        runs++;
        if (runs == 1) await gate.future;
      });

      s.request('a'); // starts running, blocked on the gate
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 20; i++) {
        s.request('b'); // all collapse into one queued run
      }
      gate.complete();
      await s.idle;

      expect(runs, 2);
    });

    test('a request for the rule that is running is queued again (its scan may be stale)', () async {
      var runs = 0;
      final gate = Completer<void>();
      final s = SyncRunScheduler((id) async {
        runs++;
        if (runs == 1) await gate.future;
      });

      s.request('a');
      await Future<void>.delayed(Duration.zero);
      s.request('a'); // change arrived mid-run
      gate.complete();
      await s.idle;

      expect(runs, 2);
    });

    test('a throwing rule does not stop the queue', () async {
      final ran = <String>[];
      final s = SyncRunScheduler((id) async {
        ran.add(id);
        if (id == 'bad') throw StateError('boom');
      });

      s.request('bad');
      s.request('good');
      await s.idle;

      expect(ran, ['bad', 'good']);
    });

    test('close drops the queue and refuses new requests; idle still completes', () async {
      final ran = <String>[];
      final gate = Completer<void>();
      final s = SyncRunScheduler((id) async {
        ran.add(id);
        await gate.future;
      });

      s.request('a');
      s.request('b');
      await Future<void>.delayed(Duration.zero);
      s.close();
      s.request('c');
      gate.complete();
      await s.idle;

      expect(ran, ['a']);
    });

    test('idle is already complete when nothing has been requested', () async {
      final s = SyncRunScheduler((_) async {});
      await s.idle;
      expect(s.isBusy, isFalse);
    });
  });

  group('RuleWatcher', () {
    test('a vault-side change triggers after the quiet period, once', () {
      fakeAsync((async) {
        var fired = 0;
        final w = watcher(onTrigger: () => fired++)..start();

        w.vaultChanged();
        w.vaultChanged();
        w.vaultChanged();
        async.elapse(const Duration(milliseconds: 900));
        expect(fired, 0);
        async.elapse(const Duration(milliseconds: 200));
        expect(fired, 1);
        w.stop();
      });
    });

    test('the poll is the fallback: it fires when nothing else did, and waits for runFinished', () {
      fakeAsync((async) {
        var fired = 0;
        final w = watcher(onTrigger: () => fired++)..start();

        async.elapse(const Duration(seconds: 9));
        expect(fired, 0);
        async.elapse(const Duration(seconds: 2));
        expect(fired, 1);

        async.elapse(const Duration(minutes: 5));
        expect(fired, 1, reason: 'not re-armed until the run it started is over');

        w.runFinished(const Duration(milliseconds: 100)); // 20x = 2s: the 10s base wins
        async.elapse(const Duration(seconds: 9));
        expect(fired, 1);
        async.elapse(const Duration(seconds: 2));
        expect(fired, 2);
        w.stop();
      });
    });

    test('a slow run stretches the next poll (about 20x its duration, capped)', () {
      fakeAsync((async) {
        var fired = 0;
        final w = watcher(onTrigger: () => fired++)..start();
        async.elapse(const Duration(seconds: 11));
        expect(fired, 1);

        w.runFinished(const Duration(seconds: 15)); // -> 300s, above the 10s base
        async.elapse(const Duration(seconds: 290));
        expect(fired, 1);
        async.elapse(const Duration(seconds: 20));
        expect(fired, 2);
        w.stop();
      });
    });

    test('a debounced trigger replaces a pending poll instead of doubling up', () {
      fakeAsync((async) {
        var fired = 0;
        final w = watcher(onTrigger: () => fired++)..start();

        async.elapse(const Duration(seconds: 9));
        w.vaultChanged();
        async.elapse(const Duration(seconds: 2)); // debounce fires (t = 11s)
        expect(fired, 1);
        async.elapse(const Duration(seconds: 30));
        expect(fired, 1, reason: 'the poll was cancelled by the trigger');
        w.stop();
      });
    });

    test('stop cancels everything', () {
      fakeAsync((async) {
        var fired = 0;
        final w = watcher(onTrigger: () => fired++)..start();
        w.vaultChanged();
        w.stop();
        w.vaultChanged();
        async.elapse(const Duration(minutes: 5));
        expect(fired, 0);
      });
    });

    test('host events: relative paths are filtered by ignore rules, artifacts and recent writes', () {
      fakeAsync((async) {
        var fired = 0;
        final host = StreamController<String>();
        final w = watcher(
          onTrigger: () => fired++,
          host: host.stream,
          recent: (rel) => rel == 'written-by-us.txt',
        )..start();

        // Each event is followed by more than the 1s quiet period, so a
        // trigger would show up immediately -- while the whole sequence
        // stays inside the 10s poll interval, which would otherwise fire.
        void event(String path) {
          host.add(path);
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 1200));
        }

        event('/sdcard/Docs/scratch.tmp'); // ignored pattern
        event('/sdcard/Docs/a.txt.vexp_tmp'); // the engine's own temp file
        event('/sdcard/Docs/written-by-us.txt'); // our own write
        event('/sdcard/Other/x.txt'); // outside the watched folder
        event('/sdcard/DocsExtra/x.txt'); // sibling with a common prefix
        expect(fired, 0);

        event('/sdcard/Docs/real-change.txt');
        expect(fired, 1);

        w.stop();
        unawaited(host.close());
      });
    });

    test('a change to the watched folder itself counts, with a trailing slash on the root too', () {
      fakeAsync((async) {
        var fired = 0;
        final host = StreamController<String>();
        final w = watcher(onTrigger: () => fired++, host: host.stream, root: '/sdcard/Docs/')..start();

        host.add('/sdcard/Docs');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(fired, 1);
        w.stop();
        unawaited(host.close());
      });
    });

    test('a host watcher that errors is dropped; the poll keeps working', () {
      fakeAsync((async) {
        var fired = 0;
        final host = StreamController<String>();
        final w = watcher(onTrigger: () => fired++, host: host.stream)..start();
        expect(w.isWatchingHost, isTrue);

        host.addError(StateError('inotify limit reached'));
        async.flushMicrotasks();
        expect(w.isWatchingHost, isFalse);

        async.elapse(const Duration(seconds: 11));
        expect(fired, 1, reason: 'poll still fires');
        w.stop();
        unawaited(host.close());
      });
    });
  });

  group('validateSyncRule', () {
    SyncRule rule(String id, String vaultPath, {String uri = '/target', String sub = ''}) => SyncRule(
      id: id,
      vaultInternalPath: vaultPath,
      targetEndpointUri: uri,
      targetSubPath: sub,
    );

    test('needs a target', () {
      expect(
        validateSyncRule(candidate: rule('a', 'Docs', uri: ''), vaultUri: '/v.vc', others: const []),
        SyncRuleProblem.noTarget,
      );
    });

    test('a target inside the same vault must not overlap the synced folder', () {
      expect(
        validateSyncRule(candidate: rule('a', 'Docs', uri: '/v.vc', sub: 'Docs/Backup'), vaultUri: '/v.vc', others: const []),
        SyncRuleProblem.overlapsTarget,
      );
      expect(
        validateSyncRule(candidate: rule('a', 'Docs', uri: '/v.vc', sub: 'Mirror'), vaultUri: '/v.vc', others: const []),
        isNull,
      );
      expect(
        validateSyncRule(candidate: rule('a', 'Docs', uri: '/other.vc', sub: 'Docs'), vaultUri: '/v.vc', others: const []),
        isNull,
        reason: 'same path in a different vault is fine',
      );
    });

    test('rules may not cover the same folder or nest inside each other', () {
      final existing = [rule('x', 'Photos/2024')];
      expect(
        validateSyncRule(candidate: rule('a', 'Photos'), vaultUri: '/v.vc', others: existing),
        SyncRuleProblem.overlapsOtherRule,
      );
      expect(
        validateSyncRule(candidate: rule('a', 'Photos/2024/Trip'), vaultUri: '/v.vc', others: existing),
        SyncRuleProblem.overlapsOtherRule,
      );
      expect(
        validateSyncRule(candidate: rule('a', 'Photos/2025'), vaultUri: '/v.vc', others: existing),
        isNull,
      );
      expect(
        validateSyncRule(candidate: rule('a', 'Photos/2024-old'), vaultUri: '/v.vc', others: existing),
        isNull,
        reason: 'a shared name prefix is not nesting',
      );
    });

    test('editing a rule does not conflict with itself', () {
      final existing = [rule('a', 'Docs')];
      expect(
        validateSyncRule(candidate: rule('a', 'Docs'), vaultUri: '/v.vc', others: existing),
        isNull,
      );
    });

    test('the vault root overlaps everything', () {
      expect(syncPathsOverlap('', 'Anything/At/All'), isTrue);
      expect(syncPathsOverlap('/A/B/', 'A/B'), isTrue);
      expect(syncPathsOverlap('A', 'AB'), isFalse);
    });
  });
}
