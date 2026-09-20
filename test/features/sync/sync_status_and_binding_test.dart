import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/sync/data/config/sync_config_store.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_plan.dart';
import 'package:vaultexplorer/features/sync/services/sync_status.dart';

void main() {
  group('SyncTargetBinding', () {
    test('round-trips uri, name and the folder within the target', () {
      const binding = SyncTargetBinding(
        uri: 'content://com.android.externalstorage.documents/tree/primary%3ADocs',
        displayName: 'Docs',
        subPath: 'Work/Notes',
      );
      final back = SyncTargetBinding.tryParse(jsonEncode(binding.toJson()));

      expect(back!.uri, binding.uri);
      expect(back.displayName, 'Docs');
      expect(back.subPath, 'Work/Notes');
    });

    test('an older binding without subPath still loads (subPath is empty)', () {
      final back = SyncTargetBinding.tryParse('{"uri":"/sdcard/Docs","displayName":"Docs"}');
      expect(back!.uri, '/sdcard/Docs');
      expect(back.subPath, '');
    });

    test('an empty subPath is not written', () {
      expect(const SyncTargetBinding(uri: '/x').toJson().containsKey('subPath'), isFalse);
    });

    test('anything unusable reads as "no binding" rather than throwing', () {
      expect(SyncTargetBinding.tryParse(null), isNull);
      expect(SyncTargetBinding.tryParse(''), isNull);
      expect(SyncTargetBinding.tryParse('not json'), isNull);
      expect(SyncTargetBinding.tryParse('[1,2]'), isNull);
      expect(SyncTargetBinding.tryParse('{"displayName":"no uri"}'), isNull);
      expect(SyncTargetBinding.tryParse('{"uri":""}'), isNull);
    });
  });

  group('SyncStatus', () {
    test('has value equality, so notifiers only fire on a real change', () {
      const a = SyncStatus(running: true, targetLabel: 'Docs', doneActions: 1, totalActions: 4);
      const b = SyncStatus(running: true, targetLabel: 'Docs', doneActions: 1, totalActions: 4);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(doneActions: 2), isFalse);
    });

    test('fraction is null until the total is known, and stays within 0..1', () {
      expect(const SyncStatus().fraction, isNull);
      expect(const SyncStatus(doneActions: 1, totalActions: 4).fraction, 0.25);
      expect(const SyncStatus(doneActions: 9, totalActions: 4).fraction, 1.0);
    });

    test('copyWith keeps what it is not asked to change', () {
      const s = SyncStatus(running: true, targetLabel: 'Docs', attention: 2);
      final t = s.copyWith(doneActions: 3);
      expect(t.running, isTrue);
      expect(t.targetLabel, 'Docs');
      expect(t.attention, 2);
      expect(t.doneActions, 3);
    });
  });

  group('SyncRunReport', () {
    test('didWork: only real changes count, not a run that found everything in step', () {
      expect(const SyncRunReport(ruleId: 'r').didWork, isFalse);
      expect(const SyncRunReport(ruleId: 'r', skipped: 5).didWork, isFalse);
      expect(const SyncRunReport(ruleId: 'r', copied: 1).didWork, isTrue);
      expect(const SyncRunReport(ruleId: 'r', deleted: 1).didWork, isTrue);
      expect(const SyncRunReport(ruleId: 'r', conflictsKeptBoth: 1).didWork, isTrue);
      expect(const SyncRunReport(ruleId: 'r', adopted: 1).didWork, isTrue);
    });

    test('needsAttention: failures, unreadable folders and paused deletions -- not benign skips, not cancels', () {
      expect(const SyncRunReport(ruleId: 'r', skipped: 9).needsAttention, isFalse);
      expect(const SyncRunReport(ruleId: 'r', failed: 1).needsAttention, isTrue);
      expect(const SyncRunReport(ruleId: 'r', incompleteScan: true).needsAttention, isTrue);
      expect(const SyncRunReport(ruleId: 'r', deletionsBlocked: true).needsAttention, isTrue);
      expect(
        const SyncRunReport(ruleId: 'r', failed: 3, cancelled: true).needsAttention,
        isFalse,
        reason: 'a run cut short by a lock is not a problem to report',
      );
    });
  });
}
