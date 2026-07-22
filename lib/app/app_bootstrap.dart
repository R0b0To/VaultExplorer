import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vaultexplorer/app/vault_explorer_app.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// One-time platform/video-backend wiring that must happen before [runApp]
/// — system UI mode, a filter for a couple of known-benign platform errors,
/// and registering the `fvp` video backend.
void configurePlatformIntegrations() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  PlatformDispatcher.instance.onError = (error, stack) {
    final errStr = error.toString();
    if (errStr.contains('Cannot add event after closing') ||
        errStr.contains('video_player_mdk')) {
      return true;
    }
    return false;
  };

  fvp.registerWith(
    options: {
      'platforms': ['android'],
    },
  );
}

/// Settings load, secure-screen setup, package info, and temp-file cleanup —
/// none of this needs to finish before the first frame, so it happens after
/// [runApp] instead of blocking it. [LockGateScreen] independently loads
/// settings itself to build its UI, so this pass mainly handles the
/// side effects (theme notifier, secure screen, version string, cleanup).
Future<void> runDeferredStartupWork() async {
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
/// finally{} block.  Prefixes match [TempFileUtils] and [VaultExplorerApi].
Future<void> _cleanupOrphanedTempFiles() async {
  try {
    final tmpDir = await getTemporaryDirectory();
    // Async listing instead of listSync(): this walks the whole temp
    // directory, and listSync() would block the isolate's event loop
    // for the entire scan instead of yielding between entries.
    await for (final entity in tmpDir.list()) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      // Matches the prefixes used by TempFileUtils.uniquePath and
      // VaultExplorerApi.createEmptyFile.
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
