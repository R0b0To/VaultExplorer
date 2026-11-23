import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_repair.dart';
import 'package:vaultexplorer/core/engine/desktop/ve_native.dart' show veErrFailed, veOk;

// DesktopRepair is the Dart half of Check & Repair and the header backup tool: it maps method arguments onto the
// engine calls and every outcome onto the error codes `VaultRepairApi` already understands. The native half is
// covered by the engine's own tests (container_repair, fv_check) and the folder-vault section of ve_smoke_test; here
// a fake engine call stands in for it.

class _W {
  final BytesBuilder b = BytesBuilder();
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void str(String s) {
    final bytes = utf8.encode(s);
    u32(bytes.length);
    b.add(bytes);
  }

  Uint8List done() => b.toBytes();
}

/// A `ve_fv_check` / `ve_fv_repair` record.
Uint8List _folderRecord({
  int outcome = 0,
  String message = '',
  bool repair = false,
  int a = 0, // check: files scanned; repair: fixed
  int b = 0, // check: deep scan; repair: recovered
  int c = 0, // repair: removed
  List<(int, String, String)> issues = const [],
}) {
  final w = _W()
    ..u32(outcome)
    ..str(message);
  if (outcome == 0) {
    if (repair) {
      w
        ..u32(a)
        ..u32(b)
        ..u32(c);
    } else {
      w
        ..u32(a)
        ..u32(b);
    }
    w.u32(issues.length);
    for (final (sev, path, msg) in issues) {
      w
        ..u32(sev)
        ..str(path)
        ..str(msg);
    }
  }
  return w.done();
}

/// A `ve_header_export` record.
Uint8List _headerRecord(int result, int format, List<int> payload) {
  final w = _W()
    ..u32(result)
    ..u32(format)
    ..u32(payload.length);
  w.b.add(payload);
  return w.done();
}

class _FakeEngine {
  final List<(String, List<Object?>)> calls = [];
  Future<Object?> Function(String op, List<Object?> args)? handler;

  Future<Object?> call(String op, List<Object?> args) async {
    calls.add((op, args));
    return handler!(op, args);
  }
}

Matcher _code(String code) => throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));

