import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_video_thumbnails.dart';
import 'package:vaultexplorer/data/models/thumbnail_generation_strategy.dart';

/// A fake player + vault. Every grab is numbered in the order it is made; the frame it returns carries that
/// number as its only byte, so a test can tell which grab a thumbnail came from.
class _Fixture {
  _Fixture({
    this.duration = const Duration(seconds: 100),
    this.blankFrames = const {},
    this.failingGrabs = const {},
    int maxConcurrent = 2,
    this.gate,
  }) {
    service = DesktopVideoThumbnails(
      openVaultFile: (vol, path) async {
        vaultOpens++;
        if (path.startsWith('missing')) return null;
        return VideoSource(
          url: 'http://127.0.0.1/$path',
          close: () async {
            closed++;
            if (closeThrows) throw StateError('session already gone');
          },
        );
      },
      grab: _grab,
      decode: _decode,
      maxConcurrent: maxConcurrent,
      grabTimeout: const Duration(seconds: 1),
    );
  }

  final Duration duration;

  /// Grab numbers whose frame decodes as blank.
  final Set<int> blankFrames;

  /// Grab numbers that produce no frame at all.
  final Set<int> failingGrabs;

  /// While set, grabs wait for it.
  final Future<void>? gate;

  late final DesktopVideoThumbnails service;
  final List<Duration?> starts = [];
  final List<String> urls = [];
  final List<bool> localFlags = [];
  var vaultOpens = 0;
  var closed = 0;
  var closeThrows = false;
  var grabThrows = false;

  Future<GrabbedFrame?> _grab({
    required String url,
    required bool isLocalFile,
    Duration? start,
    required Duration timeout,
  }) async {
    final n = starts.length;
    starts.add(start);
    urls.add(url);
    localFlags.add(isLocalFile);
    final g = gate;
    if (g != null) await g;
    if (grabThrows) throw StateError('libmpv is missing');
    if (failingGrabs.contains(n)) return null;
    return GrabbedFrame(encoded: Uint8List.fromList([n]), duration: duration);
  }

  Future<DecodedFrame?> _decode(Uint8List encoded, int targetSize) async => DecodedFrame(
        png: encoded,
        sourceWidth: 1920,
        sourceHeight: 1080,
        isBlank: blankFrames.contains(encoded.first),
      );
}

