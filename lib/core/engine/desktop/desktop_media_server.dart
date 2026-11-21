// Streams decrypted vault files to the desktop video player over a loopback HTTP socket.
//
// Why this exists: the desktop player (libmpv, see desktop_video_backend.dart) needs something to read from, and
// Android's equivalent (a Media3 DataSource over the JNI engine) has no desktop counterpart. Writing a decrypted
// copy to disk would defeat the vault, so the bytes travel over `127.0.0.1` instead and never touch storage:
//
//   libmpv --HTTP Range--> this server --pool.call('read')--> engine (decrypts) --> bytes
//
// Hardening, because anything listening on a TCP port is reachable by every local process:
//   * bound to the loopback interface only, on a random port, and only while a session is open;
//   * every session has its own unguessable 128-bit token in the URL path; an unknown token is a bare 404;
//   * the Host header must be exactly 127.0.0.1:<port> or localhost:<port> (DNS-rebinding defence);
//   * GET / HEAD only, no CORS headers, `Cache-Control: no-store`;
//   * a session ends when the player closes it, when its vault locks ([closeVolume]) or at app exit
//     ([closeAll]); an in-flight response is cut off at the next chunk boundary.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Size of the vault file at [path] in volume [vol], or a negative number when it cannot be read.
typedef MediaSizeProbe = Future<int> Function(int vol, String path);

/// Up to [length] bytes of [path] starting at [offset]; null or empty on failure or end of file.
typedef MediaRangeReader = Future<Uint8List?> Function(int vol, String path, int offset, int length);

/// One open file. [url] is what the player is given.
class DesktopMediaSession {
  DesktopMediaSession._(this._server, this.token, this.volId, this.filePath, this.url);

  final DesktopMediaServer _server;
  final String token;
  final int volId;
  final String filePath;
  final String url;

  bool get isClosed => !_server._entries.containsKey(token);

  /// Ends the session; its URL stops working at once. Safe to call twice.
  Future<void> close() => _server._release(token);
}

class DesktopMediaServer {
  DesktopMediaServer({
    required this.sizeOf,
    required this.readRange,
    this.chunkBytes = 1 << 20,
    math.Random? random,
  })  : assert(chunkBytes > 0),
        _random = random ?? math.Random.secure();

  final MediaSizeProbe sizeOf;
  final MediaRangeReader readRange;

  /// Bytes read from the engine per step while streaming a response.
  final int chunkBytes;

  final math.Random _random;
  final Map<String, _Entry> _entries = {};
  HttpServer? _server;
  Future<HttpServer>? _starting;

  /// Open sessions; the socket is only listening while this is above zero.
  int get activeSessionCount => _entries.length;

  /// Whether the loopback socket is currently open (false whenever no session is).
  bool get isListening => _server != null;

  /// The port while listening, for tests and diagnostics.
  int? get port => _server?.port;

  /// Registers [filePath] of volume [volId] and returns the session carrying its URL.
  Future<DesktopMediaSession> open({required int volId, required String filePath}) async {
    final server = await _ensureServer();
    final token = _newToken();
    final url = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: [token, 'video${_safeExtension(filePath)}'],
    ).toString();
    _entries[token] = _Entry(volId, filePath);
    return DesktopMediaSession._(this, token, volId, filePath, url);
  }

  /// Ends every session reading from [volId] (the vault is being locked or went away).
  Future<void> closeVolume(int volId) async {
    final tokens = [
      for (final e in _entries.entries)
        if (e.value.volId == volId) e.key,
    ];
    for (final t in tokens) {
      await _release(t);
    }
  }

  /// Ends every session and closes the socket (app exit).
  Future<void> closeAll() async {
    for (final t in _entries.keys.toList()) {
      await _release(t);
    }
    await _stopIfIdle();
  }

  Future<void> _release(String token) async {
    final entry = _entries.remove(token);
    if (entry == null) return;
    entry.closed = true;
    await _stopIfIdle();
  }

  Future<void> _stopIfIdle() async {
    if (_entries.isNotEmpty) return;
    final starting = _starting;
    final server = _server;
    _server = null;
    _starting = null;
    if (server != null) {
      await server.close(force: true);
    } else if (starting != null) {
      // Closed while still binding: shut the socket that is about to appear.
      try {
        await (await starting).close(force: true);
      } on Object {
        // never bound; nothing to close
      }
    }
  }

  Future<HttpServer> _ensureServer() {
    final existing = _server;
    if (existing != null) return Future.value(existing);
    return _starting ??= () async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen(_handle, onError: (Object _) {}, cancelOnError: false);
      _server = s;
      return s;
    }();
  }

  String _newToken() {
    final sb = StringBuffer();
    for (var i = 0; i < 16; i++) {
      sb.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  // ── request handling ────────────────────────────────────────────────────

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      response.headers
        ..set('Cache-Control', 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');

      final method = request.method;
      if (method != 'GET' && method != 'HEAD') {
        response.headers.set('Allow', 'GET, HEAD');
        await _fail(response, HttpStatus.methodNotAllowed);
        return;
      }
      if (!_hostAllowed(request)) {
        await _fail(response, HttpStatus.forbidden);
        return;
      }

      final segments = request.uri.pathSegments;
      final entry = segments.isEmpty ? null : _entries[segments.first];
      if (entry == null || entry.closed || segments.length != 2) {
        await _fail(response, HttpStatus.notFound);
        return;
      }

      final size = await sizeOf(entry.volId, entry.path);
      if (size < 0 || entry.closed) {
        await _fail(response, HttpStatus.notFound);
        return;
      }

      final range = parseByteRange(request.headers.value(HttpHeaders.rangeHeader), size);
      response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.contentTypeHeader, contentTypeFor(entry.path));

      if (range == ByteRange.unsatisfiable) {
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        await _fail(response, HttpStatus.requestedRangeNotSatisfiable);
        return;
      }

      final int start;
      final int length;
      if (range == null) {
        start = 0;
        length = size;
        response.statusCode = HttpStatus.ok;
      } else {
        start = range.start;
        length = range.end - range.start + 1;
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-${range.end}/$size');
      }
      response.contentLength = length;

      if (method == 'HEAD' || length == 0) {
        await response.close();
        return;
      }
      await _stream(entry, response, start, length);
    } on Object {
      // The peer went away or the engine failed in a way nothing can be told about any more.
      await _abort(response);
    }
  }

  /// Copies `[start, start + length)` to [response], reading the next chunk while the current one is written.
  Future<void> _stream(_Entry entry, HttpResponse response, int start, int length) async {
    var pos = start;
    var remaining = length;
    Future<Uint8List?> pending = _readChunk(entry, pos, math.min(chunkBytes, remaining));
    while (remaining > 0) {
      final data = await pending;
      if (data == null || data.isEmpty || entry.closed) {
        // Short of the promised Content-Length: cut the connection so the player sees a failure rather
        // than a silently truncated, apparently complete, file.
        await _abort(response);
        return;
      }
      final take = math.min(data.length, remaining);
      pos += take;
      remaining -= take;
      if (remaining > 0) pending = _readChunk(entry, pos, math.min(chunkBytes, remaining));
      response.add(take == data.length ? data : Uint8List.sublistView(data, 0, take));
      await response.flush();
    }
    await response.close();
  }

  Future<Uint8List?> _readChunk(_Entry entry, int offset, int length) async {
    try {
      return await readRange(entry.volId, entry.path, offset, length);
    } on Object {
      return null;
    }
  }

  bool _hostAllowed(HttpRequest request) {
    final server = _server;
    if (server == null) return false;
    final host = request.headers.host;
    final port = request.headers.port;
    return (host == '127.0.0.1' || host == 'localhost') && port == server.port;
  }

  Future<void> _fail(HttpResponse response, int status) async {
    response.statusCode = status;
    response.contentLength = 0;
    await response.close();
  }

  /// Ends a response that cannot be completed. Closing it short of its Content-Length makes dart:io fail
  /// the response and destroy the connection, so the player sees an error, not a plausible short file.
  /// (`detachSocket` cannot do this once headers have gone out, which is the usual case mid-stream.)
  Future<void> _abort(HttpResponse response) async {
    try {
      await response.close();
    } on Object {
      // expected: "content size below specified contentLength"; the connection is torn down by dart:io
    }
  }
}

