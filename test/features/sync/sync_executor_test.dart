import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/sync/data/ledger/sync_ledger_repository.dart';
import 'package:vaultexplorer/features/sync/domain/executor/sync_executor.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_plan.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/sync_cancellation.dart';
import 'package:vaultexplorer/features/sync/domain/sync_rule_runner.dart';

import 'fake_sync_endpoint.dart';

final _at = DateTime(2026, 9, 19, 20, 15, 0);
const _conflictName = 'readme (Vault Conflict 2026-09-19-201500).txt';

SyncRule rule({
  SyncDirection direction = SyncDirection.twoWay,
  ConflictStrategy strategy = ConflictStrategy.renameConflict,
  bool deleteOrphans = false,
}) => SyncRule(
  id: 'r',
  vaultInternalPath: 'Notes',
  targetEndpointUri: '/storage/Documents',
  direction: direction,
  conflictStrategy: strategy,
  deleteOrphans: deleteOrphans,
);

class Harness {
  final clock = FakeClock();
  late final FakeSyncEndpoint vault = FakeSyncEndpoint('vault', clock, encrypted: true);

  /// Like an SAF tree: can't restore a source's modified time on write.
  late final FakeSyncEndpoint target = FakeSyncEndpoint(
    'target',
    clock,
    supportsSetModified: false,
  );
  final ledger = InMemorySyncLedger();
  DateTime now = _at;
  late final SyncExecutor executor = SyncExecutor(now: () => now);
  late final SyncRuleRunner runner = SyncRuleRunner(executor: executor);

  Future<SyncRunReport> run(SyncRule r, {SyncCancellationToken? token}) =>
      runner.run(
        rule: r,
        vault: vault,
        target: target,
        ledger: ledger,
        token: token ?? SyncCancellationToken(),
        now: _at,
      );

  bool get noTempFiles => [
    ...vault.files.keys,
    ...target.files.keys,
  ].every((p) => !p.endsWith('.vexp_tmp') && !p.endsWith('.vexp_old'));
}

