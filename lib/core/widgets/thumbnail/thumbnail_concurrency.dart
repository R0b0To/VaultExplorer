import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart';


export 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart';

void unawaited(Future<void> future) {
  future.catchError((Object e) {
    // error silently swallowed
  });
}

class ThumbnailConcurrency {
  ThumbnailConcurrency._();

  static final imageLimiter = PriorityTaskQueue(2);
  static final videoLimiter = PriorityTaskQueue(1);

  static var inFlightThumbnails = LruCache<String, Future<Uint8List>>(160);

  static void resizeForDevice({
    required int imageConcurrency,
    required int videoConcurrency,
    required int inFlightCapacity,
  }) {
    imageLimiter.resize(imageConcurrency);
    videoLimiter.resize(videoConcurrency);
    inFlightThumbnails.resize(inFlightCapacity);
  }
}