class _Entry {
  _Entry(this.volId, this.path);
  final int volId;
  final String path;
  bool closed = false;
}

/// An inclusive byte range, already clamped to the entity size.
class ByteRange {
  const ByteRange(this.start, this.end);
  final int start;
  final int end;

  /// Returned by [parseByteRange] for a range that starts past the end of the entity.
  static const ByteRange unsatisfiable = ByteRange(-1, -1);

  @override
  bool operator ==(Object other) => other is ByteRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ByteRange($start-$end)';
}

/// Parses an HTTP `Range` header value for an entity of [size] bytes.
///
/// Returns null when the header is absent or not a single `bytes` range (the caller then serves the whole
/// entity, which RFC 9110 allows), [ByteRange.unsatisfiable] when no byte of it exists, otherwise the
/// clamped range. Supports `a-b`, `a-` and the suffix form `-n`.
ByteRange? parseByteRange(String? header, int size) {
  if (header == null) return null;
  final m = RegExp(r'^\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)\s*$').firstMatch(header);
  if (m == null) return null; // other units, multiple ranges, garbage: ignore the header
  final a = m.group(1)!;
  final b = m.group(2)!;
  if (a.isEmpty && b.isEmpty) return null;
  if (a.isEmpty) {
    final n = int.tryParse(b);
    if (n == null) return null;
    if (n == 0 || size == 0) return ByteRange.unsatisfiable;
    return ByteRange(math.max(0, size - n), size - 1);
  }
  final start = int.tryParse(a);
  if (start == null) return null;
  if (start >= size) return ByteRange.unsatisfiable;
  var end = size - 1;
  if (b.isNotEmpty) {
    final e = int.tryParse(b);
    if (e == null) return null;
    if (e < start) return null; // invalid per RFC: ignore the header
    end = math.min(e, size - 1);
  }
  return ByteRange(start, end);
}

String _safeExtension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return '';
  final ext = path.substring(dot + 1).toLowerCase();
  if (ext.length > 8 || !RegExp(r'^[a-z0-9]+$').hasMatch(ext)) return '';
  return '.$ext';
}

/// MIME type for [path] by extension; libmpv sniffs the content anyway, this only keeps the headers honest.
String contentTypeFor(String path) {
  switch (_safeExtension(path)) {
    case '.mp4':
    case '.m4v':
      return 'video/mp4';
    case '.mov':
      return 'video/quicktime';
    case '.mkv':
    case '.mk3d':
      return 'video/x-matroska';
    case '.webm':
      return 'video/webm';
    case '.avi':
      return 'video/x-msvideo';
    case '.ts':
    case '.m2ts':
    case '.mts':
      return 'video/mp2t';
    case '.mpg':
    case '.mpeg':
      return 'video/mpeg';
    case '.wmv':
      return 'video/x-ms-wmv';
    case '.flv':
      return 'video/x-flv';
    case '.3gp':
      return 'video/3gpp';
    case '.ogv':
      return 'video/ogg';
    default:
      return 'application/octet-stream';
  }
}
