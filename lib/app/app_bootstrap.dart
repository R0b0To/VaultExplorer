import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/device_capability_service.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/services/memory_pressure_observer.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/services/resume_paint_signal.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';

void configurePlatformIntegrations(ProviderContainer container) {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  MemoryPressureObserver.register();
  final fileIoApi = container.read(vaultFileIoApiProvider);
  ResumePaintSignal.register(fileIoApi);
  PlaybackThrottleController.configure(fileIoApi);
  ArchiveService.configure(fileIoApi);
  ThumbnailCacheService.configure(
    fileIoApi: fileIoApi,
    cryptoApi: container.read(vaultCryptoApiProvider),
    hashApi: container.read(vaultHashApiProvider),
  );
  PlatformDispatcher.instance.onError = (error, stack) {
    final errStr = error.toString();
    if (errStr.contains('Cannot add event after closing')) {
      return true;
    }
    return false;
  };
}

Future<void> runDeferredStartupWork(ProviderContainer container) async {
  unawaited(
    DeviceCapabilityService.init(container.read(vaultLifecycleApiProvider)),
  );
  unawaited(ThumbnailCacheService.enforceDiskBudget());
  try {
    final settings = await container
        .read(appSettingsServiceProvider)
        .loadSettings();
    final disguiseMode = await disguiseModeApi.getMode();
    final secureScreenPolicy = container.read(secureScreenPolicyProvider);

    appThemeModeNotifier.value = settings.themeMode;
    appUseDynamicColorNotifier.value = settings.useDynamicColor;
    appUsePureBlackNotifier.value = settings.useOledBlackTheme;
    if (settings.languageCode != null) {
      appLocaleNotifier.value = Locale(settings.languageCode!);
    }

    if (disguiseMode == DisguiseMode.decoy) {
      await secureScreenPolicy.disableForDecoy();
    } else {
      await secureScreenPolicy.apply(preference: settings.blockScreenshots);
    }
  } catch (_) {
    // Best-effort deferred startup work: a failure loading settings/disguise
    // mode or applying the screen-security policy shouldn't block app
    // launch. The field initializers' defaults stay in effect either way.
  }
  try {
    appVersion = await container.read(vaultFileIoApiProvider).getAppVersion();
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
      final matches =
          name.startsWith('cb_copy_') ||
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