void main() {
  group('Test 1: clean 3-way sync', () {
    test('a new host file lands in the vault and in the ledger; a rerun is a no-op', () async {
      final h = Harness();
      h.target.put('note.txt', 'hello');

      final first = await h.run(rule());
      expect(first.copied, 1);
      expect(first.failed, 0);
      expect(h.vault.read('note.txt'), 'hello');
      expect(h.ledger.baselineFor('r').keys, ['note.txt']);
      expect(h.noTempFiles, isTrue);

      final hashCalls = h.vault.hashCalls.length + h.target.hashCalls.length;
      final second = await h.run(rule());
      expect(second.copied + second.deleted + second.adopted + second.conflictsKeptBoth, 0);
      expect(
        h.vault.hashCalls.length + h.target.hashCalls.length,
        hashCalls,
        reason: 'an unchanged tree must not cost any hashing',
      );
    });

    test('a host deletion is propagated to the vault and the ledger row removed', () async {
      final h = Harness();
      h.target.put('note.txt', 'hello');
      await h.run(rule(deleteOrphans: true));

      h.target.files.remove('note.txt');
      final report = await h.run(rule(deleteOrphans: true));

      expect(report.deleted, 1);
      expect(h.vault.has('note.txt'), isFalse);
      expect(h.ledger.baselineFor('r'), isEmpty);
    });

    test('with deleteOrphans off the vault copy survives a host deletion', () async {
      final h = Harness();
      h.target.put('note.txt', 'hello');
      await h.run(rule());

      h.target.files.remove('note.txt');
      final report = await h.run(rule());

      expect(report.deleted, 0);
      expect(h.vault.read('note.txt'), 'hello');
    });

    test('edits flow in the direction they were made', () async {
      final h = Harness();
      h.vault.put('a.txt', 'one');
      h.target.put('b.txt', 'two');
      await h.run(rule());
      expect(h.target.read('a.txt'), 'one');
      expect(h.vault.read('b.txt'), 'two');

      h.vault.put('a.txt', 'one, edited in the vault');
      h.target.put('b.txt', 'two, edited on the host');
      final report = await h.run(rule());

      expect(report.copied, 2);
      expect(h.target.read('a.txt'), 'one, edited in the vault');
      expect(h.vault.read('b.txt'), 'two, edited on the host');
      expect(h.noTempFiles, isTrue);
    });
  });

  group('Test 2: conflict handling', () {
    Future<Harness> conflicted() async {
      final h = Harness();
      h.vault.put('readme.txt', 'v0');
      h.target.put('readme.txt', 'v0');
      await h.run(rule()); // adopted as identical
      h.vault.put('readme.txt', 'vault edit');
      h.target.put('readme.txt', 'target edit!');
      return h;
    }

    test('renameConflict keeps both versions, on both sides, and loses nothing', () async {
      final h = await conflicted();
      final report = await h.run(rule());

      expect(report.conflictsKeptBoth, 1);
      expect(report.failed, 0);
      for (final side in [h.vault, h.target]) {
        expect(side.read('readme.txt'), 'target edit!', reason: 'the host version keeps the name');
        expect(side.read(_conflictName), 'vault edit', reason: 'the vault version is preserved');
      }
      expect(h.noTempFiles, isTrue);
    });

    test('and settles: the next run does nothing (no endless conflict copies)', () async {
      final h = await conflicted();
      await h.run(rule());
      final again = await h.run(rule());

      expect(again.copied + again.conflictsKeptBoth + again.deleted, 0);
      expect(h.vault.files.keys.toSet(), {'readme.txt', _conflictName});
      expect(h.target.files.keys.toSet(), {'readme.txt', _conflictName});
    });

    test('a failed conflict resolution puts the vault file back under its own name', () async {
      final h = await conflicted();
      h.vault.failCopyTo.add('readme.txt'); // writing the winner into the vault fails

      final report = await h.run(rule());

      expect(report.failed, 1);
      expect(h.vault.read('readme.txt'), 'vault edit');
      expect(h.vault.has(_conflictName), isFalse);
      expect(h.noTempFiles, isTrue);
    });

    test('vaultWins overwrites the host copy', () async {
      final h = await conflicted();
      await h.run(rule(strategy: ConflictStrategy.vaultWins));
      expect(h.target.read('readme.txt'), 'vault edit');
      expect(h.vault.read('readme.txt'), 'vault edit');
    });
  });

  group('Test 3: cancellation on lock', () {
    test('cancelling mid-transfer removes the partial temp file and touches nothing else', () async {
      final h = Harness();
      h.target.put('big.bin', 'x' * 100);
      h.target.put('small.txt', 's');
      final token = SyncCancellationToken();
      h.vault.duringCopy = (rel) async {
        if (rel == 'big.bin') token.cancel();
      };

      final report = await h.run(rule(), token: token);

      expect(report.cancelled, isTrue);
      expect(h.vault.files, isEmpty, reason: 'no partial file, and the run stopped');
      expect(h.ledger.baselineFor('r'), isEmpty);
    });

    test('work completed before the cancel is kept and recorded', () async {
      final h = Harness();
      h.target.put('a.txt', 'done');
      h.target.put('b.bin', 'y' * 100);
      final token = SyncCancellationToken();
      h.vault.duringCopy = (rel) async {
        if (rel == 'b.bin') token.cancel();
      };

      final report = await h.run(rule(), token: token);

      expect(report.cancelled, isTrue);
      expect(h.vault.read('a.txt'), 'done');
      expect(h.vault.has('b.bin'), isFalse);
      expect(h.noTempFiles, isTrue);
      expect(h.ledger.baselineFor('r').keys, ['a.txt']);

      // A later run finishes the job.
      final resumed = await h.run(rule());
      expect(resumed.copied, 1);
      expect(h.vault.read('b.bin'), 'y' * 100);
    });

    test('a token cancelled before the run starts does no work', () async {
      final h = Harness();
      h.target.put('a.txt', 'x');
      final token = SyncCancellationToken()..cancel();

      final report = await h.run(rule(), token: token);

      expect(report.cancelled, isTrue);
      expect(h.vault.files, isEmpty);
    });

    test('token: every bound callback runs once; late binders run at once; unbind works', () {
      final token = SyncCancellationToken();
      var a = 0, b = 0, c = 0;
      final onA = () => a++; // a variable: bind and unbind see the same object
      token
        ..bindOnCancel(onA)
        ..bindOnCancel(() => b++);
      token.unbind(onA);
      token.cancel();
      token.cancel();
      token.bindOnCancel(() => c++);

      expect((a, b, c), (0, 1, 1));
      expect(token.isCancelled, isTrue);
    });
  });

  group('Test 4: no bouncing (re-entrancy)', () {
    test('a copy to storage that stamps its own mtime is not seen as a change', () async {
      final h = Harness();
      h.vault.put('a.txt', 'from the vault');

      await h.run(rule());
      expect(h.target.read('a.txt'), 'from the vault');
      expect(
        h.target.files['a.txt']!.mtime,
        isNot(h.vault.files['a.txt']!.mtime),
        reason: 'precondition: the target really did stamp a different mtime',
      );

      final second = await h.run(rule());
      final third = await h.run(rule());
      expect(second.copied + third.copied, 0);
    });

    test('the engine reports its own writes as in-flight / recently written for watchers', () async {
      final h = Harness();
      h.target.put('a.txt', 'x');

      final seenDuringCopy = <bool>[];
      h.vault.duringCopy = (rel) async {
        seenDuringCopy.add(h.executor.isInFlight(SyncSide.vault, rel));
      };
      await h.run(rule());

      expect(seenDuringCopy, [true]);
      expect(h.executor.inFlightPaths, isEmpty);
      expect(h.executor.wasRecentlyWritten(SyncSide.vault, 'a.txt'), isTrue);
      expect(h.executor.wasRecentlyWritten(SyncSide.target, 'a.txt'), isFalse);

      h.now = _at.add(const Duration(seconds: 30));
      expect(h.executor.wasRecentlyWritten(SyncSide.vault, 'a.txt'), isFalse);
    });
  });

  group('atomic replace', () {
    Future<Harness> synced() async {
      final h = Harness();
      h.vault.put('a.txt', 'one');
      h.target.put('a.txt', 'one');
      await h.run(rule());
      return h;
    }

    test('replacing an existing file never relies on rename-over-existing', () async {
      final h = await synced();
      h.target.put('a.txt', 'a much longer replacement');

      final report = await h.run(rule());

      expect(report.copied, 1);
      expect(h.vault.read('a.txt'), 'a much longer replacement');
      expect(h.noTempFiles, isTrue);
    });

    test('if the final swap fails, the old file is put back and no temp files remain', () async {
      final h = await synced();
      h.target.put('a.txt', 'a much longer replacement');
      h.vault.failRenameTo.add('a.txt');

      final report = await h.run(rule());

      expect(report.failed, 1);
      expect(h.vault.read('a.txt'), 'one');
      expect(h.vault.files.keys.toSet(), {'a.txt'});

      // Next run (the storage hiccup is gone) succeeds.
      final retry = await h.run(rule());
      expect(retry.failed, 0);
      expect(h.vault.read('a.txt'), 'a much longer replacement');
    });

    test('one failing file does not stop the others', () async {
      final h = Harness();
      h.target.put('a.txt', 'a');
      h.target.put('b.txt', 'b');
      h.target.put('c.txt', 'c');
      h.vault.failCopyTo.add('b.txt');

      final report = await h.run(rule());

      expect(report.copied, 2);
      expect(report.failed, 1);
      expect(h.vault.has('b.txt'), isFalse);
      expect(h.noTempFiles, isTrue);
      expect(report.completedCleanly, isFalse);
    });
  });

  group('recovery after an interrupted run', () {
    test('a file caught mid-swap is restored, not read as deleted and propagated', () async {
      final h = Harness();
      h.vault.put('a.txt', 'one');
      h.target.put('a.txt', 'one');
      await h.run(rule(deleteOrphans: true));

      // The process died after "a.txt -> a.txt.vexp_old" and while the new
      // copy sat complete in "a.txt.vexp_tmp".
      h.vault.files['a.txt.vexp_old'] = h.vault.files.remove('a.txt')!;
      h.vault.put('a.txt.vexp_tmp', 'two');

      final report = await h.run(rule(deleteOrphans: true));

      expect(h.vault.read('a.txt'), 'one', reason: 'old version restored');
      expect(h.target.read('a.txt'), 'one', reason: 'must NOT have been deleted');
      expect(report.deleted, 0);
      expect(h.noTempFiles, isTrue);
    });

    test('a stray temp file (the swap had not started yet) is removed', () async {
      final h = Harness();
      h.vault.put('a.txt', 'one');
      h.target.put('a.txt', 'one');
      await h.run(rule());
      h.target.put('a.txt.vexp_tmp', 'partial');

      await h.run(rule());

      expect(h.target.has('a.txt.vexp_tmp'), isFalse);
      expect(h.target.read('a.txt'), 'one');
    });
  });

  group('rule options', () {
    test('one-way vault -> target never writes to the vault', () async {
      final h = Harness();
      h.vault.put('from-vault.txt', 'v');
      h.target.put('only-on-host.txt', 't');

      final report = await h.run(rule(direction: SyncDirection.vaultToTarget));

      expect(h.target.read('from-vault.txt'), 'v');
      expect(h.vault.has('only-on-host.txt'), isFalse);
      expect(report.skipped, 1);
    });

    test('ignore patterns keep scratch files and media-store trash out of the vault', () async {
      final h = Harness();
      h.target.put('keep.txt', 'k');
      h.target.put('scratch.tmp', 's');
      h.target.put('.trashed-1700000000-photo.jpg', 'p');
      h.target.put('.vaultexplorer/sync_ledger.json', 'not ours to copy');

      await h.run(rule());

      expect(h.vault.files.keys.toSet(), {'keep.txt'});
    });

    test('a host listing that fails (unreadable folder) never deletes vault files', () async {
      final h = Harness();
      h.vault.put('photos/a.jpg', 'a');
      h.target.put('photos/a.jpg', 'a');
      await h.run(rule(deleteOrphans: true));

      h.target.unreadable.add('photos'); // e.g. the SAF grant was revoked
      final report = await h.run(rule(deleteOrphans: true));

      expect(h.vault.read('photos/a.jpg'), 'a');
      expect(report.deleted, 0);
      expect(report.incompleteScan, isTrue);
      expect(report.completedCleanly, isFalse);
    });
  });
}
