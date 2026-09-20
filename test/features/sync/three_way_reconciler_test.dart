import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_plan.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';
import 'package:vaultexplorer/features/sync/domain/reconciler/three_way_reconciler.dart';

SyncSideState st(int size, int mtime, [String? hash]) =>
    SyncSideState(size: size, mtimeSecs: mtime, hash: hash);

SyncSnapshot snap(
  Map<String, SyncSideState> files, {
  Set<String> dirs = const {},
  Set<String> unreadable = const {},
  Set<String> truncated = const {},
}) => SyncSnapshot(
  files: files,
  dirs: dirs,
  unreadableDirs: unreadable,
  truncatedDirs: truncated,
);

SyncStateRecord rec(String path, SyncSideState v, SyncSideState t) =>
    SyncStateRecord(ruleId: 'r', relPath: path, vault: v, target: t, lastSyncedAtMs: 0);

SyncRule mkRule({
  SyncDirection direction = SyncDirection.twoWay,
  ConflictStrategy strategy = ConflictStrategy.renameConflict,
  bool deleteOrphans = false,
}) => SyncRule(
  id: 'r',
  vaultInternalPath: 'Notes',
  targetEndpointUri: '/x',
  direction: direction,
  conflictStrategy: strategy,
  deleteOrphans: deleteOrphans,
);

/// Hash resolver over a fixed table; records what was asked for.
class Hashes {
  final Map<String, String> vault;
  final Map<String, String> target;
  final List<String> asked = [];
  Hashes({this.vault = const {}, this.target = const {}});

  Future<String?> call(SyncSide side, String path) async {
    asked.add('${side.name}:$path');
    return (side == SyncSide.vault ? vault : target)[path];
  }
}

final _now = DateTime(2026, 9, 19, 20, 15, 0);

Future<SyncPlan> plan({
  required SyncRule rule,
  Map<String, SyncSideState> vault = const {},
  Map<String, SyncSideState> target = const {},
  Map<String, SyncStateRecord> baseline = const {},
  Hashes? hashes,
  SyncSnapshot? vaultSnap,
  SyncSnapshot? targetSnap,
}) {
  return const ThreeWayReconciler().reconcile(
    rule: rule,
    vault: vaultSnap ?? snap(vault),
    target: targetSnap ?? snap(target),
    baseline: baseline,
    hashOf: (hashes ?? Hashes()).call,
    now: _now,
  );
}

SyncAction only(SyncPlan p) {
  expect(p.actions, hasLength(1), reason: p.actions.toString());
  return p.actions.single;
}

