import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'gallery_meta.dart';
import 'gallery_meta_parser.dart';

/// Parses photo headers (EXIF, XMP, container boxes) on a background isolate.
///
/// [GalleryMetaParser.parse] is synchronous CPU work (a UTF-8 decode of the XMP
/// packet and several regular expressions over up to 160 KB per photo). Run
/// inline for every photo of a large library it takes a slice out of every
/// frame for as long as the scan lasts. The *reads* stay on the calling isolate
/// (they go through platform channels, which a plain isolate cannot use); only
/// the bytes travel, handed over without a copy ([TransferableTypedData]).
///
/// The isolate starts with the first photo and stops by itself after
/// [idleTimeout] without work, so an idle gallery costs nothing. Should it
/// fail to start or die, parsing silently falls back to the calling isolate:
/// slower for the frames, never wrong.
class GalleryMetaWorker {
  GalleryMetaWorker({this.idleTimeout = const Duration(seconds: 5)});

  final Duration idleTimeout;

  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  ReceivePort? _exitPort;
  ReceivePort? _errorPort;
  Completer<SendPort>? _ready;
  Future<void>? _starting;
  final Map<int, Completer<GalleryMeta>> _pending = {};
  int _nextId = 0;
  Timer? _idleTimer;
  bool _disposed = false;
  bool _broken = false;

  /// Whether the background isolate is up (for tests and diagnostics).
  bool get isRunning => _toWorker != null;

  /// Whether parsing has fallen back to the calling isolate for good.
  bool get isBroken => _broken;

  /// What [GalleryMetaParser.parse] returns for [bytes], computed off the
  /// calling isolate when possible. Completes with an error only if the worker
  /// was stopped (disposed) while the photo was being parsed.
  Future<GalleryMeta> parse(Uint8List bytes) async {
    if (_disposed || _broken) return GalleryMetaParser.parse(bytes);
    _idleTimer?.cancel();
    try {
      await (_starting ??= _start());
    } catch (_) {
      if (_disposed) return GalleryMetaParser.parse(bytes);
      _broken = true;
      _teardown();
      return GalleryMetaParser.parse(bytes);
    }
    final send = _toWorker;
    if (send == null) return GalleryMetaParser.parse(bytes);
    final id = _nextId++;
    final done = Completer<GalleryMeta>();
    _pending[id] = done;
    send.send(<Object>[id, TransferableTypedData.fromList([bytes])]);
    return done.future;
  }

  Future<void> _start() async {
    final from = ReceivePort();
    final exit = ReceivePort();
    final error = ReceivePort();
    final ready = Completer<SendPort>();
    // Failing it on teardown must not be reported as unhandled when the
    // spawn itself was what failed and nobody waits for it yet.
    ready.future.ignore();
    _fromWorker = from;
    _exitPort = exit;
    _errorPort = error;
    _ready = ready;
    from.listen((Object? message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is List && message.length == 2 && message[0] is int) {
        _onResult(message[0] as int, message[1]);
      }
    });
    exit.listen((_) => _onDied());
    error.listen((_) => _onDied());
    try {
      _isolate = await Isolate.spawn<SendPort>(
        _workerMain,
        from.sendPort,
        onExit: exit.sendPort,
        onError: error.sendPort,
        errorsAreFatal: true,
        debugName: 'GalleryMetaWorker',
      );
      final port = await ready.future.timeout(const Duration(seconds: 10));
      if (_disposed) throw StateError('GalleryMetaWorker disposed');
      _toWorker = port;
    } catch (_) {
      _teardown();
      rethrow;
    }
  }

  void _onResult(int id, Object? json) {
    final done = _pending.remove(id);
    if (done != null && !done.isCompleted) {
      final meta = json == null ? null : GalleryMeta.tryFromJson(json);
      if (meta == null) {
        done.completeError(StateError('photo header could not be parsed'));
      } else {
        done.complete(meta);
      }
    }
    _armIdle();
  }

  void _onDied() {
    if (_disposed) return;
    _broken = true;
    _teardown(StateError('GalleryMetaWorker died'));
  }

  void _armIdle() {
    if (_disposed || _pending.isNotEmpty) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      if (_pending.isEmpty) _teardown();
    });
  }

  void _teardown([Object? error]) {
    _idleTimer?.cancel();
    _idleTimer = null;
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('GalleryMetaWorker stopped'));
    }
    _toWorker = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fromWorker?.close();
    _exitPort?.close();
    _errorPort?.close();
    _fromWorker = null;
    _exitPort = null;
    _errorPort = null;
    _starting = null;
    final waiting = _pending.values.toList();
    _pending.clear();
    for (final c in waiting) {
      if (!c.isCompleted) {
        c.completeError(error ?? StateError('GalleryMetaWorker stopped'));
      }
    }
  }

  /// Stops the isolate. Photos still being parsed complete with an error.
  void dispose() {
    _disposed = true;
    _teardown();
  }
}

void _workerMain(SendPort host) {
  final port = ReceivePort();
  host.send(port.sendPort);
  port.listen((Object? message) {
    final request = message as List<Object?>;
    final id = request[0] as int;
    List<Object?>? json;
    try {
      final bytes = (request[1] as TransferableTypedData)
          .materialize()
          .asUint8List();
      json = GalleryMetaParser.parse(bytes).toJson();
    } catch (_) {
      json = null;
    }
    host.send(<Object?>[id, json]);
  });
}
