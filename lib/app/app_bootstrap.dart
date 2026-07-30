import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/core/services/device_capability_service.dart';
import 'package:vaultexplorer/core/services/memory_pressure_observer.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

void configurePlatformIntegrations() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  MemoryPressureObserver.register();
  PlatformDispatcher.instance.onError = (error, stack) {
    final errStr = error.toString();
    if (errStr.contains('Cannot add event after closing')) {
      // The one known source of this (VaultCameraController.dispose()
      // racing its own StreamController.close() against a straggling
      // native camera event) is fixed -- see docs/tech-debt.md TD-9. This
      // is now a safety net, not a silent blanket suppression: if it fires
      // again, that's a *new* instance of the same class of bug somewhere
      // else, and it should be visible rather than invisible.
      debugPrint('Suppressed stream-after-close error (see TD-9): $errStr');
      return true;
    }
    return false;
  };
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
    appVersion = packageInfo.version;
  } catch (e) {
    appVersion = 'unknown';
  }
  await _cleanupOrphanedTempFiles();
}

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
          name.startsWith('tmp_') ||
          name.startsWith('vx_pdf_')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  } catch (_) {}
}