import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Queries [DeviceCapabilityProfiler] on the native platform via MethodChannel and
/// scales Dart-side concurrency gates and memory budgets according to device hardware tier
/// (`LOW`, `MEDIUM`, or `HIGH`).
class DeviceCapabilityService {
  DeviceCapabilityService._();

  static bool _initialized = false;

  /// Queries native device capability profile once at startup and resizes Dart-side
  /// cache/concurrency structures accordingly. Safe to call multiple times (no-ops if already done).
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final profile = await vaultExplorerApi.getDeviceCapabilityProfile();
      final tier = profile.tier;


      switch (tier.toUpperCase()) {
        case 'LOW':
          ThumbnailConcurrency.resizeForDevice(
            imageConcurrency: 1,
            videoConcurrency: 1,
            inFlightCapacity: 80,
          );
          ThumbnailCacheService.resizeMemoryBudget(12 * 1024 * 1024); // 12 MB
          FullResImageCache.resize(60 * 1024 * 1024); // 60 MB
          break;

        case 'HIGH':
          ThumbnailConcurrency.resizeForDevice(
            imageConcurrency: 3,
            videoConcurrency: 2,
            inFlightCapacity: 240,
          );
          ThumbnailCacheService.resizeMemoryBudget(48 * 1024 * 1024); // 48 MB
          FullResImageCache.resize(300 * 1024 * 1024); // 300 MB
          break;

        case 'MEDIUM':
        default:
          ThumbnailConcurrency.resizeForDevice(
            imageConcurrency: 2,
            videoConcurrency: 1,
            inFlightCapacity: 160,
          );
          ThumbnailCacheService.resizeMemoryBudget(24 * 1024 * 1024); // 24 MB
          FullResImageCache.resize(150 * 1024 * 1024); // 150 MB
          break;
      }
    } catch (e) {

    }
  }
}
