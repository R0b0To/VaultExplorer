import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:path_provider/path_provider.dart';
import 'theme.dart';
import 'screens/lock/lock_gate_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vaultexplorer/services/app_settings_service.dart';
import 'package:vaultexplorer/services/vaultexplorer_api.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

String appVersion = '0.0.0';
void main() async {
  // Ensure bindings are initialised before calling path_provider.
  WidgetsFlutterBinding.ensureInitialized();
  VaultExplorerApi.initMethodCallHandler();
  if (kDebugMode) {
    // Fire-and-forget; asserts internally if the native CascadeId/HashId
   // ordering has drifted from what crypto_algorithms.dart expects.
    //CipherAlgo.verifyNativeCascadeOrdering();
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  try {
    final settings = await AppSettingsService.loadSettings();
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

  runApp(const VaultExplorerApp());
}

/// Deletes any temp files written during copy/paste or export that were not
/// cleaned up because the process was killed between decryption and the
/// finally{} block.  Prefixes match [TempFileUtils] and [VaultExplorerApi].
Future<void> _cleanupOrphanedTempFiles() async {
  try {
    final tmpDir = await getTemporaryDirectory();
    for (final entity in tmpDir.listSync()) {
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

class VaultExplorerApp extends StatelessWidget {
  const VaultExplorerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VaultExplorer',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: const LockGateScreen(),
    );
  }
}