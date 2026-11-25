import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_images.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_native_thumbnails.dart';
import 'package:vaultexplorer/core/engine/desktop/ve_native.dart';
import 'package:vaultexplorer/core/engine/desktop/video_frame_decoder.dart';

/// A reply as the worker sends it: [resultCode, bytes?, info ints].
List<Object?> _ok({
  List<int> bytes = const [0xFF, 0xD8, 0xFF, 0xD9],
  bool png = false,
  int sourceWidth = 4000,
  int sourceHeight = 3000,
  int width = 180,
  int height = 135,
  bool alpha = false,
  bool blank = false,
}) =>
    [
      veOk,
      Uint8List.fromList(bytes),
      [png ? 1 : 0, sourceWidth, sourceHeight, width, height, alpha ? 1 : 0, blank ? 1 : 0, 0],
    ];

List<Object?> _error(int rc) => [rc, null, const <int>[]];

/// A fake thumbnail pool: records every call and answers with [reply].
class _FakePool {
  _FakePool(this.reply);

  Object? Function(String op, List<Object?> args) reply;
  final List<(String, List<Object?>)> calls = [];

  Future<Object?> call(String op, [List<Object?> args = const []]) async {
    calls.add((op, args));
    return reply(op, args);
  }
}

void main() {
  group('interpretNativeThumbnailReply', () {
    test('a thumbnail carries bytes, both sizes and the flags', () {
      final r = interpretNativeThumbnailReply(_ok(png: true, alpha: true, blank: true, sourceWidth: 10, sourceHeight: 20));
      expect(r, isA<NativeImageThumb>());
      final t = r as NativeImageThumb;
      expect(t.bytes, [0xFF, 0xD8, 0xFF, 0xD9]);
      expect(t.isPng, isTrue);
      expect(t.hasAlpha, isTrue);
      expect(t.isBlank, isTrue);
      expect((t.sourceWidth, t.sourceHeight), (10, 20));
      expect((t.width, t.height), (180, 135));
    });

    test('result codes map to outcomes', () {
      expect(interpretNativeThumbnailReply(_error(veErrUnsupported)), isA<NativeImageUnsupported>());
      expect(interpretNativeThumbnailReply(_error(veErrFailed)), isA<NativeImageFailed>());
      expect(interpretNativeThumbnailReply(_error(veErrNotUnlocked)), isA<NativeImageFailed>());
      expect(interpretNativeThumbnailReply(_error(veErrInvalidArg)), isA<NativeImageFailed>());
      final tooLarge = interpretNativeThumbnailReply(_error(veErrTooLarge)) as NativeImageRefused;
      expect(tooLarge.outOfMemory, isFalse);
      final noMemory = interpretNativeThumbnailReply(_error(veErrNoMemory)) as NativeImageRefused;
      expect(noMemory.outOfMemory, isTrue);
    });

    test('a success without bytes is a failure, not an empty thumbnail', () {
      expect(interpretNativeThumbnailReply([veOk, Uint8List(0), List<int>.filled(8, 0)]), isA<NativeImageFailed>());
      expect(interpretNativeThumbnailReply([veOk, null, const <int>[]]), isA<NativeImageFailed>());
    });
  });

  group('DesktopNativeThumbnails', () {
    test('sends each kind of source to its own op with the arguments in order', () async {
      final pool = _FakePool((op, args) => _ok());
      final native = DesktopNativeThumbnails(call: pool.call);

      await native.vaultFile(3, '/a/b.jpg', targetSize: 180, quality: 70, preserveAlpha: false, maxSourceBytes: 99);
      await native.hostFile('/tmp/x.png', targetSize: 360, quality: 80, preserveAlpha: true, maxSourceBytes: 50);
      await native.memory(Uint8List.fromList([1, 2, 3]), targetSize: 200, quality: 75);

      expect(pool.calls.map((c) => c.$1), ['imageThumbnail', 'imageThumbnailFile', 'imageThumbnailMem']);
      expect(pool.calls[0].$2, [3, '/a/b.jpg', 180, 70, false, 99]);
      expect(pool.calls[1].$2, ['/tmp/x.png', 360, 80, true, 50]);
      expect(pool.calls[2].$2, [
        Uint8List.fromList([1, 2, 3]),
        200,
        75,
        false,
      ]);
    });

    test('a pool that cannot run answers "unsupported", so the caller uses another decoder', () async {
      final native = DesktopNativeThumbnails(call: (op, [args = const []]) => throw StateError('engine library not loaded'));
      final r = await native.vaultFile(0, '/a.jpg', targetSize: 180, quality: 70, preserveAlpha: false, maxSourceBytes: 1);
      expect(r, isA<NativeImageUnsupported>());
    });

    test('dispose stops the pool it owns', () async {
      var stopped = 0;
      final native = DesktopNativeThumbnails(call: (op, [args = const []]) async => _ok(), onDispose: () async => stopped++);
      await native.dispose();
      expect(stopped, 1);
    });
  });

  test('nativeThumbnailWorkers leaves a core for the UI and stays within 2..8', () {
    expect(nativeThumbnailWorkers(cores: 1), 2);
    expect(nativeThumbnailWorkers(cores: 2), 2);
    expect(nativeThumbnailWorkers(cores: 4), 3);
    expect(nativeThumbnailWorkers(cores: 8), 7);
    expect(nativeThumbnailWorkers(cores: 16), 8);
    expect(nativeThumbnailWorkers(cores: 128), 8);
  });

  group('DesktopImages with the native thumbnailer', () {
    late _FakePool pool;
    late List<String> wholeReads;
    late DesktopImages images;

    setUp(() {
      pool = _FakePool((op, args) => _ok(sourceWidth: 6000, sourceHeight: 4000));
      wholeReads = [];
      images = DesktopImages(
        readWhole: (vol, path, maxBytes) async {
          wholeReads.add(path);
          return null; // the Flutter route has nothing to decode in these tests
        },
        native: DesktopNativeThumbnails(call: pool.call),
      );
    });

    test('answers the native thumbnail with the SOURCE size, and never reads the file into Dart', () async {
      final t = await images.thumbnail(1, '/p/photo.jpg', targetSize: 180, quality: 65, preserveAlpha: true);
      expect(t, isNotNull);
      expect(t!.bytes, [0xFF, 0xD8, 0xFF, 0xD9]);
      expect((t.width, t.height), (6000, 4000));
      expect(wholeReads, isEmpty);
      expect(pool.calls.single.$1, 'imageThumbnail');
      expect(pool.calls.single.$2, [1, '/p/photo.jpg', 180, 65, true, DesktopImages.maxSourceBytes]);
    });

    test('a host file goes to the host-file op', () async {
      await images.thumbnail(null, '/home/me/pic.webp', targetSize: 256, hostFile: true);
      expect(pool.calls.single.$1, 'imageThumbnailFile');
      expect(pool.calls.single.$2.first, '/home/me/pic.webp');
    });

    test('a picture the engine could not decode is "no thumbnail" and is not retried through Flutter', () async {
      pool.reply = (op, args) => _error(veErrFailed);
      expect(await images.thumbnail(1, '/p/bad.jpg', targetSize: 180), isNull);
      expect(wholeReads, isEmpty);
    });

    test('a format the engine does not handle falls back to Flutter\'s route', () async {
      pool.reply = (op, args) => _error(veErrUnsupported);
      expect(await images.thumbnail(1, '/p/anim.gif', targetSize: 180), isNull); // readWhole gave nothing
      expect(wholeReads, ['/p/anim.gif']);
    });

    test('the size guards surface as the codes the app already understands', () async {
      pool.reply = (op, args) => _error(veErrTooLarge);
      await expectLater(
        images.thumbnail(1, '/p/huge.png', targetSize: 180),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'IMAGE_TOO_LARGE')),
      );
      pool.reply = (op, args) => _error(veErrNoMemory);
      await expectLater(
        images.thumbnail(1, '/p/huge.png', targetSize: 180),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'OUT_OF_MEMORY')),
      );
    });
  });

  group('nativeFrameDecoder', () {
    test('turns a native thumbnail into a decoded frame with the blank verdict', () async {
      final pool = _FakePool((op, args) => _ok(sourceWidth: 3840, sourceHeight: 2160, blank: true));
      final decode = nativeFrameDecoder(DesktopNativeThumbnails(call: pool.call));
      final frame = await decode(Uint8List.fromList([9, 9, 9]), 180);
      expect(frame, isNotNull);
      expect(frame!.png, [0xFF, 0xD8, 0xFF, 0xD9]);
      expect((frame.sourceWidth, frame.sourceHeight), (3840, 2160));
      expect(frame.isBlank, isTrue);
      expect(pool.calls.single.$1, 'imageThumbnailMem');
      expect(pool.calls.single.$2[1], 180);
    });

    test('a frame the engine cannot decode is no thumbnail', () async {
      final pool = _FakePool((op, args) => _error(veErrFailed));
      final decode = nativeFrameDecoder(DesktopNativeThumbnails(call: pool.call));
      expect(await decode(Uint8List.fromList([1]), 180), isNull);
    });
  });
}
