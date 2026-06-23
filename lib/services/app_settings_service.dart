import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Per-container configuration persisted alongside saved containers.
class ContainerConfig {
  final String uri;
  String label; // user-editable display name
  bool rememberPassword;
  String? encryptedPassword; // stored only when rememberPassword = true
  int autoCloseMins; // 0 = disabled

  ContainerConfig({
    required this.uri,
    required this.label,
    this.rememberPassword = false,
    this.encryptedPassword,
    this.autoCloseMins = 0,
  });

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'label': label,
        'rememberPassword': rememberPassword,
        'encryptedPassword': encryptedPassword,
        'autoCloseMins': autoCloseMins,
      };

  factory ContainerConfig.fromJson(Map<String, dynamic> j) => ContainerConfig(
        uri: j['uri'] as String,
        label: j['label'] as String? ?? '',
        rememberPassword: j['rememberPassword'] as bool? ?? false,
        encryptedPassword: j['encryptedPassword'] as String?,
        autoCloseMins: j['autoCloseMins'] as int? ?? 0,
      );
}

/// Global app settings (master password, document provider, etc.)
class AppSettings {
  bool useMasterPassword;
  bool masterPasswordIsFingerprint;
  String? masterPasswordHash; // bcrypt / simple hash placeholder
  bool mountAsDocumentProvider;

  AppSettings({
    this.useMasterPassword = false,
    this.masterPasswordIsFingerprint = false,
    this.masterPasswordHash,
    this.mountAsDocumentProvider = true,
  });

  Map<String, dynamic> toJson() => {
        'useMasterPassword': useMasterPassword,
        'masterPasswordIsFingerprint': masterPasswordIsFingerprint,
        'masterPasswordHash': masterPasswordHash,
        'mountAsDocumentProvider': mountAsDocumentProvider,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        useMasterPassword: j['useMasterPassword'] as bool? ?? false,
        masterPasswordIsFingerprint:
            j['masterPasswordIsFingerprint'] as bool? ?? false,
        masterPasswordHash: j['masterPasswordHash'] as String?,
        mountAsDocumentProvider:
            j['mountAsDocumentProvider'] as bool? ?? true,
      );
}

class AppSettingsService {
  static Future<File> get _settingsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  static Future<File> get _containerConfigsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/container_configs.json');
  }

  // ── App-level settings ────────────────────────────────────────────────────

  static Future<AppSettings> loadSettings() async {
    try {
      final file = await _settingsFile;
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return AppSettings.fromJson(json);
      }
    } catch (_) {}
    return AppSettings();
  }

  static Future<void> saveSettings(AppSettings settings) async {
    try {
      final file = await _settingsFile;
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {}
  }

  // ── Per-container configs ─────────────────────────────────────────────────

  static Future<Map<String, ContainerConfig>> loadContainerConfigs() async {
    try {
      final file = await _containerConfigsFile;
      if (await file.exists()) {
        final list = jsonDecode(await file.readAsString()) as List<dynamic>;
        return {
          for (final item in list)
            (item as Map<String, dynamic>)['uri'] as String:
                ContainerConfig.fromJson(item)
        };
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveContainerConfig(ContainerConfig config) async {
    try {
      final configs = await loadContainerConfigs();
      configs[config.uri] = config;
      final file = await _containerConfigsFile;
      await file.writeAsString(
          jsonEncode(configs.values.map((c) => c.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> removeContainerConfig(String uri) async {
    try {
      final configs = await loadContainerConfigs();
      configs.remove(uri);
      final file = await _containerConfigsFile;
      await file.writeAsString(
          jsonEncode(configs.values.map((c) => c.toJson()).toList()));
    } catch (_) {}
  }

  static Future<ContainerConfig?> getContainerConfig(String uri) async {
    final configs = await loadContainerConfigs();
    return configs[uri];
  }
}