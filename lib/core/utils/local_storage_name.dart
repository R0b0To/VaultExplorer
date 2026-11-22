import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/utils/platform_features.dart';

/// What to call the "Local Storage" location. On Android it is the device's
/// shared storage, so [fallback] ("Local Storage") fits; on desktop it opens
/// the user's home folder, so it is named after that folder (`Aeido`).
String localStorageDisplayName(String fallback) {
  if (!PlatformFeatures.isDesktop) return fallback;
  final env = Platform.environment;
  final home = (Platform.isWindows ? env['USERPROFILE'] : env['HOME']) ?? '';
  if (home.isEmpty) return fallback;
  final name = p.basename(home);
  return name.isEmpty ? fallback : name;
}
