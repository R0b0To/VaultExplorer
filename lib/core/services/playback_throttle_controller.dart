import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';


class PlaybackThrottleController {
  PlaybackThrottleController._();

  static final ValueNotifier<bool> isPlaybackActive = ValueNotifier<bool>(false);

  /// Completes when the current playback initialization finishes (or
  /// immediately if no playback session is initializing). Video thumbnail
  /// extraction tasks await this before starting, ensuring the ExoPlayer
  /// MediaCodec claim is resolved before a thumbnail decoder contends for
  /// the same hardware instance.
  static Completer<void>? _initGate;

  /// Call at the start of ExoPlayer initialization to lock the gate.
  static void setInitializing() {
    _initGate ??= Completer<void>();
  }

  /// Call after ExoPlayer initialization completes (success or failure)
  /// to release any tasks waiting on the gate.
  static void setInitialized() {
    if (_initGate != null && !_initGate!.isCompleted) {
      _initGate!.complete();
    }
    _initGate = null;
  }

  /// A future that completes once the active ExoPlayer initialization is
  /// finished. Returns immediately if no initialization is in progress.
  static Future<void> get initGate => _initGate?.future ?? Future.value();

  static Future<void> setActive(bool active) async {
    if (isPlaybackActive.value != active) {
      isPlaybackActive.value = active;
      if (active) {
        ThumbnailConcurrency.videoLimiter.cancelAll();
      }
      await vaultExplorerApi.setPlaybackActive(active);
    } else if (active) {
      await vaultExplorerApi.setPlaybackActive(true);
    }
  }


}
