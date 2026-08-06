import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
      debugPrint('Suppressed stream-after-close error: $errStr');
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
    if (settings.languageCode != null) {
      appLocaleNotifier.value = Locale(settings.languageCode!);
    }
    if (settings.blockScreenshots) {
      await vaultExplorerApi.setSecureScreen(true);
    }
  } catch (_) {}
  try {
    appVersion = await vaultExplorerApi.getAppVersion();
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