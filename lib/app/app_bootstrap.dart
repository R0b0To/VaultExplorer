import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/services/memory_pressure_observer.dart';
import 'package:vaultexplorer/core/services/device_capability_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

void configurePlatformIntegrations() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  MemoryPressureObserver.register();
  PlatformDispatcher.instance.onError = (error, stack) {
    final errStr = error.toString();
    if (errStr.contains('Cannot add event after closing')) {
      return true;
    }
    return false;
  };

  try {
    fvp.registerWith(options: {
      'platforms': ['android'],
      'video.decoders': ['FFmpeg'],
    });
  } catch (_) {}
}


Future<void> runDeferredStartupWork() async {

  unawaited(DeviceCapabilityService.init());
  unawaited(ThumbnailCacheService.enforceDiskBudget());

  try {
    final settings = await AppSettingsService.loadSettings();
    appThemeModeNotifier.value = settings.themeMode;
    if (settings.blockScreenshots) {
      await vaultExplorerApi.setSecureScreen(true);
    }
  } catch (_) {}
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    appVersion = packageInfo.version; // e.g., "0.8.10"
  } catch (e) {
    // Fallback if platform retrieval fails
    appVersion = 'unknown';
  }
  // clean up any decrypted temp files left behind by a
  // previous crash or force-kill before the copy/paste finally{} block ran.
  await _cleanupOrphanedTempFiles();
}

/// Deletes any temp files written during copy/paste or export that were not
/// cleaned up because the process was killed between decryption and the
/// finally{} block. Prefixes match [TempFileUtils] and [VaultExplorerApi].
Future<void> _cleanupOrphanedTempFiles() async {
  try {
    final tmpDir = await getTemporaryDirectory();
    await for (final entity in tmpDir.list()) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      if (name.startsWith('cb_copy_') ||
          name.startsWith('cb_empty_') ||
          name.startsWith('cb_edit_') ||
          name.startsWith('xclip_') ||
          name.startsWith('tmp_')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  } catch (_) {}
}