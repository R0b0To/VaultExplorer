import 'dart:async';

import 'package:test/test.dart';
import 'package:vaultexplorer/data/services/vault_relocation_service.dart';

const _pkg = 'com.aeidolon.vaultexplorer';
const _external = 'content://com.android.externalstorage.documents/document/primary%3AVaults%2Fwork.hc';
const _externalTree = 'content://com.android.externalstorage.documents/tree/primary%3AVaults%2FNotes';
const _internal = 'file:///data/user/0/$_pkg/files/vaults/work.hc';
const _internalDir = 'file:///data/user/0/$_pkg/files/vaults/Notes';

/// Records every call, in order, and can be told to fail at any step.
class _FakeGateway implements RelocationGateway {
  final List<String> log;
  _FakeGateway(this.log);

  String copyInUri = _internal;
  String? copyOutUri = _external;
  Object? copyInError;
  Object? copyOutError;
  Object? finalizeError;
  Object? discardError;
  RelocationFinalize finalizeResult = const RelocationFinalize(sourceDeleted: true);
  Completer<void>? copyGate; // hold a copy open so a test can act mid-copy
  final List<int> opIds = [];
  final List<int> cancelled = [];
  bool? lastDeleteSource;

  @override
  Future<RelocationCopy> copyIn({
    required String sourceUri,
    required bool isFolderVault,
    required String displayName,
    required int opId,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) async {
    log.add('copyIn($sourceUri)');
    opIds.add(opId);
    onProgress?.call(50, 100);
    if (copyGate != null) await copyGate!.future;
    if (copyInError != null) throw copyInError!;
    onProgress?.call(100, 100);
    return RelocationCopy(uri: copyInUri, bytes: 1000, files: 3);
  }

  @override
  Future<RelocationCopy?> copyOut({
    required String sourceUri,
    required bool isFolderVault,
    required String displayName,
    required int opId,
    void Function(int bytesDone, int bytesTotal)? onProgress,
  }) async {
    log.add('copyOut($sourceUri)');
    opIds.add(opId);
    if (copyGate != null) await copyGate!.future;
    if (copyOutError != null) throw copyOutError!;
    final uri = copyOutUri;
    return uri == null ? null : RelocationCopy(uri: uri, bytes: 2000, files: 1);
  }

  @override
  Future<RelocationFinalize> finalize({
    required String oldUri,
    required String newUri,
    required bool isFolderVault,
    required bool deleteSource,
  }) async {
    log.add('finalize($oldUri -> $newUri, delete=$deleteSource)');
    lastDeleteSource = deleteSource;
    if (finalizeError != null) throw finalizeError!;
    return finalizeResult;
  }

  @override
  Future<void> discardCopy({required String uri, required bool isFolderVault}) async {
    log.add('discard($uri)');
    if (discardError != null) throw discardError!;
  }

  @override
  Future<void> cancel(int opId) async {
    log.add('cancel($opId)');
    cancelled.add(opId);
  }
}

class _FakeRecords implements RelocationRecordStore {
  final List<String> log;
  _FakeRecords(this.log);
  Object? error;
  RecordMove result = const RecordMove();
  Completer<void>? gate;