void main() {
  group('FolderVaultRecord', () {
    test('a check record', () {
      final r = FolderVaultRecord.tryParse(
        _folderRecord(a: 12, b: 1, issues: [(1, '/a', 'odd'), (0, '/', 'fyi'), (2, '/b/c', 'broken')]),
        repair: false,
      )!;
      expect(r.outcome, 0);
      expect(r.filesScanned, 12);
      expect(r.deepScan, isTrue);
      expect(r.issues, [
        {'severity': 1, 'path': '/a', 'message': 'odd'},
        {'severity': 0, 'path': '/', 'message': 'fyi'},
        {'severity': 2, 'path': '/b/c', 'message': 'broken'},
      ]);
      expect(r.healthy, isFalse);
    });

    test('info entries do not make a vault unhealthy', () {
      final r = FolderVaultRecord.tryParse(_folderRecord(issues: [(0, '/', 'note')]), repair: false)!;
      expect(r.healthy, isTrue);
    });

    test('a repair record', () {
      final r = FolderVaultRecord.tryParse(
        _folderRecord(repair: true, a: 3, b: 2, c: 1, issues: [(1, '/x', 'still')]),
        repair: true,
      )!;
      expect((r.fixed, r.recovered, r.removed), (3, 2, 1));
      expect(r.issues.single['path'], '/x');
    });

    test('a refusal carries only the outcome and the message', () {
      final r = FolderVaultRecord.tryParse(_folderRecord(outcome: 2, message: 'not a vault'), repair: false)!;
      expect(r.outcome, 2);
      expect(r.message, 'not a vault');
      expect(r.issues, isEmpty);
    });

    test('a truncated record is rejected', () {
      final bytes = _folderRecord(a: 1, issues: [(1, '/a', 'odd')]);
      expect(FolderVaultRecord.tryParse(Uint8List.sublistView(bytes, 0, bytes.length - 2), repair: false), isNull);
    });
  });

  group('DesktopRepair', () {
    late _FakeEngine engine;
    late DesktopRepair repair;
    late Directory tmp;

    setUp(() {
      engine = _FakeEngine();
      tmp = Directory.systemTemp.createTempSync('ve_repair_test_');
      repair = DesktopRepair(
        call: engine.call,
        folderVaultStateDir: () async => '/state',
        tempDir: '/tmpdir',
        withActivity: (body) => body(),
      );
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    group('single-file containers', () {
      test('diagnose: the format ordinal becomes its wire name', () async {
        engine.handler = (op, args) async => [veOk, 1, 2];
        final res = await repair.diagnoseUnmounted({'uri': '/c.hc', 'opId': 9});
        expect(engine.calls.single.$1, 'repairDiagnoseFile');
        expect(engine.calls.single.$2, ['/c.hc', 9]);
        expect(res, {'diagnosisCode': 1, 'format': 'luks2'});

        engine.handler = (op, args) async => [veOk, 0, -1];
        expect((await repair.diagnoseUnmounted({'uri': '/c.hc'}))['format'], isNull);
        expect(engine.calls.last.$2, ['/c.hc', -1]); // the default op id: no live log

        engine.handler = (op, args) async => [veErrFailed, 1, -1];
        await expectLater(repair.diagnoseUnmounted({'uri': '/c.hc'}), _code('IO_ERROR'));
        await expectLater(repair.diagnoseUnmounted({}), _code('INVALID_ARGS'));
      });

      test('mounted volume: diagnose and check', () async {
        engine.handler = (op, args) async => op == 'repairCheckMounted' ? [veOk, true] : [veOk, 2];
        expect(await repair.diagnoseMounted({'volId': 3, 'opId': 4}), {'diagnosisCode': 2, 'format': null});
        expect(engine.calls.last.$2, [3, 4]);
        expect(await repair.runMountedCheck({'volId': 3}), isTrue);
        await expectLater(repair.diagnoseMounted({}), _code('INVALID_ARGS'));
        await expectLater(repair.runMountedCheck({}), _code('INVALID_ARGS'));
      });

      group('restoreBackupHeaderUnmounted', () {
        /// Probe answers [format]; the restore op answers [restore].
        void engineFor(int format, Object? restore) {
          engine.handler = (op, args) async => op == 'repairDiagnoseFile' ? [veOk, 1, format] : restore;
        }

        test('LUKS2 needs no password; a refusal is NOTHING_TO_REPAIR', () async {
          engineFor(2, veOk);
          expect(await repair.restoreBackupHeaderUnmounted({'uri': '/c.img', 'opId': 5}), isTrue);
          expect(engine.calls.last.$1, 'repairRestoreLuks2');
          expect(engine.calls.last.$2, ['/c.img', 5]);

          engineFor(2, veErrFailed);
          await expectLater(repair.restoreBackupHeaderUnmounted({'uri': '/c.img'}), _code('NOTHING_TO_REPAIR'));
        });

        test('VeraCrypt asks for a password first, and never calls the engine without one', () async {
          engineFor(0, [veOk, 0]);
          await expectLater(repair.restoreBackupHeaderUnmounted({'uri': '/c.hc'}), _code('PASSWORD_REQUIRED'));
          await expectLater(repair.restoreBackupHeaderUnmounted({'uri': '/c.hc', 'password': ''}), _code('PASSWORD_REQUIRED'));
          expect(engine.calls.where((c) => c.$1 == 'repairRestoreVeracrypt'), isEmpty);
        });

        test('VeraCrypt results: restored and already healthy are both success', () async {
          for (final result in [0, 2]) {
            engineFor(0, [veOk, result]);
            expect(await repair.restoreBackupHeaderUnmounted({'uri': '/c.hc', 'password': 'pw', 'pim': 5}), isTrue);
          }
          final args = engine.calls.last.$2;
          expect(args[0], '/c.hc');
          expect(args.sublist(2), [5, 255, 255, -1]); // pim, cipher and hash auto-detect, no op id
        });

        test('VeraCrypt: a wrong password and an I/O error are told apart; the password bytes are wiped', () async {
          engineFor(0, [veOk, 1]);
          await expectLater(
            repair.restoreBackupHeaderUnmounted({'uri': '/c.hc', 'password': 'pw'}),
            _code('PASSWORD_INCORRECT'),
          );
          final sent = engine.calls.last.$2[1] as Uint8List;
          expect(sent.every((b) => b == 0), isTrue);

          engineFor(0, [veOk, 3]);
          await expectLater(repair.restoreBackupHeaderUnmounted({'uri': '/c.hc', 'password': 'pw'}), _code('IO_ERROR'));
          engineFor(0, [veErrFailed, 3]);
          await expectLater(repair.restoreBackupHeaderUnmounted({'uri': '/c.hc', 'password': 'pw'}), _code('IO_ERROR'));
        });

        test('other formats, and an unrecognised file, are UNSUPPORTED_FORMAT', () async {
          for (final format in [1, 3, 4, -1]) {
            engineFor(format, veOk);
            await expectLater(repair.restoreBackupHeaderUnmounted({'uri': '/c'}), _code('UNSUPPORTED_FORMAT'));
          }
        });
      });
    });

    group('header backup', () {
      test('export returns the format wire name and the payload', () async {
        engine.handler = (op, args) async => [veOk, _headerRecord(0, 1, [1, 2, 3, 4])];
        final res = await repair.exportContainerHeader({'uri': '/c.img'});
        expect(res['format'], 'luks1');
        expect(res['bytes'], [1, 2, 3, 4]);
      });

      test('export errors keep their codes', () async {
        Future<void> expectResult(int result, String code) async {
          engine.handler = (op, args) async => [veOk, _headerRecord(result, 0xFFFFFFFF, const [])];
          await expectLater(repair.exportContainerHeader({'uri': '/c'}), _code(code));
        }

        await expectResult(1, 'UNRECOGNIZED_FILE');
        await expectResult(2, 'UNSUPPORTED_FORMAT');
        await expectResult(3, 'HEADER_UNREADABLE');
        await expectResult(4, 'IO_ERROR');
        engine.handler = (op, args) async => [veErrFailed, null];
        await expectLater(repair.exportContainerHeader({'uri': '/c'}), _code('IO_ERROR'));
      });

      test('restore: argument checks', () async {
        final base = {'uri': '/c', 'format': 'luks2', 'bytes': Uint8List.fromList([1])};
        await expectLater(repair.restoreContainerHeaderRegion({...base, 'bytes': Uint8List(0)}), _code('INVALID_ARGS'));
        await expectLater(repair.restoreContainerHeaderRegion({...base, 'format': 'bitlocker'}), _code('UNSUPPORTED_FORMAT'));
        // a VeraCrypt backup needs a password or at least one keyfile
        await expectLater(repair.restoreContainerHeaderRegion({...base, 'format': 'veracrypt'}), _code('PASSWORD_REQUIRED'));
        expect(engine.calls, isEmpty);
      });

      test('restore: arguments reach the engine, keyfile-only is allowed, the password is wiped', () async {
        engine.handler = (op, args) async => [veOk, 0];
        final payload = Uint8List.fromList([7, 8, 9]);
        expect(
          await repair.restoreContainerHeaderRegion({
            'uri': '/c.hc',
            'format': 'veracrypt',
            'bytes': payload,
            'password': 'pw',
            'pim': 3,
            'cipherId': 1,
            'hashId': 2,
            'keyfilePaths': ['/k1', '/k2'],
            'opId': 6,
          }),
          isTrue,
        );
        final (op, args) = engine.calls.single;
        expect(op, 'headerRestore');
        expect(args[0], '/c.hc');
        expect(args[1], 0); // veracrypt
        expect(args[2], payload);
        expect((args[3] as Uint8List).every((b) => b == 0), isTrue); // wiped after the call
        expect(args.sublist(4), [3, 1, 2, 6, ['/k1', '/k2']]);

        // keyfiles alone are enough
        expect(
          await repair.restoreContainerHeaderRegion({
            'uri': '/c.hc',
            'format': 'veracrypt',
            'bytes': payload,
            'keyfilePaths': ['/k1'],
          }),
          isTrue,
        );
        expect(engine.calls.last.$2[3], isNull);
      });

      test('restore: every native result keeps its error code', () async {
        final base = {'uri': '/c', 'format': 'luks2', 'bytes': Uint8List.fromList([1])};
        Future<void> expectResult(int result, String code) async {
          engine.handler = (op, args) async => [veOk, result];
          await expectLater(repair.restoreContainerHeaderRegion(base), _code(code));
        }

        await expectResult(1, 'PASSWORD_INCORRECT');
        await expectResult(2, 'BACKUP_INVALID');
        await expectResult(3, 'SIZE_MISMATCH');
        await expectResult(4, 'IO_ERROR');
        engine.handler = (op, args) async => [veErrFailed, 4]; // a file that would not open
        await expectLater(repair.restoreContainerHeaderRegion(base), _code('IO_ERROR'));
      });
    });

    group('folder vaults', () {
      test('check: arguments, and the report in the shape the Dart models read', () async {
        engine.handler = (op, args) async => [
              veOk,
              _folderRecord(a: 7, b: 1, issues: [(1, '/docs', 'odd name')]),
            ];
        final res = await repair.checkFolderVault({
          'uri': '/vaults/g',
          'format': 'gocryptfs',
          'password': 'pw',
          'volId': 2,
          'opId': 11,
        });
        final (op, args) = engine.calls.single;
        expect(op, 'fvCheck');
        expect(args[0], false); // check, not repair
        expect(args[1], 0); // gocryptfs
        expect(args[2], '/vaults/g');
        expect(args.sublist(4), [2, '/state', '/tmpdir', 11]);
        expect((args[3] as Uint8List).every((b) => b == 0), isTrue); // password wiped
        expect(res, {
          'format': 'gocryptfs',
          'healthy': false,
          'filesScanned': 7,
          'deepScanPerformed': true,
          'issues': [
            {'severity': 1, 'path': '/docs', 'message': 'odd name'},
          ],
        });
      });

      test('no password and no mounted volume: structure-only, slot -1', () async {
        engine.handler = (op, args) async => [veOk, _folderRecord(a: 1)];
        final res = await repair.checkFolderVault({'uri': '/v', 'format': 'cryfs'});
        expect(engine.calls.single.$2[1], 2);
        expect(engine.calls.single.$2[3], isNull);
        expect(engine.calls.single.$2[4], -1);
        expect(res['healthy'], isTrue);
        expect(res['deepScanPerformed'], isFalse);
      });

      test('the legacy directory_vault name is Cryptomator, and the report uses the canonical name', () async {
        engine.handler = (op, args) async => [veOk, _folderRecord()];
        final res = await repair.checkFolderVault({'uri': '/v', 'format': 'directory_vault'});
        expect(engine.calls.single.$2[1], 1);
        expect(res['format'], 'cryptomator');
      });

      test('repair: counts and what is still wrong', () async {
        engine.handler = (op, args) async => [
              veOk,
              _folderRecord(repair: true, a: 2, b: 1, c: 3, issues: [(2, '/x', 'gone')]),
            ];
        final res = await repair.repairFolderVault({'uri': '/v', 'format': 'cryptomator', 'password': 'pw'});
        expect(engine.calls.single.$2[0], true);
        expect(res, {
          'format': 'cryptomator',
          'fixedCount': 2,
          'recoveredCount': 1,
          'removedCount': 3,
          'remainingIssues': [
            {'severity': 2, 'path': '/x', 'message': 'gone'},
          ],
        });
      });

      test('outcomes: wrong password, not a vault, bad format, engine failure', () async {
        engine.handler = (op, args) async => [veOk, _folderRecord(outcome: 1)];
        await expectLater(repair.checkFolderVault({'uri': '/v', 'format': 'gocryptfs', 'password': 'x'}), _code('PASSWORD_INCORRECT'));
        engine.handler = (op, args) async => [veOk, _folderRecord(outcome: 2, message: 'nope')];
        await expectLater(repair.repairFolderVault({'uri': '/v', 'format': 'gocryptfs'}), _code('INVALID_VAULT'));
        await expectLater(repair.checkFolderVault({'uri': '/v', 'format': 'zip'}), _code('INVALID_VAULT'));
        await expectLater(repair.checkFolderVault({'uri': '/v'}), _code('INVALID_ARGS'));
        engine.handler = (op, args) async => [veErrFailed, null];
        await expectLater(repair.checkFolderVault({'uri': '/v', 'format': 'gocryptfs'}), _code('IO_ERROR'));
        engine.handler = (op, args) async => [veOk, Uint8List(2)];
        await expectLater(repair.checkFolderVault({'uri': '/v', 'format': 'gocryptfs'}), _code('IO_ERROR'));
      });

      group('config file', () {
        setUp(() {
          engine.handler = (op, args) async {
            if (op == 'fvConfigFileName') return const ['gocryptfs.conf', 'masterkey.cryptomator', 'cryfs.config'][args[0] as int];
            if (op == 'fvValidateConfig') return (args[1] as Uint8List).length > 3 ? null : 'too short to be a config';
            return null;
          };
        });

        test('resolve: the file name is always returned, the path only when the file exists', () async {
          final missing = await repair.resolveFolderVaultConfigFile({'uri': tmp.path, 'format': 'gocryptfs'});
          expect(missing, {'fileName': 'gocryptfs.conf', 'uri': null, 'exists': false});

          File(p.join(tmp.path, 'gocryptfs.conf')).writeAsStringSync('{}');
          final found = await repair.resolveFolderVaultConfigFile({'uri': tmp.path, 'format': 'gocryptfs'});
          expect(found['exists'], isTrue);
          expect(found['uri'], p.join(tmp.path, 'gocryptfs.conf'));

          await expectLater(
            repair.resolveFolderVaultConfigFile({'uri': tmp.path, 'format': 'veracrypt'}),
            _code('UNSUPPORTED_FORMAT'),
          );
        });

        test('restore: a config that does not validate writes nothing', () async {
          final existing = File(p.join(tmp.path, 'cryfs.config'))..writeAsStringSync('original');
          await expectLater(
            repair.restoreFolderVaultConfig({'uri': tmp.path, 'format': 'cryfs', 'bytes': Uint8List.fromList([1, 2])}),
            throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'BACKUP_INVALID').having((e) => e.message, 'message', contains('too short'))),
          );
          expect(existing.readAsStringSync(), 'original');
          expect(tmp.listSync().length, 1);
        });

        test('restore: a valid config replaces the vault\'s copy, creating it when missing, leaving nothing behind', () async {
          final bytes = Uint8List.fromList(utf8.encode('{"valid":true}'));
          await repair.restoreFolderVaultConfig({'uri': tmp.path, 'format': 'gocryptfs', 'bytes': bytes});
          expect(File(p.join(tmp.path, 'gocryptfs.conf')).readAsBytesSync(), bytes);

          File(p.join(tmp.path, 'masterkey.cryptomator')).writeAsStringSync('old');
          await repair.restoreFolderVaultConfig({'uri': tmp.path, 'format': 'cryptomator', 'bytes': bytes});
          expect(File(p.join(tmp.path, 'masterkey.cryptomator')).readAsBytesSync(), bytes);
          expect(tmp.listSync().map((e) => p.basename(e.path)).toSet(), {'gocryptfs.conf', 'masterkey.cryptomator'});
        });

        test('restore: argument checks', () async {
          await expectLater(repair.restoreFolderVaultConfig({'uri': tmp.path, 'format': 'gocryptfs'}), _code('INVALID_ARGS'));
          await expectLater(
            repair.restoreFolderVaultConfig({'uri': tmp.path, 'format': 'nope', 'bytes': Uint8List.fromList([1, 2, 3, 4])}),
            _code('UNSUPPORTED_FORMAT'),
          );
        });
      });
    });
  });
}
