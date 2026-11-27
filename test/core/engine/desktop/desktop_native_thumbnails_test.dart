import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_images.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_native_thumbnails.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_video_thumbnails.dart';
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

  group('DesktopVideoThumbnails with the native thumbnailer', () {
    var mpvGrabs = 0;
    var opens = 0;

    NativeImageThumb nativeThumb() => NativeImageThumb(
          bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
          isPng: false,
          sourceWidth: 1080,
          sourceHeight: 1920,
          width: 101,
          height: 180,
          hasAlpha: false,
          isBlank: false,
        );

    DesktopVideoThumbnails make(NativeVideoThumbnailer native, {int maxNative = 2}) {
      mpvGrabs = 0;
      opens = 0;
      return DesktopVideoThumbnails(
        openVaultFile: (vol, path) async {
          opens++;
          return VideoSource(url: 'http://127.0.0.1/$path', close: () async {});
        },
        grab: ({required url, required isLocalFile, start, required timeout}) async {
          mpvGrabs++;
          return GrabbedFrame(encoded: Uint8List.fromList([7]), duration: const Duration(seconds: 10));
        },
        decode: (encoded, targetSize) async =>
            DecodedFrame(png: encoded, sourceWidth: 640, sourceHeight: 360, isBlank: false),
        native: native,
        maxNativeConcurrent: maxNative,
        grabTimeout: const Duration(seconds: 1),
      );
    }

    VideoThumbnailRequest request({int vol = 1, String path = 'a.mp4'}) => VideoThumbnailRequest(volId: vol, path: path);

    test('a native thumbnail is the answer: no player is started and no media-server session opened', () async {
      final service = make((r) async => nativeThumb());
      final t = await service.thumbnail(request());
      expect(t, isNotNull);
      expect(t!.bytes, [0xFF, 0xD8, 0xFF, 0xD9]);
      expect((t.width, t.height), (1080, 1920));
      expect((mpvGrabs, opens), (0, 0));
    });

    test('a video the engine understands but cannot picture is no thumbnail, and libmpv is not asked either', () async {
      final service = make((r) async => const NativeImageFailed());
      expect(await service.thumbnail(request()), isNull);
      expect(mpvGrabs, 0);
    });

    test('"unsupported" (AV1, an exotic container, an engine without FFmpeg) falls through to libmpv', () async {
      final service = make((r) async => const NativeImageUnsupported());
      final t = await service.thumbnail(request());
      expect(t, isNotNull);
      expect(t!.bytes, [7]);
      expect(mpvGrabs, greaterThan(0));
    });

    test('a native call that throws falls through to libmpv instead of failing the tile', () async {
      final service = make((r) async => throw StateError('worker gone'));
      expect((await service.thumbnail(request()))?.bytes, [7]);
    });

    test('native thumbnails are capped, so a burst cannot fill the thumbnail pool', () async {
      final gates = <Completer<void>>[];
      var running = 0, peak = 0;
      final service = make((r) async {
        running++;
        peak = running > peak ? running : peak;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        running--;
        return nativeThumb();
      }, maxNative: 2);
      final results = [for (var i = 0; i < 5; i++) service.thumbnail(request(path: 'v$i.mp4'))];
      await Future<void>.delayed(Duration.zero);
      expect(running, 2); // two started, three queued
      for (var i = 0; i < 20 && !(gates.length == 5 && gates.every((g) => g.isCompleted)); i++) {
        for (final g in gates) {
          if (!g.isCompleted) g.complete();
        }
        await Future<void>.delayed(Duration.zero);
      }
      expect((await Future.wait(results)).every((t) => t != null), isTrue);
      expect(peak, 2);
    });

    test('a locked vault drops its queued native requests', () async {
      final gate = Completer<void>();
      var started = 0;
      final service = make((r) async {
        started++;
        await gate.future;
        return nativeThumb();
      }, maxNative: 1);
      final running = service.thumbnail(request(vol: 1, path: 'a.mp4'));
      final queued = service.thumbnail(request(vol: 1, path: 'b.mp4'));
      final other = service.thumbnail(request(vol: 2, path: 'c.mp4'));
      await Future<void>.delayed(Duration.zero);
      service.cancelVolume(1);
      expect(await queued, isNull);
      gate.complete();
      expect(await running, isNull); // cancelled while running: its result is dropped by the caller's volume lock
      expect(await other, isNotNull);
      expect(started, 2); // 'b.mp4' never started
    });
  });
}
