import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

MountedContainer _vault() => MountedContainer(
      uri: 'content://test-container',
      displayName: 'Test Vault',
      volId: 7,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1,
      freeSpace: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  const api = VaultBookApi(channel);

  final calls = <MethodCall>[];
  Object? nextResult;
  PlatformException? nextError;

  setUp(() {
    calls.clear();
    nextResult = null;
    nextError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (nextError != null) throw nextError!;
      return nextResult;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('open', () {
    test('a vault file is addressed by volume id and vault path', () async {
      nextResult = {'status': 'ok', 'token': 't1', 'entries': [], 'encrypted': false};

      await api.open(container: _vault(), path: '/Comics/a.cbz', kind: BookKind.comic);

      expect(calls.single.method, 'bookOpen');
      expect(calls.single.arguments['volId'], 7);
      expect(calls.single.arguments['vaultPath'], '/Comics/a.cbz');
      expect(calls.single.arguments['kind'], 'comic');
      expect(calls.single.arguments.containsKey('localPathOrUri'), isFalse);
    });

    test('a Local Storage file is addressed by its full path', () async {
      nextResult = {'status': 'ok', 'token': 't1', 'entries': []};
      final local = buildLocalStorageContainer(
        rootPath: '/storage/emulated/0',
        displayName: 'Internal',
      );

      await api.open(container: local, path: 'Books/b.epub', kind: BookKind.epub);

      expect(calls.single.arguments['localPathOrUri'], '/storage/emulated/0/Books/b.epub');
      expect(calls.single.arguments['kind'], 'epub');
      expect(calls.single.arguments.containsKey('volId'), isFalse);
    });

    test('parses a comic page list', () async {
      nextResult = {
        'status': 'ok',
        'token': 'abc',
        'entries': [
          {'name': '001.jpg', 'size': 10},
          {'name': '002.jpg', 'size': 20},
        ],
        'encrypted': true,
      };

      final r = await api.open(container: _vault(), path: 'a.cbz', kind: BookKind.comic);

      expect(r.status, BookOpenStatus.ok);
      expect(r.token, 'abc');
      expect(r.entries.map((e) => e.name), ['001.jpg', '002.jpg']);
      expect(r.entries.last.size, 20);
      expect(r.hasEncryptedEntries, isTrue);
      expect(r.epub, isNull);
    });

    test('parses an e-book package', () async {
      nextResult = {
        'status': 'ok',
        'token': 'abc',
        'epub': {
          'title': 'A Tale',
          'author': 'Ann',
          'language': 'en',
          'direction': 'rtl',
          'coverPath': 'OEBPS/c.jpg',
          'spine': [
            {'path': 'OEBPS/1.xhtml', 'linear': true},
            {'path': 'OEBPS/2.xhtml', 'linear': false},
          ],
          'toc': [
            {'title': 'One', 'path': 'OEBPS/1.xhtml', 'fragment': 's', 'level': 1},
          ],
        },
      };

      final r = await api.open(container: _vault(), path: 'a.epub', kind: BookKind.epub);

      final info = r.epub!;
      expect(info.title, 'A Tale');
      expect(info.direction, 'rtl');
      expect(info.spine.map((s) => s.path), ['OEBPS/1.xhtml', 'OEBPS/2.xhtml']);
      expect(info.spine.last.linear, isFalse);
      expect(info.toc.single.level, 1);
      expect(info.toc.single.fragment, 's');
    });

    test('a rejected file keeps its reason and offers no token', () async {
      for (final entry in {
        'notZip': BookOpenStatus.notZip,
        'encrypted': BookOpenStatus.encrypted,
        'unsupported': BookOpenStatus.unsupported,
        'tooLarge': BookOpenStatus.tooLarge,
        'corrupt': BookOpenStatus.corrupt,
        'invalid': BookOpenStatus.invalid,
      }.entries) {
        nextResult = {'status': entry.key};
        final r = await api.open(container: _vault(), path: 'a.cbz', kind: BookKind.comic);
        expect(r.status, entry.value, reason: entry.key);
        expect(r.token, isNull);
      }
    });

    test('only formats the archive browser may handle suggest falling back to it', () {
      expect(BookOpenStatus.notZip.archiveBrowserMayHelp, isTrue);
      expect(BookOpenStatus.encrypted.archiveBrowserMayHelp, isTrue);
      expect(BookOpenStatus.unsupported.archiveBrowserMayHelp, isTrue);
      expect(BookOpenStatus.corrupt.archiveBrowserMayHelp, isFalse);
      expect(BookOpenStatus.invalid.archiveBrowserMayHelp, isFalse);
      expect(BookOpenStatus.tooLarge.archiveBrowserMayHelp, isFalse);
    });

    test('an unknown status is treated as corrupt, never as ok', () {
      expect(BookOpenStatus.fromWire('something-new'), BookOpenStatus.corrupt);
      expect(BookOpenStatus.fromWire(null), BookOpenStatus.corrupt);
    });

    test('a platform error from native is not swallowed', () async {
      nextError = PlatformException(code: 'NOT_MOUNTED');
      expect(
        () => api.open(container: _vault(), path: 'a.cbz', kind: BookKind.comic),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('readEntry / close', () {
    test('readEntry returns the bytes for a token and entry name', () async {
      nextResult = Uint8List.fromList([1, 2, 3]);

      final bytes = await api.readEntry('tok', '001.jpg');

      expect(bytes, [1, 2, 3]);
      expect(calls.single.method, 'bookReadEntry');
      expect(calls.single.arguments, {'token': 'tok', 'name': '001.jpg'});
    });

    test('readEntry surfaces native errors', () {
      nextError = PlatformException(code: 'BOOK_ENCRYPTED');
      expect(
        () => api.readEntry('tok', 'x.jpg'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'BOOK_ENCRYPTED')),
      );
    });

    test('readEntry rejects an empty reply instead of returning null', () {
      nextResult = null;
      expect(() => api.readEntry('tok', 'x.jpg'), throwsA(isA<PlatformException>()));
    });

    test('close never throws, even if native does', () async {
      nextError = PlatformException(code: 'BOOM');
      await api.close('tok');
      expect(calls.single.method, 'bookClose');
    });
  });
}