VideoThumbnailRequest _request({
  int vol = 1,
  String path = 'clip.mp4',
  ThumbnailGenerationStrategy strategy = ThumbnailGenerationStrategy.hybrid,
  double framePosition = 0.12,
  int? explicitTimeUs,
}) =>
    VideoThumbnailRequest(
      volId: vol,
      path: path,
      strategy: strategy,
      framePosition: framePosition,
      explicitTimeUs: explicitTimeUs,
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('frame selection', () {
    test('hybrid: a good first frame is used as is', () async {
      final f = _Fixture();
      final t = await f.service.thumbnail(_request());
      expect(t!.bytes, [0]);
      expect(t.width, 1920); // the source frame's size, not the thumbnail's
      expect(t.height, 1080);
      expect(f.starts, [null]);
    });

    test('hybrid: a blank first frame is retried at 12%, 25%, 45% until one is good', () async {
      final f = _Fixture(blankFrames: {0, 1});
      final t = await f.service.thumbnail(_request());
      expect(f.starts, [null, const Duration(seconds: 12), const Duration(seconds: 25)]);
      expect(t!.bytes, [2]);
    });

    test('hybrid: when every frame is blank the first one is still returned', () async {
      final f = _Fixture(blankFrames: {0, 1, 2, 3});
      final t = await f.service.thumbnail(_request());
      expect(f.starts, hasLength(4));
      expect(t!.bytes, [0]);
    });

    test('hybrid: a failed retry does not lose the frame already in hand', () async {
      final f = _Fixture(blankFrames: {0}, failingGrabs: {1, 2, 3});
      final t = await f.service.thumbnail(_request());
      expect(t!.bytes, [0]);
    });

    test('hybrid: an unknown duration cannot be retried', () async {
      final f = _Fixture(duration: Duration.zero, blankFrames: {0});
      final t = await f.service.thumbnail(_request());
      expect(f.starts, [null]);
      expect(t!.bytes, [0]);
    });

    test('firstFrame never retries', () async {
      final f = _Fixture(blankFrames: {0});
      final t = await f.service.thumbnail(_request(strategy: ThumbnailGenerationStrategy.firstFrame));
      expect(f.starts, [null]);
      expect(t!.bytes, [0]);
    });

    test('frameAtPercentage takes the frame at the position, and falls back to the first one', () async {
      final f = _Fixture();
      final t = await f.service.thumbnail(
        _request(strategy: ThumbnailGenerationStrategy.frameAtPercentage, framePosition: 0.5),
      );
      expect(f.starts, [null, const Duration(seconds: 50)]);
      expect(t!.bytes, [1]);

      final g = _Fixture(failingGrabs: {1});
      final fallback = await g.service.thumbnail(
        _request(strategy: ThumbnailGenerationStrategy.frameAtPercentage, framePosition: 0.5),
      );
      expect(fallback!.bytes, [0]);
    });

    test('an exact timestamp wins over the strategy and is never retried', () async {
      final f = _Fixture(blankFrames: {0});
      final t = await f.service.thumbnail(_request(explicitTimeUs: 5000000));
      expect(f.starts, [const Duration(seconds: 5)]);
      expect(t!.bytes, [0]);

      final zero = _Fixture();
      await zero.service.thumbnail(_request(explicitTimeUs: 0));
      expect(zero.starts, [null]);
    });
  });

  group('sources', () {
    test('a vault file is read through its session, which is closed afterwards', () async {
      final f = _Fixture();
      await f.service.thumbnail(_request(path: 'a/b.mp4'));
      expect(f.vaultOpens, 1);
      expect(f.urls.single, 'http://127.0.0.1/a/b.mp4');
      expect(f.localFlags.single, isFalse);
      expect(f.closed, 1);
    });

    test('the session is closed even when nothing could be grabbed', () async {
      final f = _Fixture(failingGrabs: {0});
      expect(await f.service.thumbnail(_request()), isNull);
      expect(f.closed, 1);
    });

    test('a missing or empty vault file never starts a player', () async {
      final f = _Fixture();
      expect(await f.service.thumbnail(_request(path: 'missing.mp4')), isNull);
      expect(f.starts, isEmpty);
    });

    test('a local file is read directly, a missing one is not', () async {
      final dir = Directory.systemTemp.createTempSync('video_thumb_test_');
      try {
        final file = File('${dir.path}${Platform.pathSeparator}clip.mp4')..writeAsBytesSync([1, 2, 3]);
        final f = _Fixture();
        final t = await f.service.thumbnail(VideoThumbnailRequest(path: file.path, isLocalFile: true));
        expect(t, isNotNull);
        expect(f.vaultOpens, 0);
        expect(f.localFlags.single, isTrue);
        expect(f.urls.single.startsWith('file:'), isTrue);

        final none = await f.service.thumbnail(
          VideoThumbnailRequest(path: '${dir.path}${Platform.pathSeparator}nope.mp4', isLocalFile: true),
        );
        expect(none, isNull);
        expect(f.starts, hasLength(1));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('failures', () {
    test('a player that throws is "no thumbnail", not an error', () async {
      final f = _Fixture()..grabThrows = true;
      expect(await f.service.thumbnail(_request()), isNull);
      expect(f.closed, 1);
    });

    test('a session that fails to close does not lose the thumbnail', () async {
      final f = _Fixture()..closeThrows = true;
      expect(await f.service.thumbnail(_request()), isNotNull);
    });
  });

  group('scheduling', () {
    test('no more players than maxConcurrent at a time, the rest wait their turn', () async {
      final gate = Completer<void>();
      final f = _Fixture(maxConcurrent: 1, gate: gate.future);
      final first = f.service.thumbnail(_request(path: 'a.mp4'));
      final second = f.service.thumbnail(_request(path: 'b.mp4'));
      await _settle();
      expect(f.starts, hasLength(1));

      gate.complete();
      expect(await first, isNotNull);
      expect(await second, isNotNull);
      expect(f.starts, hasLength(2));
    });

    test('locking a vault drops its queued thumbnails and stops the running one, not other vaults', () async {
      final gate = Completer<void>();
      final f = _Fixture(maxConcurrent: 1, gate: gate.future);
      final running = f.service.thumbnail(_request(vol: 1, path: 'a.mp4'));
      final queuedSameVault = f.service.thumbnail(_request(vol: 1, path: 'b.mp4'));
      final queuedOtherVault = f.service.thumbnail(_request(vol: 2, path: 'c.mp4'));
      await _settle();

      f.service.cancelVolume(1);
      expect(await queuedSameVault, isNull);

      gate.complete();
      expect(await running, isNull);
      expect(await queuedOtherVault, isNotNull);
      expect(f.starts, hasLength(2)); // the dropped one never started a player
    });

    test('after dispose nothing is generated', () async {
      final f = _Fixture();
      f.service.dispose();
      expect(await f.service.thumbnail(_request()), isNull);
      expect(f.starts, isEmpty);
    });
  });
}
