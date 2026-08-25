import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/core/services/device_capability_service.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/services/memory_pressure_observer.dart';
import 'package:vaultexplorer/core/services/resume_paint_signal.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

void configurePlatformIntegrations() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  MemoryPressureObserver.register();
  ResumePaintSignal.register();
  PlatformDispatcher.instance.onError = (error, stack) {
    final errStr = error.toString();
    if (errStr.contains('Cannot add event after closing')) {
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
    final disguiseMode = await disguiseModeApi.getMode();

    appThemeModeNotifier.value = settings.themeMode;
    appUseDynamicColorNotifier.value = settings.useDynamicColor;
    if (settings.languageCode != null) {
      appLocaleNotifier.value = Locale(settings.languageCode!);
    }

    if (disguiseMode == DisguiseMode.decoy) {
      await SecureScreenPolicy.disableForDecoy();
    } else {
      await SecureScreenPolicy.apply(preference: settings.blockScreenshots);
    }
  } catch (_) {
    // Best-effort deferred startup work: a failure loading settings/disguise
    // mode or applying the screen-security policy shouldn't block app
    // launch. The field initializers' defaults stay in effect either way.
  }
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
      final name = entity.path.split('/').last;
      final matches = name.startsWith('cb_copy_') ||
          name.startsWith('cb_empty_') ||
          name.startsWith('cb_edit_') ||
          name.startsWith('xclip_') ||
          name.startsWith('tmp_') ||
          name.startsWith('vx_pdf_') ||
          name.startsWith('archive_browse_') ||
          name.startsWith('archive_extract_');
      if (!matches) continue;
      try {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else {
          await entity.delete();
        }
      } catch (_) {
        // Best-effort per-entity cleanup: leave this one orphaned temp file
        // and move on to the rest rather than aborting the whole sweep.
      }
    }
  } catch (_) {
    // Best-effort cleanup overall: if listing the temp directory itself
    // fails, there's nothing more to clean up this run; try again next
    // startup.
  }
}