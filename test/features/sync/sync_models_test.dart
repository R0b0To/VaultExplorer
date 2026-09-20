import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/sync/data/ledger/sync_ledger_repository.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

void main() {
  group('SyncRule / SyncConfig JSON', () {
    test('round-trips every field', () {
      final rule = SyncRule(
        id: 'abc',
        vaultInternalPath: '/Notes/2024/',
        targetEndpointUri: 'content://tree/x',
        targetSubPath: 'Sub',
        targetDisplayName: 'Documents',
        direction: SyncDirection.targetToVault,
        conflictStrategy: ConflictStrategy.keepNewer,
        autoSyncOnUnlock: false,
        liveWatch: true,
        deleteOrphans: true,
        ignorePatterns: const ['*.log'],
        lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final back = SyncRule.fromJson(rule.toJson());

      expect(back.toJson(), rule.toJson());
      expect(back.vaultRelativePath, 'Notes/2024');
      expect(back.direction, SyncDirection.targetToVault);
      expect(back.lastSyncedAt, rule.lastSyncedAt);
    });

    test('unknown enum values and missing fields fall back to the safe defaults', () {
      final rule = SyncRule.fromJson({
        'id': 'x',
        'direction': 'someFutureMode',
        'conflictStrategy': 'alsoUnknown',
      });
      expect(rule.direction, SyncDirection.twoWay);
      expect(rule.conflictStrategy, ConflictStrategy.renameConflict);
      expect(rule.deleteOrphans, isFalse, reason: 'deleting is opt-in');
      expect(rule.liveWatch, isFalse);
      expect(rule.autoSyncOnUnlock, isTrue);
      expect(rule.ignorePatterns, SyncRule.defaultIgnorePatterns);
    });

    test('one unreadable rule does not take the config down', () {
      final config = SyncConfig.fromJson({
        'vaultSyncId': 'vault-1',
        'rules': [
          {'id': 'good', 'vaultInternalPath': 'A', 'targetEndpointUri': '/x'},
          {'no-id': true},
          'not even a map',
        ],
      });
      expect(config.vaultSyncId, 'vault-1');
      expect(config.rules.map((r) => r.id), ['good']);
    });

    test('a config without a vaultSyncId is rejected rather than silently re-keyed', () {
      expect(() => SyncConfig.fromJson({'rules': []}), throwsFormatException);
    });

    test('normalizeSyncPath', () {
      expect(normalizeSyncPath('/Notes//2024/'), 'Notes/2024');
      expect(normalizeSyncPath('/'), '');
      expect(normalizeSyncPath(''), '');
    });
  });

  group('SyncIgnoreMatcher', () {
    test('the engine\'s own files and the vault meta folder are always ignored', () {
      final m = SyncIgnoreMatcher(const []);
      expect(m.isIgnored('a.txt.vexp_tmp'), isTrue);
      expect(m.isIgnored('deep/dir/a.txt.vexp_old'), isTrue);
      expect(m.isIgnored('.vaultexplorer/sync_ledger.json'), isTrue);
      expect(m.isIgnored('notes/a.txt'), isFalse);
    });

    test('segment patterns match at any depth and cover everything beneath a folder', () {
      final m = SyncIgnoreMatcher(const ['*.tmp', '.*', 'node_modules']);
      expect(m.isIgnored('a/b/c.tmp'), isTrue);
      expect(m.isIgnored('.git/config'), isTrue);
      expect(m.isIgnored('src/.hidden'), isTrue);
      expect(m.isIgnored('node_modules/x/y.js'), isTrue);
      expect(m.isIgnored('src/main.dart'), isFalse);
    });

    test('patterns with a slash are anchored at the sync root', () {
      final m = SyncIgnoreMatcher(const ['cache/*.bin']);
      expect(m.isIgnored('cache/x.bin'), isTrue);
      expect(m.isIgnored('cache/x.bin.meta'), isFalse);
      expect(m.isIgnored('other/cache/x.bin'), isFalse);
    });

    test('matching is case-insensitive and ? matches a single character', () {
      final m = SyncIgnoreMatcher(const ['THUMBS.DB', 'file?.txt']);
      expect(m.isIgnored('sub/Thumbs.db'), isTrue);
      expect(m.isIgnored('file1.txt'), isTrue);
      expect(m.isIgnored('file12.txt'), isFalse);
    });

    test('regex metacharacters in a pattern are literal', () {
      final m = SyncIgnoreMatcher(const ['a+b(1).txt']);
      expect(m.isIgnored('a+b(1).txt'), isTrue);
      expect(m.isIgnored('aab1.txt'), isFalse);
    });

    test('the default rule patterns cover editor swap files and media-store trash', () {
      final m = SyncIgnoreMatcher(SyncRule.defaultIgnorePatterns);
      expect(m.isIgnored('doc.txt~'), isTrue);
      expect(m.isIgnored('.doc.txt.swp'), isTrue);
      expect(m.isIgnored('DCIM/.trashed-1700000000-IMG_1.jpg'), isTrue);
      expect(m.isIgnored('DCIM/IMG_1.jpg'), isFalse);
    });
  });

  group('SyncLedgerCodec', () {
    SyncStateRecord row(String path, {String? vh, String? th}) => SyncStateRecord(
      ruleId: 'r#1',
      relPath: path,
      vault: SyncSideState(size: 10, mtimeSecs: 100, hash: vh),
      target: SyncSideState(size: 11, mtimeSecs: 500, hash: th),
      lastSyncedAtMs: 42,
    );

    test('round-trips rows with and without hashes, and odd file names', () {
      final rules = {
        'r#1': {
          'a.txt': row('a.txt'),
          'dir/ünï cödé "q" [1].txt': row('dir/ünï cödé "q" [1].txt', vh: 'aa', th: 'bb'),
        },
      };
      final back = SyncLedgerCodec.decode(SyncLedgerCodec.encode(rules));
      expect(back, rules);
    });

    test('empty rules are not written', () {
      final json = SyncLedgerCodec.encode({'gone': <String, SyncStateRecord>{}});
      expect(SyncLedgerCodec.decode(json), isEmpty);
    });

    test('malformed rows are skipped, good ones kept', () {
      const json =
          '{"v":1,"rules":{"r":['
          '["ok.txt",1,2,null,3,4,null,5],'
          '["short"],'
          '["bad-types",1,"2",null,3,4,null,5],'
          '"not a row"]}}';
      final back = SyncLedgerCodec.decode(json);
      expect(back['r']!.keys, ['ok.txt']);
    });

    test('something that is not a ledger throws, so the caller can start empty', () {
      expect(() => SyncLedgerCodec.decode('not json'), throwsFormatException);
      expect(() => SyncLedgerCodec.decode('[1,2]'), throwsFormatException);
      expect(() => SyncLedgerCodec.decode('{"v":1}'), throwsFormatException);
    });
  });

  group('InMemorySyncLedger', () {
    SyncStateRecord row(String rule, String path) => SyncStateRecord(
      ruleId: rule,
      relPath: path,
      vault: const SyncSideState(size: 1, mtimeSecs: 1),
      target: const SyncSideState(size: 1, mtimeSecs: 1),
      lastSyncedAtMs: 0,
    );

    test('put / remove / clearRule and dirty tracking', () async {
      final l = InMemorySyncLedger();
      expect(l.isDirty, isFalse);
      l.put(row('r1', 'a'));
      l.put(row('r1', 'b'));
      l.put(row('r2', 'a'));
      expect(l.isDirty, isTrue);
      expect(l.ruleKeys.toSet(), {'r1', 'r2'});
      expect(l.baselineFor('r1').keys.toSet(), {'a', 'b'});

      await l.flush();
      expect(l.isDirty, isFalse);
      l.remove('r1', 'missing');
      expect(l.isDirty, isFalse, reason: 'removing nothing changes nothing');
      l.remove('r1', 'a');
      l.clearRule('r2');
      expect(l.baselineFor('r1').keys, ['b']);
      expect(l.baselineFor('r2'), isEmpty);
    });

    test('baselineFor returns a copy: mutating it never changes the ledger', () {
      final l = InMemorySyncLedger()..put(row('r', 'a'));
      l.baselineFor('r').clear();
      expect(l.baselineFor('r'), hasLength(1));
    });
  });

  group('SyncSnapshot', () {
    test('isUnderUnreadable / isUnderTruncated respect folder boundaries', () {
      const s = SyncSnapshot(
        files: {},
        unreadableDirs: {'photos'},
        truncatedDirs: {'big'},
      );
      expect(s.isUnderUnreadable('photos/a.jpg'), isTrue);
      expect(s.isUnderUnreadable('photos'), isTrue);
      expect(s.isUnderUnreadable('photos-old/a.jpg'), isFalse);
      expect(s.isUnderTruncated('big/x'), isTrue);
      expect(s.isUnderTruncated('bigger/x'), isFalse);
      expect(s.isComplete, isFalse);
    });

    test('a truncated root makes every path "unknown when missing"', () {
      const s = SyncSnapshot(files: {}, truncatedDirs: {''});
      expect(s.isUnderTruncated('anything/at/all'), isTrue);
    });

    test('an unreadable root makes everything unknown', () {
      const s = SyncSnapshot(files: {}, rootReadable: false);
      expect(s.isUnderUnreadable('x'), isTrue);
      expect(s.isComplete, isFalse);
    });
  });
}
