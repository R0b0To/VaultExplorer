import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_archive.dart';
import 'package:vaultexplorer/core/engine/desktop/ve_native.dart' show veErrNotUnlocked, veOk;

// DesktopArchive is the Dart half of the engine channel's archive methods. The native half is covered by
// ve_archive_test (C++, real libarchive); here a fake engine call stands in for it, so these tests check what
// only Dart decides: how method arguments become engine calls, how the result record is decoded, and how the
// one plaintext file (browse staging) is created, guarded and cleaned up.

const String _container = '/vaults/a.hc';
const int _vol = 3;

class _Writer {
  final BytesBuilder b = BytesBuilder();
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void i32(int v) => b.add((ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List());
  void u64(int v) => b.add((ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List());
  void i64(int v) => b.add((ByteData(8)..setInt64(0, v, Endian.little)).buffer.asUint8List());
  void str(String s) {
    final bytes = utf8.encode(s);
    u32(bytes.length);
    b.add(bytes);
  }

  Uint8List done() => b.toBytes();
}

/// A record as `ve_archive_*` writes it (layout in ve_engine.h).
Uint8List _record({
  int status = 0,
  int flags = 0,
  int count = 0,
  String message = '',
  List<({String path, int size, int packed, int mtime, int entryFlags, int index})> entries = const [],
}) {
  final w = _Writer()
    ..u32(status)
    ..u32(flags)
    ..u32(entries.isEmpty ? count : entries.length)
    ..str(message);
  for (final e in entries) {
    w
      ..str(e.path)
      ..u64(e.size)
      ..u64(e.packed)
      ..i64(e.mtime)
      ..u32(e.entryFlags)
      ..i32(e.index);
  }
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

void main() {
  group('ArchiveRecord', () {
    test('decodes the head and every entry', () {
      final bytes = _record(
        flags: 3,
        message: 'note',
        entries: [
          (path: 'a/b.txt', size: 10, packed: 6, mtime: 1700000000, entryFlags: 1, index: 0),
          (path: 'a', size: 0, packed: 0, mtime: -5, entryFlags: 2, index: 7),
        ],
      );
      final r = ArchiveRecord.tryParse(bytes, withEntries: true)!;
      expect(r.status, 0);
      expect(r.isSolid, isTrue);
      expect(r.isSevenZip, isTrue);
      expect(r.cancelled, isFalse);
      expect(r.message, 'note');
      expect(r.entries, hasLength(2));
      expect(r.entries[0], {
        'path': 'a/b.txt',
        'uncompressedSize': 10,
        'compressedSize': 6,
        'modTimeEpochSeconds': 1700000000,
        'isEncrypted': true,
        'isDirectory': false,
        'index': 0,
      });
      expect(r.entries[1]['isDirectory'], isTrue);
      expect(r.entries[1]['modTimeEpochSeconds'], -5);
      expect(r.entries[1]['index'], 7);
    });

    test('non-ASCII names survive', () {
      final bytes = _record(
        entries: [(path: 'dossier/élan – 日本.txt', size: 1, packed: 1, mtime: 0, entryFlags: 0, index: 0)],
      );
      expect(ArchiveRecord.tryParse(bytes, withEntries: true)!.entries.single['path'], 'dossier/élan – 日本.txt');
    });

    test('the run flags: cancelled', () {
      expect(ArchiveRecord.tryParse(_record(flags: 4, count: 2))!.cancelled, isTrue);
      expect(ArchiveRecord.tryParse(_record(flags: 4, count: 2))!.count, 2);
    });

    test('a truncated record is rejected, not half-read', () {
      final bytes = _record(entries: [(path: 'x', size: 1, packed: 1, mtime: 0, entryFlags: 0, index: 0)]);
      expect(ArchiveRecord.tryParse(Uint8List.sublistView(bytes, 0, bytes.length - 3), withEntries: true), isNull);
      expect(ArchiveRecord.tryParse(Uint8List(5)), isNull);
    });
  });

  group('DesktopArchive', () {
    late _FakeEngine engine;
    late DesktopArchive archive;
    late List<int> registered;
    late List<int> unregistered;

    setUp(() {
      engine = _FakeEngine();
      registered = [];
      unregistered = [];
      archive = DesktopArchive(
        call: engine.call,
        volFor: (uri) {
          if (uri == _container) return _vol;
          throw PlatformException(code: 'NOT_MOUNTED', message: 'Container not mounted');
        },
        volOrNull: (uri) => uri == _container ? _vol : null,
        isFolderVault: (vol) => vol == _vol,
        registerOp: registered.add,
        unregisterOp: unregistered.add,
        withActivity: (body) => body(),
      );
    });

    tearDown(() async => archive.cleanupAll());

    group('scan', () {
      test('a vault archive: slot, vault path and passphrase reach the engine, entries come back as maps', () async {
        engine.handler = (op, args) async => [
              veOk,
              _record(
                flags: 1,
                entries: [(path: 'f.txt', size: 4, packed: 4, mtime: 9, entryFlags: 0, index: 0)],
              ),
            ];
        final res = await archive.scanVault({'filePath': _container, 'vaultPath': 'docs/a.zip', 'passphrase': ''});
        expect(engine.calls.single.$1, 'archiveScan');
        expect(engine.calls.single.$2, [_vol, 'docs/a.zip', null]); // an empty passphrase is "none"
        expect(res['status'], 0);
        expect(res['isSolid'], isTrue);
        expect(res['isSevenZip'], isFalse);
        expect((res['entries'] as List).single, containsPair('path', 'f.txt'));
      });

      test('a host archive: slot -1, and a file:// URI becomes a path', () async {
        engine.handler = (op, args) async => [veOk, _record()];
        await archive.scanLocal({'filePath': Uri.file('/home/me/a.7z').toString(), 'passphrase': 'pw'});
        expect(engine.calls.single.$2, [-1, Uri.file('/home/me/a.7z').toFilePath(), 'pw']);
      });

      test('scanVault needs a vault path; a locked container is NOT_MOUNTED', () async {
        expect(
          () => archive.scanVault({'filePath': _container}),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'INVALID_ARGS')),
        );
        expect(
          () => archive.scanVault({'filePath': '/vaults/other.hc', 'vaultPath': 'x.zip'}),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'NOT_MOUNTED')),
        );
      });

      test('the engine saying the slot is not unlocked becomes NOT_UNLOCKED', () async {
        engine.handler = (op, args) async => [veErrNotUnlocked, null];
        expect(
          () => archive.scanVault({'filePath': _container, 'vaultPath': 'x.zip'}),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'NOT_UNLOCKED')),
        );
      });

      test('an engine failure or an unreadable record is an I/O error result, not an exception', () async {
        engine.handler = (op, args) async => [5, null];
        final failed = await archive.scanLocal({'filePath': '/a.zip'});
        expect(failed['status'], 4);
        expect(failed['errorMessage'], isNotEmpty);
        engine.handler = (op, args) async => [veOk, Uint8List(3)];
        expect((await archive.scanLocal({'filePath': '/a.zip'}))['status'], 4);
      });

      test('passphrase statuses pass through unchanged', () async {
        engine.handler = (op, args) async => [veOk, _record(status: 2, message: 'needs a passphrase')];
        final res = await archive.scanLocal({'filePath': '/a.7z'});
        expect(res['status'], 2);
        expect(res['errorMessage'], 'needs a passphrase');
      });
    });

    group('single entries', () {
      test('into memory: bytes returned, an empty entry is an empty list, a failure carries no data', () async {
        engine.handler = (op, args) async => [veOk, _record(), Uint8List.fromList([1, 2, 3])];
        final res = await archive.extractVaultEntry({
          'filePath': _container,
          'vaultPath': 'a.zip',
          'targetIndex': 4,
          'passphrase': 'pw',
        });
        expect(engine.calls.single.$2, [_vol, 'a.zip', 4, 'pw', -1, null]);
        expect(res['data'], [1, 2, 3]);

        engine.handler = (op, args) async => [veOk, _record(), Uint8List(0)];
        expect((await archive.extractLocalEntry({'filePath': '/a.zip', 'targetIndex': 0}))['data'], isEmpty);

        engine.handler = (op, args) async => [veOk, _record(status: 3, message: 'wrong'), null];
        final bad = await archive.extractLocalEntry({'filePath': '/a.zip', 'targetIndex': 0});
        expect(bad['status'], 3);
        expect(bad.containsKey('data'), isFalse);
      });

      test('a target index is required', () {
        expect(
          () => archive.extractLocalEntry({'filePath': '/a.zip'}),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'INVALID_ARGS')),
        );
        expect(
          () => archive.extractLocalEntry({'filePath': '/a.zip', 'targetIndex': -1}),
          throwsA(isA<PlatformException>()),
        );
      });
    });

    group('browse staging', () {
      /// The engine stand-in: writes the staged file the way ve_archive_extract_entry would.
      void stagingEngine() {
        engine.handler = (op, args) async {
          final dest = args[5] as String?;
          if (dest != null) File(dest).writeAsBytesSync([9, 9, 9]);
          return [veOk, _record()];
        };
      }

      test('streams into a private archive_browse_ file with a safe name, and discards it', () async {
        stagingEngine();
        final res = await archive.stageBrowseEntry({
          'filePath': _container,
          'vaultPath': 'a.zip',
          'targetIndex': 2,
          'entryName': 'dir\\sub/we:ird?name.txt',
        });
        expect(res['status'], 0);
        final path = res['path'] as String;
        expect(p.basename(path), startsWith('archive_browse_'));
        expect(p.basename(path), endsWith('_we_ird_name.txt')); // directory part dropped, bad characters replaced
        expect(File(path).readAsBytesSync(), [9, 9, 9]);
        expect(engine.calls.single.$2.sublist(0, 5), [_vol, 'a.zip', 2, null, -1]);

        expect(await archive.discardBrowseFile(path), isTrue);
        expect(File(path).existsSync(), isFalse);
      });

      test('a failed extraction returns the status and leaves no file', () async {
        engine.handler = (op, args) async => [veOk, _record(status: 2, message: 'passphrase required')];
        final res = await archive.stageBrowseEntry({
          'filePath': '/a.7z',
          'targetIndex': 0,
          'entryName': 'x.bin',
        });
        expect(res['status'], 2);
        expect(res.containsKey('path'), isFalse);
      });

      test('only staged files can be discarded', () async {
        stagingEngine();
        final staged = (await archive.stageBrowseEntry({
          'filePath': '/a.zip',
          'targetIndex': 0,
          'entryName': 'x.bin',
        }))['path'] as String;

        final outside = File(p.join(Directory.systemTemp.createTempSync('ve_arch_test_').path, 'archive_browse_1_x'))
          ..writeAsBytesSync([1]);
        final ordinary = File(p.join(p.dirname(staged), 'not_staged.txt'))..writeAsBytesSync([1]);
        try {
          expect(await archive.discardBrowseFile(outside.path), isFalse); // right name, wrong folder
          expect(await archive.discardBrowseFile(ordinary.path), isFalse); // right folder, wrong name
          expect(await archive.discardBrowseFile('${p.dirname(staged)}/../archive_browse_x'), isFalse);
          expect(await archive.discardBrowseFile(null), isFalse);
          expect(await archive.discardBrowseFile(''), isFalse);
          expect(outside.existsSync() && ordinary.existsSync() && File(staged).existsSync(), isTrue);
        } finally {
          outside.parent.deleteSync(recursive: true);
          ordinary.deleteSync();
        }
      });

      test('locking a vault deletes what was staged from it, and only that', () async {
        stagingEngine();
        final fromVault = (await archive.stageBrowseEntry({
          'filePath': _container,
          'vaultPath': 'a.zip',
          'targetIndex': 0,
          'entryName': 'v.bin',
        }))['path'] as String;
        final fromHost = (await archive.stageBrowseEntry({
          'filePath': '/a.zip',
          'targetIndex': 0,
          'entryName': 'h.bin',
        }))['path'] as String;

        await archive.cleanupVolume(_vol);
        expect(File(fromVault).existsSync(), isFalse);
        expect(File(fromHost).existsSync(), isTrue);

        await archive.cleanupAll();
        expect(File(fromHost).existsSync(), isFalse);
      });
    });

    group('createArchive', () {
      Future<Object?> ok(String op, List<Object?> args) async => [veOk, _record(count: 1)];

      test('vault sources into the same vault: slots, vault paths and entry names reach the engine', () async {
        engine.handler = ok;
        final created = await archive.createArchive({
          'format': 0,
          'srcPaths': ['/data/a.txt', '/data/dir'],
          'entryNames': ['a.txt', 'dir/'],
          'modifiedSecs': [5, 0],
          'srcUri': _container,
          'destUri': _container,
          'destVaultPath': 'out/a.zip',
          'passphrase': 'pw',
          'compressionLevel': 6,
          'opId': 7,
        });
        expect(created, isTrue);
        final (op, args) = engine.calls.single;
        expect(op, 'archiveCreate');
        expect(args, [
          _vol,
          ['/data/a.txt', '/data/dir'],
          ['a.txt', 'dir/'],
          [5, 0],
          _vol,
          'out/a.zip',
          0,
          'pw',
          false,
          6,
          0,
          0,
          null, // a zip is not spooled: no temp folder
          7,
        ]);
        expect(registered, [7]);
        expect(unregistered, [7]);
      });

      test('host sources: relative paths are taken against srcUri, the host file is destFilePath', () async {
        engine.handler = ok;
        await archive.createArchive({
          'format': 3,
          'srcPaths': ['sub/a.txt', '/abs/b.txt'],
          'srcUri': '/home/me/docs',
          'destFilePath': '/home/me/out.tar.gz',
        });
        final args = engine.calls.single.$2;
        expect(args[0], -1);
        expect(args[1], [p.join('/home/me/docs', 'sub/a.txt'), '/abs/b.txt']);
        expect(args[2], ['a.txt', 'b.txt']); // default entry names: the last path segment
        expect(args[3], [0, 0]);
        expect(args[4], -1);
        expect(args[5], '/home/me/out.tar.gz');
      });

      test('a non-vault destUri is a folder for destVaultPath', () async {
        engine.handler = ok;
        await archive.createArchive({
          'format': 0,
          'srcPaths': ['/a.txt'],
          'destUri': '/home/me/dest',
          'destVaultPath': 'x/y.zip',
        });
        final args = engine.calls.single.$2;
        expect(args[4], -1);
        expect(args[5], p.join('/home/me/dest', 'x/y.zip'));
      });

      test('host sources into a vault', () async {
        engine.handler = ok;
        await archive.createArchive({
          'format': 0,
          'srcPaths': ['/a.txt'],
          'destUri': _container,
          'destVaultPath': 'in/a.zip',
        });
        final args = engine.calls.single.$2;
        expect(args[0], -1);
        expect(args[4], _vol);
        expect(args[5], 'in/a.zip');
      });

      test('split size, encrypted names and codec choice are passed on', () async {
        engine.handler = ok;
        await archive.createArchive({
          'format': 0,
          'srcPaths': ['/a.txt'],
          'destFilePath': '/o.zip',
          'splitSizeBytes': 65536,
          'compressionMethod': 1,
          'encryptFilenames': true,
          'passphrase': '',
        });
        final args = engine.calls.single.$2;
        expect(args.sublist(7, 12), [null, true, -1, 1, 65536]);
      });

      test('7z and ISO get a private spool folder for the call, removed afterwards', () async {
        for (final format in [1, 8]) {
          String? seen;
          var existedDuringCall = false;
          engine.handler = (op, args) async {
            seen = args[12] as String?;
            existedDuringCall = seen != null && Directory(seen!).existsSync();
            return [veOk, _record(count: 1)];
          };
          await archive.createArchive({'format': format, 'srcPaths': ['/a.txt'], 'destFilePath': '/o.bin'});
          expect(seen, isNotNull);
          expect(p.basename(seen!), startsWith('vaultexplorer-archive-'));
          expect(existedDuringCall, isTrue);
          expect(Directory(seen!).existsSync(), isFalse);
        }
      });

      test('the spool folder is removed and the op dropped even when the engine throws', () async {
        String? seen;
        engine.handler = (op, args) async {
          seen = args[12] as String?;
          throw StateError('worker died');
        };
        await expectLater(
          archive.createArchive({'format': 1, 'srcPaths': ['/a.txt'], 'destFilePath': '/o.7z', 'opId': 4}),
          throwsStateError,
        );
        expect(Directory(seen!).existsSync(), isFalse);
        expect(unregistered, [4]);
      });

      test('a failed archive answers false; a locked vault is an error', () async {
        engine.handler = (op, args) async => [veOk, _record(status: 4, message: 'no space')];
        expect(await archive.createArchive({'format': 0, 'srcPaths': ['/a'], 'destFilePath': '/o.zip'}), isFalse);

        engine.handler = (op, args) async => [veErrNotUnlocked, null];
        await expectLater(
          archive.createArchive({'format': 0, 'srcPaths': ['/a'], 'destFilePath': '/o.zip'}),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'NOT_UNLOCKED')),
        );
      });

      test('argument checks', () {
        void expectInvalid(Map<Object?, Object?> args) => expect(
              () => archive.createArchive(args),
              throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'INVALID_ARGS')),
            );
        expectInvalid({'format': 0, 'destFilePath': '/o.zip'}); // no sources
        expectInvalid({'format': 0, 'srcPaths': [], 'destFilePath': '/o.zip'});
        expectInvalid({
          'format': 0,
          'srcPaths': ['/a', '/b'],
          'entryNames': ['a'],
          'destFilePath': '/o.zip',
        });
        expectInvalid({
          'format': 0,
          'srcPaths': ['/a'],
          'modifiedSecs': [1, 2],
          'destFilePath': '/o.zip',
        });
        expectInvalid({'format': 0, 'srcPaths': ['/a']}); // no destination
      });
    });

    group('extractAll', () {
      test('into the same folder vault: write batch around the run, op registered, count returned', () async {
        engine.handler = (op, args) async => op == 'archiveExtractAll' ? [veOk, _record(count: 5)] : veOk;
        final res = await archive.extractAll({
          'filePath': _container,
          'vaultPath': 'in/a.zip',
          'destDirPath': 'out/dest',
          'subPath': 'dir',
          'passphrase': 'pw',
          'opId': 7,
        });
        expect(res, {'status': 0, 'extractedCount': 5, 'errorMessage': ''});
        expect(engine.calls.map((c) => c.$1), ['fvBatch', 'archiveExtractAll', 'fvBatch']);
        expect(engine.calls[0].$2, [_vol, 0, true]);
        expect(engine.calls[1].$2, [_vol, 'in/a.zip', 'pw', 'dir', _vol, 'out/dest', 7]);
        expect(engine.calls[2].$2, [_vol, 0, false]);
        expect(registered, [7]);
        expect(unregistered, [7]);
      });

      test('a host archive into a host folder, under destDirPath', () async {
        engine.handler = (op, args) async => [veOk, _record(count: 2)];
        await archive.extractAll({
          'filePath': '/home/me/a.zip',
          'destUri': '/home/me/dest',
          'destDirPath': 'sub',
        });
        expect(engine.calls.map((c) => c.$1), ['archiveExtractAll']); // no vault, no write batch
        expect(engine.calls.single.$2, [-1, '/home/me/a.zip', null, null, -1, p.join('/home/me/dest', 'sub'), 0]);
        expect(registered, isEmpty);
      });

      test('a host archive into a vault folder', () async {
        engine.handler = (op, args) async => op == 'archiveExtractAll' ? [veOk, _record(count: 1)] : veOk;
        await archive.extractAll({'filePath': '/home/me/a.zip', 'destUri': _container, 'destDirPath': 'x'});
        expect(engine.calls[1].$2, [-1, '/home/me/a.zip', null, null, _vol, 'x', 0]);
      });

      test('the write batch is closed and the op dropped even when the engine throws', () async {
        engine.handler = (op, args) async {
          if (op == 'archiveExtractAll') throw StateError('worker died');
          return veOk;
        };
        await expectLater(
          archive.extractAll({'filePath': _container, 'vaultPath': 'a.zip', 'destDirPath': '', 'opId': 9}),
          throwsStateError,
        );
        expect(engine.calls.last.$1, 'fvBatch');
        expect(engine.calls.last.$2, [_vol, 0, false]);
        expect(unregistered, [9]);
      });

      test('a cancelled run is still a normal result', () async {
        engine.handler = (op, args) async => op == 'archiveExtractAll' ? [veOk, _record(flags: 4, count: 3)] : veOk;
        final res = await archive.extractAll({'filePath': _container, 'vaultPath': 'a.zip', 'destDirPath': ''});
        expect(res['status'], 0);
        expect(res['extractedCount'], 3);
      });
    });
  });
}
