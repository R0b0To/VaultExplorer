import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_volume_tools.dart';
import 'package:vaultexplorer/core/engine/desktop/ve_native.dart' show veErrFailed, veOk;

// DesktopVolumeTools is the Dart half of the Volume tools screen (expand a container, grow its file system, add a
// hidden volume to an existing one): it maps method arguments onto the engine calls and every outcome onto the error
// codes and messages `VeraCryptToolsApi` already understands (the ones VeraCryptToolsHandlers.kt raises on Android).
// The native half is covered by the "tools" section of ve_smoke_test; here a fake engine call stands in for it.

class _FakeEngine {
  final List<(String, List<Object?>)> calls = [];
  Future<Object?> Function(String op, List<Object?> args)? handler;

  Future<Object?> call(String op, List<Object?> args) async {
    calls.add((op, args));
    return handler!(op, args);
  }

  /// Every call answers `[rc, result]`.
  void answer(int rc, Object? result) => handler = (op, args) async => [rc, result];
}

Matcher _code(String code, [String? message]) => throwsA(
      isA<PlatformException>().having((e) => e.code, 'code', code).having(
            (e) => e.message,
            'message',
            message == null ? isNotNull : equals(message),
          ),
    );

void main() {
  late _FakeEngine engine;
  late DesktopVolumeTools tools;

  setUp(() {
    engine = _FakeEngine();
    tools = DesktopVolumeTools(call: engine.call);
  });

  group('expand', () {
    test('VeraCrypt: arguments reach the engine, the success map names the file system step', () async {
      engine.answer(veOk, [0, 0, 8]); // outcome ok, file system grown, ext4
      final fileUri = Uri.file('/k/two'); // a file: URI is accepted wherever a path is
      final res = await tools.expand(VolumeToolKind.veracrypt, {
        'uri': '/data/c.hc',
        'password': 'pw',
        'pim': 7,
        'cipherId': 1,
        'hashId': 2,
        'keyfilePaths': ['/k/one', fileUri.toString()],
        'newSizeBytes': 1 << 30,
        'initFreeSpace': false,
        'growFileSystem': false,
      });
      expect(res, {'fsStatus': 'grown', 'fsName': 'ext4'});

      final (op, args) = engine.calls.single;
      expect(op, 'toolExpand');
      expect(args[0], 0); // VolumeToolKind.veracrypt
      expect(args[1], '/data/c.hc');
      expect(args.sublist(3), [
        7,
        1,
        2,
        ['/k/one', fileUri.toFilePath()],
        1 << 30,
        false,
        false,
      ]);
    });

    test('defaults match Android: auto-detect cipher and hash, free space initialised, file system grown', () async {
      engine.answer(veOk, [0, -1, 0]);
      await tools.expand(VolumeToolKind.luks, {'uri': '/c.img', 'password': 'pw', 'newSizeBytes': 10});
      var args = engine.calls.last.$2;
      expect(args[0], 1);
      expect(args.sublist(3), [0, 255, 255, <String>[], 10, true, true]);

      // BitLocker does not initialise the new space unless asked to
      await tools.expand(VolumeToolKind.bitlocker, {'uri': '/c.vhd', 'password': 'pw', 'newSizeBytes': 10});
      args = engine.calls.last.$2;
      expect(args[0], 2);
      expect(args[8], false);
    });

    test('a file system step that was not run, and an unknown kind, are reported as Android does', () async {
      engine.answer(veOk, [0, -1, 0]);
      expect(
        await tools.expand(VolumeToolKind.veracrypt, {'uri': '/c', 'password': 'p', 'newSizeBytes': 1}),
        {'fsStatus': 'not_run', 'fsName': ''},
      );
      for (final (code, name) in [
        (0, 'grown'),
        (1, 'already_fills'),
        (2, 'unsupported'),
        (3, 'needs_check'),
        (4, 'busy'),
        (5, 'failed'),
      ]) {
        expect(DesktopVolumeTools.fsStatusName(code), name);
      }
      expect(
        [for (var k = 0; k <= 9; k++) DesktopVolumeTools.fsKindName(k)],
        ['', 'FAT12', 'FAT16', 'FAT32', 'exFAT', 'NTFS', 'ext2', 'ext3', 'ext4', ''],
      );
    });

    test('argument checks never reach the engine', () async {
      const credentialMessage = 'uri, newSizeBytes and a password or keyfile are required';
      final ok = {'uri': '/c', 'password': 'pw', 'newSizeBytes': 5};
      await expectLater(tools.expand(VolumeToolKind.veracrypt, {...ok, 'uri': ''}), _code('INVALID_ARGS', credentialMessage));
      await expectLater(tools.expand(VolumeToolKind.veracrypt, {...ok}..remove('uri')), _code('INVALID_ARGS', credentialMessage));
      await expectLater(tools.expand(VolumeToolKind.veracrypt, {...ok, 'newSizeBytes': 0}), _code('INVALID_ARGS', credentialMessage));
      await expectLater(tools.expand(VolumeToolKind.luks, {...ok, 'password': ''}), _code('INVALID_ARGS', credentialMessage));
      await expectLater(
        tools.expand(VolumeToolKind.bitlocker, {...ok, 'password': ''}),
        _code('INVALID_ARGS', 'uri, newSizeBytes and a password or recovery key are required'),
      );
      expect(engine.calls, isEmpty);

      // a keyfile alone is a credential for VeraCrypt and LUKS, but never for BitLocker
      engine.answer(veOk, [0, 0, 5]);
      await tools.expand(VolumeToolKind.luks, {...ok, 'password': '', 'keyfilePaths': ['/k']});
      expect(engine.calls.single.$2[6], ['/k']);
      await expectLater(
        tools.expand(VolumeToolKind.bitlocker, {...ok, 'password': '', 'keyfilePaths': ['/k']}),
        _code('INVALID_ARGS'),
      );
    });

    test('the password is sent as UTF-8 and this side wipes its copy afterwards', () async {
      engine.answer(veOk, [0, 0, 5]);
      await tools.expand(VolumeToolKind.veracrypt, {'uri': '/c', 'password': 'pässword', 'newSizeBytes': 1});
      final sent = engine.calls.single.$2[2] as Uint8List;
      expect(sent.every((b) => b == 0), isTrue);

      // what was sent before the wipe: capture a copy inside the engine call
      List<int>? seen;
      engine.handler = (op, args) async {
        seen = List<int>.of(args[2] as Uint8List);
        return [veOk, [0, 0, 5]];
      };
      await tools.expand(VolumeToolKind.veracrypt, {'uri': '/c', 'password': 'pässword', 'newSizeBytes': 1});
      expect(seen, [0x70, 0xC3, 0xA4, 0x73, 0x73, 0x77, 0x6F, 0x72, 0x64]);
    });

    test('every engine outcome keeps its code and message', () async {
      Future<void> expectOutcome(VolumeToolKind kind, int outcome, String code, [String? message]) async {
        engine.answer(veOk, [outcome, -1, 0]);
        await expectLater(
          tools.expand(kind, {'uri': '/c', 'password': 'pw', 'newSizeBytes': 9}),
          _code(code, message),
        );
      }

      await expectOutcome(VolumeToolKind.veracrypt, 1, 'PASSWORD_INCORRECT', 'Incorrect password');
      await expectOutcome(
          VolumeToolKind.veracrypt, 2, 'NOT_EXPANDABLE', 'Only a standard volume that fills its container can be expanded.');
      await expectOutcome(
          VolumeToolKind.luks, 2, 'NOT_EXPANDABLE', 'This LUKS container uses an unsupported segment layout or inconsistent metadata.');
      await expectOutcome(VolumeToolKind.bitlocker, 2, 'NOT_EXPANDABLE');
      await expectOutcome(VolumeToolKind.veracrypt, 3, 'NOT_LARGER', 'The new size must be larger than the current size.');
      await expectOutcome(VolumeToolKind.veracrypt, 5, 'KEYFILE_ERROR', 'A keyfile could not be read.');
      await expectOutcome(VolumeToolKind.luks, 6, 'NOT_LUKS', 'The selected file is not a LUKS container.');
      await expectOutcome(VolumeToolKind.luks, 7, 'INVALID_HEADER', 'The LUKS header is damaged or unsupported.');
      await expectOutcome(VolumeToolKind.bitlocker, 7, 'INVALID_HEADER');
      await expectOutcome(
        VolumeToolKind.veracrypt,
        8,
        'CONTAINER_IN_USE',
        'Close the unlocked volume before expanding or growing its file system.',
      );
      await expectOutcome(VolumeToolKind.bitlocker, 9, 'NOT_BITLOCKER');
      await expectOutcome(VolumeToolKind.bitlocker, 10, 'DISK_UNSUPPORTED');
      await expectOutcome(VolumeToolKind.bitlocker, 11, 'PARTITION_UNSUPPORTED');
      await expectOutcome(VolumeToolKind.veracrypt, 4, 'IO_ERROR', 'Could not complete the volume operation (code 4)');
      await expectOutcome(VolumeToolKind.veracrypt, 99, 'IO_ERROR', 'Could not complete the volume operation (code 99)');
    });

    test('the BitLocker I/O message points at "Grow file system only"', () {
      final e = DesktopVolumeTools.expandFailure(VolumeToolKind.bitlocker, 4);
      expect(e.code, 'IO_ERROR');
      expect(e.message, contains('Grow file system only'));
      expect(DesktopVolumeTools.expandFailure(VolumeToolKind.luks, 4).message, isNot(contains('Grow file system only')));
    });

    test('a call that failed without an engine answer is an I/O error, never a success', () async {
      // the engine's own failure (exception / invalid argument) leaves the outcome at its default
      engine.answer(6, [4, -1, 0]);
      await expectLater(
        tools.expand(VolumeToolKind.veracrypt, {'uri': '/c', 'password': 'pw', 'newSizeBytes': 1}),
        _code('IO_ERROR'),
      );
      // an outcome of "ok" next to a failed call is not trusted
      engine.answer(6, [0, 0, 5]);
      await expectLater(
        tools.expand(VolumeToolKind.veracrypt, {'uri': '/c', 'password': 'pw', 'newSizeBytes': 1}),
        _code('IO_ERROR'),
      );
    });

    test('the worker failing to open the container, or a keyfile, is reported as such', () async {
      engine.answer(veErrFailed, [4, -1, 0]);
      await expectLater(
        tools.expand(VolumeToolKind.veracrypt, {'uri': '/missing', 'password': 'pw', 'newSizeBytes': 1}),
        _code('IO_ERROR', 'Could not open the container file.'),
      );
      engine.answer(veErrFailed, [5, -1, 0]);
      await expectLater(
        tools.expand(VolumeToolKind.veracrypt, {'uri': '/c', 'password': 'pw', 'newSizeBytes': 1, 'keyfilePaths': ['/nope']}),
        _code('KEYFILE_ERROR', 'A keyfile could not be read.'),
      );
    });
  });

  group('grow the file system only', () {
    test('VeraCrypt, LUKS and BitLocker take their own worker kind', () async {
      engine.answer(veOk, [0, 1, 5]);
      expect(
        await tools.growFileSystem(VolumeToolKind.veracrypt, {'uri': '/c', 'password': 'pw', 'pim': 3, 'keyfilePaths': ['/k']}),
        {'fsStatus': 'already_fills', 'fsName': 'NTFS'},
      );
      expect(engine.calls.last.$1, 'toolGrowFs');
      expect(engine.calls.last.$2, [0, '/c', isA<Uint8List>(), 3, 255, 255, ['/k']]);

      await tools.growFileSystem(VolumeToolKind.luks, {'uri': '/c', 'password': 'pw'});
      expect(engine.calls.last.$2[0], 1);
      await tools.growFileSystem(VolumeToolKind.bitlocker, {'uri': '/c', 'password': 'pw'});
      expect(engine.calls.last.$2[0], 2);
    });

    test('argument checks', () async {
      await expectLater(
        tools.growFileSystem(VolumeToolKind.veracrypt, {'uri': '/c'}),
        _code('INVALID_ARGS', 'uri and a password or keyfile are required'),
      );
      await expectLater(
        tools.growFileSystem(VolumeToolKind.bitlocker, {'uri': '/c', 'password': ''}),
        _code('INVALID_ARGS', 'uri and a password or recovery key are required'),
      );
      await expectLater(tools.growFileSystem(VolumeToolKind.luks, {'password': 'pw'}), _code('INVALID_ARGS'));
      expect(engine.calls, isEmpty);
    });

    test('outcomes map like an expand (a grow has no new size to refuse)', () async {
      engine.answer(veOk, [1, -1, 0]);
      await expectLater(tools.growFileSystem(VolumeToolKind.luks, {'uri': '/c', 'password': 'pw'}), _code('PASSWORD_INCORRECT'));
      engine.answer(veOk, [8, -1, 0]);
      await expectLater(tools.growFileSystem(VolumeToolKind.veracrypt, {'uri': '/c', 'password': 'pw'}), _code('CONTAINER_IN_USE'));
    });
  });

  group('hidden volume in an existing volume', () {
    test('analyze: the record becomes the wire map, arguments are checked', () async {
      engine.answer(veOk, [0, 5, 4096, 123456]);
      expect(
        await tools.analyzeHiddenHost({'uri': '/c.hc', 'password': 'pw', 'pim': 2, 'keyfilePaths': ['/k']}),
        {'fsKind': 5, 'clusterSize': 4096, 'maxHiddenBytes': 123456},
      );
      expect(engine.calls.single.$1, 'toolHiddenAnalyze');
      expect(engine.calls.single.$2, ['/c.hc', isA<Uint8List>(), 2, 255, 255, ['/k']]);

      await expectLater(
        tools.analyzeHiddenHost({'uri': '/c.hc'}),
        _code('INVALID_ARGS', 'uri and a password or keyfile are required'),
      );
    });

    test('analyze: every refusal keeps its code and message', () async {
      Future<void> expectOutcome(int outcome, String code, String message) async {
        engine.answer(veOk, [outcome, 0, 0, 0]);
        await expectLater(tools.analyzeHiddenHost({'uri': '/c', 'password': 'pw'}), _code(code, message));
      }

      await expectOutcome(1, 'PASSWORD_INCORRECT', 'Incorrect password');
      await expectOutcome(
        2,
        'UNSUPPORTED_FS',
        "The outer volume's file system must be FAT, exFAT or NTFS to host a hidden volume.",
      );
      await expectOutcome(5, 'KEYFILE_ERROR', 'A keyfile could not be read.');
      await expectOutcome(
        6,
        'INVALID_VOLUME',
        'Only a standard volume that fills its container can host a hidden volume, and the hidden password must differ from the outer one.',
      );
      await expectOutcome(4, 'IO_ERROR', 'Operation failed (code 4)');

      engine.answer(6, [4, 0, 0, 0]);
      await expectLater(tools.analyzeHiddenHost({'uri': '/c', 'password': 'pw'}), _code('IO_ERROR', 'Analysis failed'));
      engine.answer(veErrFailed, [5, 0, 0, 0]);
      await expectLater(tools.analyzeHiddenHost({'uri': '/c', 'password': 'pw', 'keyfilePaths': ['/x']}), _code('KEYFILE_ERROR'));
      engine.answer(veErrFailed, [4, 0, 0, 0]);
      await expectLater(
        tools.analyzeHiddenHost({'uri': '/missing', 'password': 'pw'}),
        _code('IO_ERROR', 'Could not open the container file.'),
      );
    });

    test('create: arguments reach the engine and success is true', () async {
      engine.answer(veOk, 0);
      final ok = await tools.createHiddenInExisting({
        'uri': '/c.hc',
        'outerPassword': 'outer',
        'outerPim': 1,
        'outerCipherId': 3,
        'outerHashId': 4,
        'outerKeyfilePaths': ['/ok'],
        'hiddenPassword': 'inner',
        'hiddenPim': 2,
        'hiddenFileSystem': 'NTFS',
        'hiddenSizeBytes': 50 << 20,
        'hiddenCipherId': 0,
        'hiddenHashId': 0,
        'hiddenKeyfilePaths': ['/hk'],
        'quickFormat': true,
        'userEntropy': Uint8List.fromList([1, 2, 3]),
      });
      expect(ok, isTrue);
      final (op, args) = engine.calls.single;
      expect(op, 'toolHiddenCreate');
      expect(args[0], '/c.hc');
      expect(args.sublist(2, 6), [1, 3, 4, ['/ok']]);
      expect(args.sublist(7), [2, 'NTFS', 50 << 20, 0, 0, ['/hk'], true, isA<Uint8List>()]);
    });

    test('create: defaults follow Android (exFAT, auto-detect, full format)', () async {
      engine.answer(veOk, 0);
      await tools.createHiddenInExisting({
        'uri': '/c',
        'outerPassword': 'o',
        'hiddenPassword': 'h',
        'hiddenSizeBytes': 1,
      });
      final args = engine.calls.single.$2;
      expect(args.sublist(7), [0, 'exFAT', 1, 255, 255, <String>[], false, null]);
    });

    test('create: argument checks never reach the engine', () async {
      final ok = {'uri': '/c', 'outerPassword': 'o', 'hiddenPassword': 'h', 'hiddenSizeBytes': 1};
      const message = 'uri, hiddenSizeBytes and passwords/keyfiles are required';
      await expectLater(tools.createHiddenInExisting({...ok, 'uri': ''}), _code('INVALID_ARGS', message));
      await expectLater(tools.createHiddenInExisting({...ok, 'hiddenSizeBytes': 0}), _code('INVALID_ARGS', message));
      await expectLater(tools.createHiddenInExisting({...ok, 'outerPassword': ''}), _code('INVALID_ARGS', message));
      await expectLater(tools.createHiddenInExisting({...ok, 'hiddenPassword': ''}), _code('INVALID_ARGS', message));
      expect(engine.calls, isEmpty);

      // a keyfile can stand in for either password
      engine.answer(veOk, 0);
      expect(await tools.createHiddenInExisting({...ok, 'hiddenPassword': '', 'hiddenKeyfilePaths': ['/k']}), isTrue);
    });

    test('create: outcomes and secret wiping', () async {
      Future<void> expectOutcome(int outcome, String code) async {
        engine.answer(veOk, outcome);
        await expectLater(
          tools.createHiddenInExisting({'uri': '/c', 'outerPassword': 'o', 'hiddenPassword': 'h', 'hiddenSizeBytes': 1}),
          _code(code),
        );
      }

      await expectOutcome(1, 'PASSWORD_INCORRECT');
      await expectOutcome(2, 'UNSUPPORTED_FS');
      await expectOutcome(3, 'NO_SPACE');
      await expectOutcome(4, 'IO_ERROR');
      await expectOutcome(5, 'KEYFILE_ERROR');
      await expectOutcome(6, 'INVALID_VOLUME');

      engine.answer(veErrFailed, 4);
      await expectLater(
        tools.createHiddenInExisting({'uri': '/missing', 'outerPassword': 'o', 'hiddenPassword': 'h', 'hiddenSizeBytes': 1}),
        _code('IO_ERROR', 'Could not open the container file.'),
      );
      // a failed call with a stale "ok" outcome is not a success
      engine.answer(6, 0);
      await expectLater(
        tools.createHiddenInExisting({'uri': '/c', 'outerPassword': 'o', 'hiddenPassword': 'h', 'hiddenSizeBytes': 1}),
        _code('IO_ERROR'),
      );

      // both password copies and the entropy are wiped on this side
      engine.answer(veOk, 0);
      final entropy = Uint8List.fromList([9, 9, 9]);
      await tools.createHiddenInExisting({
        'uri': '/c',
        'outerPassword': 'o',
        'hiddenPassword': 'h',
        'hiddenSizeBytes': 1,
        'userEntropy': entropy,
      });
      final args = engine.calls.last.$2;
      expect((args[1] as Uint8List).every((b) => b == 0), isTrue);
      expect((args[6] as Uint8List).every((b) => b == 0), isTrue);
      expect((args[14] as Uint8List).every((b) => b == 0), isTrue);
      expect(entropy, [9, 9, 9]); // the caller's own buffer is not touched
    });
  });
}
