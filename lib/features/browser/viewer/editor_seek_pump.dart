import 'dart:async';

import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

/// Seek pump and scrub state shared by the audio and video editors.
///
/// Only the latest requested position is ever sent to the player, one seek at
/// a time, so dragging a timeline never queues up a backlog of stale seeks.
/// [request] completes once the player has caught up with the newest request.
class EditorSeekPump {
  EditorSeekPump({
    required NativeVideoController? Function() player,
    required String logTag,
  }) : _player = player,
       _tag = logTag;

  final NativeVideoController? Function() _player;
  final String _tag;

  int? _pendingUs;
  bool _seeking = false;
  Completer<void>? _idle;
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;

  /// True while the user is dragging the playhead or a seek is in flight;
  /// position updates from the player are ignored meanwhile.
  bool get isBusy => _scrubbing || _seeking;

  Future<void> request(int us) {
    _pendingUs = us;
    if (_seeking) return _idle!.future;
    _seeking = true;
    _idle = Completer<void>();
    unawaited(_run());
    return _idle!.future;
  }

  Future<void> _run() async {
    try {
      while (_pendingUs != null) {
        final us = _pendingUs!;
        _pendingUs = null;
        final player = _player();
        if (player == null || player.isDisposed) break;
        await player.seekTo(Duration(milliseconds: (us + 999) ~/ 1000));
      }
    } catch (e) {
      VeLog.w(_tag, 'Seek failed', e);
    } finally {
      _seeking = false;
      _idle!.complete();
    }
  }

  /// Pauses playback for the duration of a scrub, remembering whether to
  /// resume afterwards.
  void scrubStart() {
    _scrubbing = true;
    final player = _player();
    _resumeAfterScrub = player?.value.isPlaying ?? false;
    if (_resumeAfterScrub) unawaited(player?.pause());
  }

  void scrubEnd() {
    _scrubbing = false;
    if (_resumeAfterScrub) unawaited(_player()?.play());
    _resumeAfterScrub = false;
  }
}