  @override
  Future<RecordMove> moveRecord({required String oldUri, required String newUri}) async {
    log.add('moveRecord($oldUri -> $newUri)');
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  late List<String> log;
  late _FakeGateway gateway;
  late _FakeRecords records;
  late VaultRelocationService service;

  setUp(() {
    log = [];
    gateway = _FakeGateway(log);
    records = _FakeRecords(log);
    service = VaultRelocationService(gateway: gateway, records: records);
  });

  group('moving into app storage', () {
    test('copies first, then switches the record, then finishes, in that order', () async {
      final outcome = await service.moveToAppStorage(uri: _external, displayName: 'work.hc', isFolderVault: false);

      expect(log, [
        'copyIn($_external)',
        'moveRecord($_external -> $_internal)',
        'finalize($_external -> $_internal, delete=true)',
      ]);
      expect(outcome.completed, isTrue);
      expect(outcome.newUri, _internal);
      expect(outcome.bytes, 1000);
      expect(outcome.files, 3);
      expect(outcome.originalDeleted, isTrue);
      expect(outcome.originalLeftBehind, isFalse);
    });

    test('reports each phase in order', () async {
      final phases = <RelocationPhase>[];
      await service.moveToAppStorage(
        uri: _external,
        displayName: 'work.hc',
        isFolderVault: false,
        onPhase: phases.add,
      );
      expect(phases, [RelocationPhase.copying, RelocationPhase.switching, RelocationPhase.finishing]);
    });

    test('forwards copy progress', () async {
      final ticks = <(int, int)>[];
      await service.moveToAppStorage(
        uri: _external,
        displayName: 'work.hc',
        isFolderVault: false,
        onProgress: (d, t) => ticks.add((d, t)),
      );
      expect(ticks, [(50, 100), (100, 100)]);
    });

    test('keeping the original skips deletion and is not reported as left behind', () async {
      gateway.finalizeResult = const RelocationFinalize(sourceDeleted: false);
      final outcome = await service.moveToAppStorage(
        uri: _external,
        displayName: 'work.hc',
        isFolderVault: false,
        deleteOriginal: false,
      );
      expect(gateway.lastDeleteSource, isFalse);
      expect(outcome.originalDeleted, isFalse);
      expect(outcome.deleteRequested, isFalse);
      expect(outcome.originalLeftBehind, isFalse);
    });

    test('works for a folder vault', () async {
      gateway.copyInUri = _internalDir;
      final outcome = await service.moveToAppStorage(uri: _externalTree, displayName: 'Notes', isFolderVault: true);
      expect(outcome.newUri, _internalDir);
      expect(log.first, 'copyIn($_externalTree)');
    });
  });

  group('moving out of app storage', () {
    test('copies out, switches the record, then finishes', () async {
      final outcome = await service.moveOutOfAppStorage(uri: _internal, displayName: 'work.hc', isFolderVault: false);
      expect(log, [
        'copyOut($_internal)',
        'moveRecord($_internal -> $_external)',
        'finalize($_internal -> $_external, delete=true)',
      ]);
      expect(outcome.completed, isTrue);
      expect(outcome.newUri, _external);
    });

    test('dismissing the destination picker changes nothing', () async {
      gateway.copyOutUri = null;
      final outcome = await service.moveOutOfAppStorage(uri: _internal, displayName: 'work.hc', isFolderVault: false);
      expect(outcome.completed, isFalse);
      expect(outcome.newUri, isNull);
      expect(log, ['copyOut($_internal)']); // no record switch, no finalize, no discard
    });
  });

  group('when something goes wrong', () {
    test('a failed or unverified copy leaves everything alone', () async {
      gateway.copyInError = const RelocationException(RelocationFailure.verifyFailed, message: 'mismatch');
      await expectLater(
        service.moveToAppStorage(uri: _external, displayName: 'w', isFolderVault: false),
        throwsA(predicate((e) => e is RelocationException && e.reason == RelocationFailure.verifyFailed)),
      );
      // The native side already removed its partial copy, so there is nothing to switch, finish or discard.
      expect(log, ['copyIn($_external)']);
    });

    test('a failed switch removes the copy and never touches the original', () async {
      records.error = StateError('disk full');
      await expectLater(
        service.moveToAppStorage(uri: _external, displayName: 'w', isFolderVault: false),
        throwsA(predicate((e) => e is RelocationException && e.reason == RelocationFailure.recordSwitchFailed)),
      );
      expect(log, [
        'copyIn($_external)',
        'moveRecord($_external -> $_internal)',
        'discard($_internal)',
      ]);
      expect(log.any((l) => l.startsWith('finalize')), isFalse);
    });

    test('a failed switch still reports the switch failure if removing the copy also fails', () async {
      records.error = StateError('disk full');
      gateway.discardError = StateError('cannot delete');
      await expectLater(
        service.moveToAppStorage(uri: _external, displayName: 'w', isFolderVault: false),
        throwsA(predicate((e) => e is RelocationException && e.reason == RelocationFailure.recordSwitchFailed)),
      );
    });

    test('a failure while finishing still counts as a completed move', () async {
      gateway.finalizeError = StateError('provider went away');
      final outcome = await service.moveToAppStorage(uri: _external, displayName: 'w', isFolderVault: false);
      expect(outcome.completed, isTrue);
      expect(outcome.newUri, _internal);
      expect(outcome.originalDeleted, isFalse);
      expect(outcome.originalLeftBehind, isTrue);
    });

    test('an original that could not be deleted is reported as left behind', () async {
      gateway.finalizeResult = const RelocationFinalize(sourceDeleted: false, reason: 'DELETE_FAILED');
      final outcome = await service.moveToAppStorage(uri: _external, displayName: 'w', isFolderVault: false);
      expect(outcome.originalLeftBehind, isTrue);
    });

    test('carries up whether biometrics and automation had to be dropped', () async {
      records.result = const RecordMove(biometricsDropped: true);
      gateway.finalizeResult = const RelocationFinalize(sourceDeleted: true, automationReset: true);
      final outcome = await service.moveToAppStorage(uri: _external, displayName: 'w', isFolderVault: false);
      expect(outcome.biometricsDropped, isTrue);
      expect(outcome.automationReset, isTrue);
    });

    test('the service is usable again after a failure', () async {
      gateway.copyInError = const RelocationException(RelocationFailure.io);
      await expectLater(
        service.moveToAppStorage(uri: _external, displayName: 'w', isFolderVault: false),
        throwsA(isA<RelocationException>()),
      );
      expect(service.isBusy, isFalse);
      gateway.copyInError = null;
      final outcome = await service.moveToAppStorage(uri: _external, displayName: 'w', isFolderVault: false);
      expect(outcome.completed, isTrue);
    });
  });

  group('guard rails', () {
    test('refuses vaults that are not a single file or folder', () async {
      for (final uri in ['usb:/dev/bus/usb/001/002', 'composite:abc']) {
        await expectLater(
          service.moveToAppStorage(uri: uri, displayName: 'x', isFolderVault: false),
          throwsA(predicate((e) => e is RelocationException && e.reason == RelocationFailure.unsupportedSource)),
        );
      }
      expect(log, isEmpty);
    });

    test('refuses to move a vault into app storage twice', () async {
      await expectLater(
        service.moveToAppStorage(uri: _internal, displayName: 'x', isFolderVault: false),
        throwsA(predicate((e) => e is RelocationException && e.reason == RelocationFailure.alreadyInAppStorage)),
      );
      expect(log, isEmpty);
    });

    test('refuses to move a vault out of app storage if it is not in it', () async {
      await expectLater(
        service.moveOutOfAppStorage(uri: _external, displayName: 'x', isFolderVault: false),
        throwsA(predicate((e) => e is RelocationException && e.reason == RelocationFailure.notInAppStorage)),
      );
      expect(log, isEmpty);
    });

    test('only one move runs at a time', () async {
      gateway.copyGate = Completer<void>();
      final first = service.moveToAppStorage(uri: _external, displayName: 'a', isFolderVault: false);
      await Future<void>.delayed(Duration.zero);
      expect(service.isBusy, isTrue);

      await expectLater(
        service.moveToAppStorage(uri: _externalTree, displayName: 'b', isFolderVault: true),
        throwsA(predicate((e) => e is RelocationException && e.reason == RelocationFailure.busy)),
      );
      expect(log.where((l) => l.startsWith('copyIn')).length, 1);

      gateway.copyGate!.complete();
      expect((await first).completed, isTrue);
      expect(service.isBusy, isFalse);
    });
  });

  group('operation ids and cancelling', () {
    test('ids come from the reserved relocation range and never repeat', () async {
      await service.moveToAppStorage(uri: _external, displayName: 'a', isFolderVault: false);
      await service.moveToAppStorage(uri: _externalTree, displayName: 'b', isFolderVault: true);
      expect(gateway.opIds[0], VaultRelocationService.kFirstRelocationOpId);
      expect(gateway.opIds[1], VaultRelocationService.kFirstRelocationOpId + 1);
      expect(gateway.opIds.every((id) => id >= 0x50000000), isTrue);
    });

    test('cancel while copying stops that operation', () async {
      gateway.copyGate = Completer<void>();
      final move = service.moveToAppStorage(uri: _external, displayName: 'a', isFolderVault: false);
      await Future<void>.delayed(Duration.zero);

      await service.cancel();
      expect(gateway.cancelled, [gateway.opIds.single]);

      gateway.copyInError = const RelocationException(RelocationFailure.cancelled);
      gateway.copyGate!.complete();
      await expectLater(move, throwsA(predicate((e) => e is RelocationException && e.reason == RelocationFailure.cancelled)));
      expect(log.any((l) => l.startsWith('moveRecord')), isFalse);
    });

    test('cancel with nothing running does nothing', () async {
      await service.cancel();
      expect(gateway.cancelled, isEmpty);
    });

    test('cancel after the copy is done does not interrupt the switch-over', () async {
      records.gate = Completer<void>();
      final move = service.moveToAppStorage(uri: _external, displayName: 'a', isFolderVault: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(log, contains('moveRecord($_external -> $_internal)'));

      await service.cancel();
      expect(gateway.cancelled, isEmpty);

      records.gate!.complete();
      expect((await move).completed, isTrue);
    });
  });
}
