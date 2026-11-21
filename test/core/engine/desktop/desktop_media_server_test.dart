import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_media_server.dart';

/// 1000 bytes of a pattern that makes an off-by-one visible.
final Uint8List _data = Uint8List.fromList(List<int>.generate(1000, (i) => i % 251));

class _Fixture {
  _Fixture({int chunk = 64, this.failAfterReads}) {
    server = DesktopMediaServer(
      chunkBytes: chunk,
      sizeOf: (vol, path) async {
        if (vol != 7 || path != 'dir/holiday movie.MKV') return -1;
        return _data.length;
      },
      readRange: (vol, path, offset, length) async {
        reads.add(length);
        final limit = failAfterReads;
        if (limit != null && reads.length > limit) return null;
        if (offset >= _data.length) return Uint8List(0);
        final end = (offset + length).clamp(0, _data.length);
        return Uint8List.fromList(_data.sublist(offset, end));
      },
    );
  }

  late final DesktopMediaServer server;
  final List<int> reads = [];
  final int? failAfterReads;
  final HttpClient client = HttpClient();

  Future<DesktopMediaSession> open() => server.open(volId: 7, filePath: 'dir/holiday movie.MKV');

  Future<({int status, Uint8List body, HttpHeaders headers})> get(
    String url, {
    String method = 'GET',
    String? range,
    String? host,
  }) async {
    final req = await client.openUrl(method, Uri.parse(url));
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    if (host != null) req.headers.host = host;
    final res = await req.close();
    final bytes = BytesBuilder(copy: false);
    await for (final c in res) {
      bytes.add(c);
    }
    return (status: res.statusCode, body: bytes.takeBytes(), headers: res.headers);
  }

  Future<void> dispose() async {
    client.close(force: true);
    await server.closeAll();
  }
}