void main() {
  group('with a baseline', () {
    final base = {'a.txt': rec('a.txt', st(10, 100), st(10, 500))};

    test('unchanged on both sides -> nothing to do', () async {
      final p = await plan(
        rule: mkRule(),
        vault: {'a.txt': st(10, 100)},
        target: {'a.txt': st(10, 500)},
        baseline: base,
      );
      expect(p.actions, isEmpty);
    });

    test('mtime jitter inside the tolerance is not a change', () async {
      final p = await plan(
        rule: mkRule(),
        vault: {'a.txt': st(10, 101)},
        target: {'a.txt': st(10, 499)},
        baseline: base,
      );
      expect(p.actions, isEmpty);
    });

    test('changed only on the vault -> copy to target (a replace)', () async {
      final p = await plan(
        rule: mkRule(),
        vault: {'a.txt': st(12, 900)},
        target: {'a.txt': st(10, 500)},
        baseline: base,
      );
      final a = only(p);
      expect(a.kind, SyncActionKind.copyToTarget);
      expect(a.replacesExisting, isTrue);
    });

    test('changed only on the target -> copy to vault', () async {
      final p = await plan(
        rule: mkRule(),
        vault: {'a.txt': st(10, 100)},
        target: {'a.txt': st(11, 900)},
        baseline: base,
      );
      expect(only(p).kind, SyncActionKind.copyToVault);
    });

    test('each side is judged against its OWN baseline, not the other side\'s mtime', () async {
      // Target mtimes are always "newer" than vault's (the target stamps
      // 'now' on write) -- that must not look like a change.
      final p = await plan(
        rule: mkRule(),
        vault: {'a.txt': st(10, 100)},
        target: {'a.txt': st(10, 500)},
        baseline: base,
      );
      expect(p.actions, isEmpty);
    });

    test('size-equal touch with a recorded hash: hash decides', () async {
      final hashed = {'a.txt': rec('a.txt', st(10, 100, 'H'), st(10, 500, 'H'))};
      final same = Hashes(vault: {'a.txt': 'H'});
      final p = await plan(
        rule: mkRule(),
        vault: {'a.txt': st(10, 9000)}, // touched
        target: {'a.txt': st(10, 500)},
        baseline: hashed,
        hashes: same,
      );
      expect(p.actions, isEmpty, reason: 'same hash => not really changed');
      expect(same.asked, ['vault:a.txt']);
    });

    test('no hashing at all when size and mtime already answer the question', () async {
      final h = Hashes();
      await plan(
        rule: mkRule(),
        vault: {'a.txt': st(10, 100)},
        target: {'a.txt': st(10, 500)},
        baseline: base,
        hashes: h,
      );
      expect(h.asked, isEmpty);
    });
  });

  group('conflicts (both sides changed)', () {
    final base = {'readme.txt': rec('readme.txt', st(10, 100), st(10, 500))};
    final v = {'readme.txt': st(20, 800)};
    final t = {'readme.txt': st(30, 900)};

    test('renameConflict: target keeps the name, vault version is kept as a copy', () async {
      final a = only(await plan(rule: mkRule(), vault: v, target: t, baseline: base));
      expect(a.kind, SyncActionKind.keepBoth);
      expect(a.winner, SyncSide.target);
      expect(a.conflictCopyPath, 'readme (Vault Conflict 2026-09-19-201500).txt');
      expect(a.propagateConflictCopy, isTrue);
    });

    test('conflict copy keeps its folder and handles dotfiles / no extension', () async {
      final baseNested = {
        'sub/.env': rec('sub/.env', st(1, 1), st(1, 1)),
        'sub/LICENSE': rec('sub/LICENSE', st(1, 1), st(1, 1)),
      };
      final p = await plan(
        rule: mkRule(),
        vault: {'sub/.env': st(2, 999), 'sub/LICENSE': st(2, 999)},
        target: {'sub/.env': st(3, 999), 'sub/LICENSE': st(3, 999)},
        baseline: baseNested,
      );
      final names = p.actions.map((a) => a.conflictCopyPath).toSet();
      expect(names, {
        'sub/.env (Vault Conflict 2026-09-19-201500)',
        'sub/LICENSE (Vault Conflict 2026-09-19-201500)',
      });
    });

    test('vaultWins / targetWins overwrite in the chosen direction', () async {
      final vw = only(await plan(
        rule: mkRule(strategy: ConflictStrategy.vaultWins),
        vault: v, target: t, baseline: base,
      ));
      expect(vw.kind, SyncActionKind.copyToTarget);
      final tw = only(await plan(
        rule: mkRule(strategy: ConflictStrategy.targetWins),
        vault: v, target: t, baseline: base,
      ));
      expect(tw.kind, SyncActionKind.copyToVault);
    });

    test('keepNewer picks the clearly newer side', () async {
      final a = only(await plan(
        rule: mkRule(strategy: ConflictStrategy.keepNewer),
        vault: {'readme.txt': st(20, 5000)},
        target: {'readme.txt': st(30, 900)},
        baseline: base,
      ));
      expect(a.kind, SyncActionKind.copyToTarget);
    });

    test('keepNewer never guesses when it cannot tell: keeps both', () async {
      final tie = only(await plan(
        rule: mkRule(strategy: ConflictStrategy.keepNewer),
        vault: {'readme.txt': st(20, 900)},
        target: {'readme.txt': st(30, 901)},
        baseline: base,
      ));
      expect(tie.kind, SyncActionKind.keepBoth);
      final unknown = only(await plan(
        rule: mkRule(strategy: ConflictStrategy.keepNewer),
        vault: {'readme.txt': st(20, 0)},
        target: {'readme.txt': st(30, 901)},
        baseline: base,
      ));
      expect(unknown.kind, SyncActionKind.keepBoth);
    });

    test('both changed to identical content -> adopt, no conflict', () async {
      final h = Hashes(vault: {'readme.txt': 'X'}, target: {'readme.txt': 'X'});
      final a = only(await plan(
        rule: mkRule(),
        vault: {'readme.txt': st(20, 800)},
        target: {'readme.txt': st(20, 900)},
        baseline: base,
        hashes: h,
      ));
      expect(a.kind, SyncActionKind.adopt);
      expect(a.vaultState!.hash, 'X');
    });

    test('same size but different hashes -> still a conflict', () async {
      final h = Hashes(vault: {'readme.txt': 'X'}, target: {'readme.txt': 'Y'});
      final a = only(await plan(
        rule: mkRule(),
        vault: {'readme.txt': st(20, 800)},
        target: {'readme.txt': st(20, 900)},
        baseline: base,
        hashes: h,
      ));
      expect(a.kind, SyncActionKind.keepBoth);
    });

    test('one-way rules: the source wins, and only the destination is written', () async {
      final toTarget = only(await plan(
        rule: mkRule(direction: SyncDirection.vaultToTarget, strategy: ConflictStrategy.vaultWins),
        vault: v, target: t, baseline: base,
      ));
      expect(toTarget.kind, SyncActionKind.copyToTarget);

      final preserved = only(await plan(
        rule: mkRule(direction: SyncDirection.vaultToTarget),
        vault: v, target: t, baseline: base,
      ));
      expect(preserved.kind, SyncActionKind.keepBoth);
      expect(preserved.winner, SyncSide.vault);
      expect(preserved.propagateConflictCopy, isFalse);
      expect(preserved.conflictCopyPath, contains('Target Conflict'));
    });
  });

  group('deletions', () {
    final base = {'a.txt': rec('a.txt', st(10, 100), st(10, 500))};

    test('deleted on target + deleteOrphans -> delete on vault', () async {
      final a = only(await plan(
        rule: mkRule(deleteOrphans: true),
        vault: {'a.txt': st(10, 100)},
        baseline: base,
      ));
      expect(a.kind, SyncActionKind.deleteOnVault);
    });

    test('deleted on vault + deleteOrphans -> delete on target', () async {
      final a = only(await plan(
        rule: mkRule(deleteOrphans: true),
        target: {'a.txt': st(10, 500)},
        baseline: base,
      ));
      expect(a.kind, SyncActionKind.deleteOnTarget);
    });

    test('deleteOrphans off -> the deletion is left alone, not restored', () async {
      final a = only(await plan(
        rule: mkRule(),
        vault: {'a.txt': st(10, 100)},
        baseline: base,
      ));
      expect(a.kind, SyncActionKind.skip);
      expect(a.skipReason, SyncSkipReason.deletionsDisabled);
    });

    test('a modification beats a deletion', () async {
      final a = only(await plan(
        rule: mkRule(deleteOrphans: true),
        vault: {'a.txt': st(99, 900)}, // edited on the vault...
        baseline: base, // ...while the target deleted it
      ));
      expect(a.kind, SyncActionKind.copyToTarget);
      expect(a.replacesExisting, isFalse);
    });

    test('gone from both sides -> forget the ledger row', () async {
      final a = only(await plan(rule: mkRule(deleteOrphans: true), baseline: base));
      expect(a.kind, SyncActionKind.forget);
    });

    test('one-way rules never write to their source', () async {
      // vaultToTarget: a target-side deletion must not delete on the vault.
      final a = only(await plan(
        rule: mkRule(direction: SyncDirection.vaultToTarget, deleteOrphans: true),
        vault: {'a.txt': st(10, 100)},
        baseline: base,
      ));
      expect(a.kind, SyncActionKind.skip);
      expect(a.skipReason, SyncSkipReason.directionBlocked);
    });
  });

  group('first sight (no baseline)', () {
    test('new on one side -> copied across', () async {
      final p = await plan(
        rule: mkRule(),
        vault: {'v.txt': st(1, 1)},
        target: {'t.txt': st(1, 1)},
      );
      final byPath = {for (final a in p.actions) a.relPath: a.kind};
      expect(byPath, {
        't.txt': SyncActionKind.copyToVault,
        'v.txt': SyncActionKind.copyToTarget,
      });
    });

    test('one-way: a file that only exists on the destination is left alone', () async {
      final a = only(await plan(
        rule: mkRule(direction: SyncDirection.vaultToTarget),
        target: {'t.txt': st(1, 1)},
      ));
      expect(a.skipReason, SyncSkipReason.directionBlocked);
    });

    test('same size and agreeing mtimes -> adopt without hashing', () async {
      final h = Hashes();
      final a = only(await plan(
        rule: mkRule(),
        vault: {'a.txt': st(10, 100)},
        target: {'a.txt': st(10, 101)},
        hashes: h,
      ));
      expect(a.kind, SyncActionKind.adopt);
      expect(h.asked, isEmpty);
    });

    test('same size, mtimes far apart -> hashes decide', () async {
      final same = Hashes(vault: {'a.txt': 'H'}, target: {'a.txt': 'H'});
      expect(
        only(await plan(rule: mkRule(), vault: {'a.txt': st(10, 100)}, target: {'a.txt': st(10, 9999)}, hashes: same)).kind,
        SyncActionKind.adopt,
      );
      final different = Hashes(vault: {'a.txt': 'H1'}, target: {'a.txt': 'H2'});
      expect(
        only(await plan(rule: mkRule(), vault: {'a.txt': st(10, 100)}, target: {'a.txt': st(10, 9999)}, hashes: different)).kind,
        SyncActionKind.keepBoth,
      );
    });

    test('a hash that cannot be computed counts as different (never assume equal)', () async {
      final a = only(await plan(
        rule: mkRule(),
        vault: {'a.txt': st(10, 100)},
        target: {'a.txt': st(10, 9999)},
        hashes: Hashes(), // returns null
      ));
      expect(a.kind, SyncActionKind.keepBoth);
    });

    test('different sizes -> conflict', () async {
      final a = only(await plan(
        rule: mkRule(),
        vault: {'a.txt': st(10, 100)},
        target: {'a.txt': st(11, 100)},
      ));
      expect(a.kind, SyncActionKind.keepBoth);
    });

    test('big equal-sized files are adopted without a full read', () async {
      final h = Hashes();
      final big = const ThreeWayReconciler().hashLimitBytes + 1;
      final a = only(await plan(
        rule: mkRule(),
        vault: {'a.bin': st(big, 100)},
        target: {'a.bin': st(big, 9999)},
        hashes: h,
      ));
      expect(a.kind, SyncActionKind.adopt);
      expect(h.asked, isEmpty);
    });
  });

  group('safety guards', () {
    Map<String, SyncStateRecord> baselineOf(int n) => {
      for (var i = 0; i < n; i++) 'f$i.txt': rec('f$i.txt', st(1, 100), st(1, 500)),
    };
    Map<String, SyncSideState> vaultOf(int n) => {
      for (var i = 0; i < n; i++) 'f$i.txt': st(1, 100),
    };

    test('an empty target (unmounted drive, failed listing) never wipes the vault', () async {
      final p = await plan(
        rule: mkRule(deleteOrphans: true),
        vault: vaultOf(5),
        target: const {},
        baseline: baselineOf(5),
      );
      expect(p.deletionsBlocked, isTrue);
      expect(p.actions.every((a) => a.kind == SyncActionKind.skip), isTrue);
      expect(p.actions.first.skipReason, SyncSkipReason.massDeleteGuard);
    });

    test('a mass deletion is held back even if the target is not empty', () async {
      // 30 tracked files, the target lost 20 of them (> max(10, 50%)).
      final target = {for (var i = 20; i < 30; i++) 'f$i.txt': st(1, 500)};
      final p = await plan(
        rule: mkRule(deleteOrphans: true),
        vault: vaultOf(30),
        target: target,
        baseline: baselineOf(30),
      );
      expect(p.deletionsBlocked, isTrue);
      expect(p.countOf(SyncActionKind.deleteOnVault), 0);
    });

    test('a small, ordinary deletion still goes through', () async {
      final target = {for (var i = 3; i < 30; i++) 'f$i.txt': st(1, 500)};
      final p = await plan(
        rule: mkRule(deleteOrphans: true),
        vault: vaultOf(30),
        target: target,
        baseline: baselineOf(30),
      );
      expect(p.deletionsBlocked, isFalse);
      expect(p.countOf(SyncActionKind.deleteOnVault), 3);
    });

    test('files under a folder that failed to list are skipped, not deleted', () async {
      final p = await plan(
        rule: mkRule(deleteOrphans: true),
        vaultSnap: snap({'photos/a.jpg': st(1, 100), 'keep.txt': st(1, 100)}),
        targetSnap: snap({'keep.txt': st(1, 500)}, unreadable: {'photos'}),
        baseline: {
          'photos/a.jpg': rec('photos/a.jpg', st(1, 100), st(1, 500)),
          'keep.txt': rec('keep.txt', st(1, 100), st(1, 500)),
        },
      );
      expect(p.countOf(SyncActionKind.deleteOnVault), 0);
      final a = p.actions.singleWhere((x) => x.relPath == 'photos/a.jpg');
      expect(a.skipReason, SyncSkipReason.unreadableSubtree);
    });

    test('absence from a truncated listing is not a deletion, but present files still sync', () async {
      final p = await plan(
        rule: mkRule(deleteOrphans: true),
        vaultSnap: snap({'big/a': st(1, 100), 'big/b': st(1, 100)}),
        targetSnap: snap({'big/b': st(2, 900)}, truncated: {'big'}),
        baseline: {
          'big/a': rec('big/a', st(1, 100), st(1, 500)),
          'big/b': rec('big/b', st(1, 100), st(1, 500)),
        },
      );
      expect(p.actions.firstWhere((a) => a.relPath == 'big/a').skipReason, SyncSkipReason.unreadableSubtree);
      expect(p.actions.firstWhere((a) => a.relPath == 'big/b').kind, SyncActionKind.copyToVault);
    });

    test('file on one side, folder on the other -> skipped, never overwritten', () async {
      final p = await plan(
        rule: mkRule(),
        vaultSnap: snap({'x': st(1, 1)}),
        targetSnap: snap({'x/inner.txt': st(1, 1)}, dirs: {'x'}),
      );
      expect(p.actions, hasLength(2));
      expect(
        p.actions.map((a) => a.skipReason),
        everyElement(SyncSkipReason.typeMismatch),
        reason: 'the file inside the clashing path must not be written either',
      );
    });
  });
}
