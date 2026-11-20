import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:vaultexplorer/core/services/device_capability_service.dart';
import 'package:vaultexplorer/core/utils/frame_jank_monitor.dart';
import 'package:vaultexplorer/core/utils/perf_trace.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

const int _mb = 1024 * 1024;

/// Tells [PerfTrace] how to describe this device/build and which levels
/// (queue depths, cache sizes) to sample. Does nothing until tracing is on.
void registerPerfTraceDiagnostics() {
  PerfTrace.describeEnvironment = () {
    final image = ThumbnailConcurrency.imageLimiter;
    final video = ThumbnailConcurrency.videoLimiter;
    final flutterImages = PaintingBinding.instance.imageCache;
    final views = PlatformDispatcher.instance.views;
    final hz = views.isEmpty ? null : views.first.display.refreshRate;
    return <String>[
      'build mode: ${kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'DEBUG -- UI-thread times are not representative; re-measure with --profile or a release build'}',
      'device tier: ${DeviceCapabilityService.detectedTier ?? 'unknown (default sizing in use)'}',
      'thumbnail slots: image=${image.maxConcurrency} video=${video.maxConcurrency}',
      'thumbnail memory cache budget: ${ThumbnailCacheService.memoryCacheBudgetBytes ~/ _mb} MB',
      'flutter image cache: up to ${flutterImages.maximumSize} images / ${flutterImages.maximumSizeBytes ~/ _mb} MB',
      'display: ${hz == null ? 'unknown' : '${hz.toStringAsFixed(0)} Hz'}, frame budget ${(FrameJankMonitor.budgetUs / 1000).toStringAsFixed(1)} ms',
    ];
  };

  PerfTrace.samplers.add(() {
    final image = ThumbnailConcurrency.imageLimiter;
    PerfTrace.gauge('queue.image.running', image.running);
    PerfTrace.gauge('queue.image.waiting', image.waiting);
    PerfTrace.gauge(
      'queue.image.waiting.visible',
      image.waitingIn(TaskPriority.visible),
    );
    PerfTrace.gauge(
      'queue.image.waiting.adjacent',
      image.waitingIn(TaskPriority.adjacent),
    );
    PerfTrace.gauge(
      'queue.video.waiting',
      ThumbnailConcurrency.videoLimiter.waiting,
    );
    PerfTrace.gauge(
      'cache.thumb_memory.mb',
      ThumbnailCacheService.memoryCacheBytes ~/ _mb,
    );
    PerfTrace.gauge(
      'cache.thumb_memory.entries',
      ThumbnailCacheService.memoryCacheEntries,
    );
    final flutterImages = PaintingBinding.instance.imageCache;
    PerfTrace.gauge('cache.flutter_images.count', flutterImages.currentSize);
    PerfTrace.gauge(
      'cache.flutter_images.mb',
      flutterImages.currentSizeBytes ~/ _mb,
    );
  });
}