void main() {
  group('parseByteRange', () {
    test('absent or unusable headers mean "serve everything"', () {
      expect(parseByteRange(null, 100), isNull);
      expect(parseByteRange('items=0-5', 100), isNull);
      expect(parseByteRange('bytes=0-5,10-15', 100), isNull);
      expect(parseByteRange('bytes=-', 100), isNull);
      expect(parseByteRange('bytes=9-3', 100), isNull);
      expect(parseByteRange('garbage', 100), isNull);
    });

    test('closed, open-ended and suffix ranges are clamped to the file', () {
      expect(parseByteRange('bytes=0-9', 100), const ByteRange(0, 9));
      expect(parseByteRange('bytes=90-', 100), const ByteRange(90, 99));
      expect(parseByteRange('bytes=90-500', 100), const ByteRange(90, 99));
      expect(parseByteRange('bytes=-10', 100), const ByteRange(90, 99));
      expect(parseByteRange('bytes=-500', 100), const ByteRange(0, 99));
      expect(parseByteRange(' bytes = 5 - 6 ', 100), const ByteRange(5, 6));
    });

    test('a range that starts past the end is unsatisfiable', () {
      expect(parseByteRange('bytes=100-', 100), ByteRange.unsatisfiable);
      expect(parseByteRange('bytes=-0', 100), ByteRange.unsatisfiable);
      expect(parseByteRange('bytes=0-', 0), ByteRange.unsatisfiable);
    });
  });

  group('DesktopMediaServer', () {
    late _Fixture f;
    setUp(() => f = _Fixture());
    tearDown(() => f.dispose());

    test('listens only while a session is open', () async {
      expect(f.server.isListening, isFalse);
      final s = await f.open();
      expect(f.server.isListening, isTrue);
      await s.close();
      expect(f.server.isListening, isFalse);
      expect(f.server.activeSessionCount, 0);
    });

    test('the URL is loopback, carries a 128-bit token and hides the file name', () async {
      final s = await f.open();
      final uri = Uri.parse(s.url);
      expect(uri.host, '127.0.0.1');
      expect(uri.pathSegments.length, 2);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(uri.pathSegments[0]), isTrue);
      expect(uri.pathSegments[1], 'video.mkv');
      expect(s.url.contains('holiday'), isFalse);
      final other = await f.open();
      expect(other.url == s.url, isFalse);
    });

    test('a plain GET returns the whole file in 200 with range support advertised', () async {
      final s = await f.open();
      final r = await f.get(s.url);
      expect(r.status, 200);
      expect(r.body, _data);
      expect(r.headers.value('accept-ranges'), 'bytes');
      expect(r.headers.value('cache-control'), 'no-store');
      expect(r.headers.value('content-type'), 'video/x-matroska');
    });

    test('streams in chunks no larger than chunkBytes', () async {
      final s = await f.open();
      await f.get(s.url);
      expect(f.reads.isNotEmpty, isTrue);
      expect(f.reads.every((n) => n <= 64), isTrue);
    });

    test('a closed range is a 206 with Content-Range', () async {
      final s = await f.open();
      final r = await f.get(s.url, range: 'bytes=10-199');
      expect(r.status, 206);
      expect(r.body, _data.sublist(10, 200));
      expect(r.headers.value('content-range'), 'bytes 10-199/1000');
      expect(r.headers.contentLength, 190);
    });

    test('open-ended and suffix ranges', () async {
      final s = await f.open();
      final tail = await f.get(s.url, range: 'bytes=990-');
      expect(tail.status, 206);
      expect(tail.body, _data.sublist(990));
      final suffix = await f.get(s.url, range: 'bytes=-5');
      expect(suffix.status, 206);
      expect(suffix.body, _data.sublist(995));
      expect(suffix.headers.value('content-range'), 'bytes 995-999/1000');
    });

    test('a range past the end is 416 with the size', () async {
      final s = await f.open();
      final r = await f.get(s.url, range: 'bytes=1000-');
      expect(r.status, 416);
      expect(r.headers.value('content-range'), 'bytes */1000');
      expect(r.body.isEmpty, isTrue);
    });

    test('HEAD answers with headers and no body, and reads nothing', () async {
      final s = await f.open();
      final r = await f.get(s.url, method: 'HEAD');
      expect(r.status, 200);
      expect(r.body.isEmpty, isTrue);
      expect(r.headers.contentLength, 1000);
      expect(f.reads.isEmpty, isTrue);
    });

    test('unknown tokens, other methods and foreign Host headers are refused', () async {
      final s = await f.open();
      final uri = Uri.parse(s.url);
      final wrongToken = uri.replace(pathSegments: ['0' * 32, 'video.mkv']).toString();
      expect((await f.get(wrongToken)).status, 404);
      expect((await f.get(s.url, method: 'POST')).status, 405);
      expect((await f.get(s.url, host: 'evil.example')).status, 403);
      expect((await f.get(uri.replace(pathSegments: [uri.pathSegments[0]]).toString())).status, 404);
    });

    test('a file the engine cannot size is a 404', () async {
      final s = await f.server.open(volId: 7, filePath: 'missing.mp4');
      expect((await f.get(s.url)).status, 404);
    });

    test('closing one session leaves the others working', () async {
      final a = await f.open();
      final b = await f.open();
      await a.close();
      expect(a.isClosed, isTrue);
      expect((await f.get(b.url)).status, 200);
      expect(f.server.isListening, isTrue);
    });

    test('closeVolume ends only that volume\'s sessions', () async {
      final a = await f.open();
      final other = await f.server.open(volId: 9, filePath: 'x.mp4');
      await f.server.closeVolume(7);
      expect(a.isClosed, isTrue);
      expect(other.isClosed, isFalse);
      await f.server.closeVolume(9);
      expect(f.server.isListening, isFalse);
    });

    test('a read failure mid-stream cuts the connection instead of ending cleanly', () async {
      final broken = _Fixture(failAfterReads: 2);
      addTearDown(broken.dispose);
      final s = await broken.open();
      Object? error;
      var received = 0;
      try {
        final req = await broken.client.getUrl(Uri.parse(s.url));
        final res = await req.close();
        await for (final c in res) {
          received += c.length;
        }
      } on Object catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(received < _data.length, isTrue);
    });
  });
}
