// The libmpv half of desktop video thumbnails: open a video paused, wait for its first picture, take it.
//
// Same player the desktop video backend uses (media_kit), set up with the same guarantees: nothing is cached to
// disk, nothing is remembered, and the player may only read from the loopback media server (or, for a plain
// local-storage file, a `file:` URL). A FRESH player is made for every frame and disposed right after. That costs
// a little startup, and buys that a frame can never be a stale one from the previous video, and that nothing
// is left running between thumbnails.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'desktop_video_thumbnails.dart' show GrabbedFrame;

/// How long after an error event the player may still produce a picture before the attempt is abandoned. mpv
/// reports some harmless problems (a broken cover image, say) through the same stream as fatal ones, so an error
/// alone does not end the attempt; one that is followed by no picture does.
const Duration _errorGrace = Duration(seconds: 2);

/// A [FrameGrabber](desktop_video_thumbnails.dart) backed by libmpv.
Future<GrabbedFrame?> grabFrameWithMpv({
  required String url,
  required bool isLocalFile,
  Duration? start,
  required Duration timeout,
}) async {
  Player? player;
  Timer? errorTimer;
  final subscriptions = <StreamSubscription<Object?>>[];
  try {
    MediaKit.ensureInitialized();
    player = Player(
      configuration: PlayerConfiguration(
        title: 'Vault Explorer thumbnail',
        protocolWhitelist: isLocalFile ? const ['file'] : const ['http', 'tcp'],
      ),
    );

    final native = player.platform;
    if (native is! NativePlayer) return null;

    // Must hold: media_kit turns `cache-on-disk` on by default, which would spool the decrypted stream to a file.
    await native.setProperty('cache-on-disk', 'no');
    if (await native.getProperty('cache-on-disk') != 'no') {
      debugPrint('[desktop-thumbnail] refusing to open video: could not disable the on-disk media cache');
      return null;
    }
    await native.setProperty('sub-auto', 'no');
    await native.setProperty('audio-file-auto', 'no');
    await native.setProperty('save-position-on-quit', 'no');

    // Nice to have, and harmless if one does not apply: one still frame needs no GPU decoder, no sound device,
    // and no read-ahead beyond the first few MiB (the default would pull ~150 MiB of the vault through the
    // decryption for every thumbnail).
    await _trySet(native, 'hwdec', 'no');
    await _trySet(native, 'ao', 'null');
    await _trySet(native, 'demuxer-max-bytes', '${16 * 1024 * 1024}');

    // Software rendering: a thumbnail must not compete with playback (or the UI) for a GL context.
    final controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(enableHardwareAcceleration: false),
    );

    var gaveUp = false;
    final giveUp = Completer<void>();
    subscriptions.add(
      player.stream.error.listen((message) {
        if (message.trim().isEmpty) return;
        debugPrint('[desktop-thumbnail] mpv: $message');
        errorTimer ??= Timer(_errorGrace, () {
          gaveUp = true;
          if (!giveUp.isCompleted) giveUp.complete();
        });
      }, onError: (Object _) {}),
    );

    final firstFrame = controller.waitUntilFirstFrameRendered;
    await player.open(Media(url, start: start), play: false);

    // Whichever comes first: the first picture, the error grace running out, or the timeout. A timeout is not
    // final: if the "first frame" signal was missed but a picture exists, the screenshot below still gets it.
    await Future.any<void>([firstFrame, giveUp.future]).timeout(timeout, onTimeout: () {});
    if (gaveUp) return null;

    final encoded = await player.screenshot(format: 'image/jpeg').timeout(const Duration(seconds: 10));
    if (encoded == null || encoded.isEmpty) return null;
    return GrabbedFrame(encoded: encoded, duration: player.state.duration);
  } finally {
    errorTimer?.cancel();
    for (final s in subscriptions) {
      try {
        await s.cancel();
      } on Object catch (e) {
        debugPrint('[desktop-thumbnail] could not cancel a player subscription: $e');
      }
    }
    try {
      await player?.dispose();
    } on Object catch (e) {
      debugPrint('[desktop-thumbnail] could not dispose the player: $e');
    }
  }
}

Future<void> _trySet(NativePlayer native, String property, String value) async {
  try {
    await native.setProperty(property, value);
  } on Object catch (e) {
    debugPrint('[desktop-thumbnail] could not set $property: $e'); // non-fatal: the setting just does not apply
  }
}
