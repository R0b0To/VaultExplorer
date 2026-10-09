import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/api/vault_panic_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/text_editor_appearance_service.dart';

part 'settings_backup_service.g.dart';

/// Settings backup is used from a screen but composes services that have no
/// widget context of their own. Providing that composition keeps its file I/O
/// and persisted-settings dependencies overrideable in tests.
@Riverpod(keepAlive: true)
SettingsBackupService settingsBackupService(Ref ref) => SettingsBackupService(
  appSettingsService: ref.watch(appSettingsServiceProvider),
  toolbarService: ref.watch(fileManagerToolbarServiceProvider),
  fileIoApi: ref.watch(vaultFileIoApiProvider),
  panicApi: ref.watch(vaultPanicApiProvider),
  lifecycleApi: ref.watch(vaultLifecycleApiProvider),
);

/// Thrown when an imported file isn't a bundle this app produced.
class InvalidSettingsBackupException implements Exception {
  final String message;
  const InvalidSettingsBackupException(this.message);

  @override
  String toString() => message;
}

/// The result of a successful import, so the caller can update its UI
/// state without re-reading both services from disk.
class ImportedSettingsBundle {
  final AppSettings appSettings;
  final FileManagerToolbarConfig toolbarConfig;
  final PanicTier? panicTier;
  final bool? quickTileEnabled;
  final bool? panicKitEnabled;
  final bool? panicKitEnforcement;
  final bool? shareTargetEnabled;

  const ImportedSettingsBundle({
    required this.appSettings,
    required this.toolbarConfig,
    this.panicTier,
    this.quickTileEnabled,
    this.panicKitEnabled,
    this.panicKitEnforcement,
    this.shareTargetEnabled,
  });
}

/// Settings -> Export/Import: bundles [AppSettings] and the file-manager
/// toolbar layout ([FileManagerToolbarConfig]) into one plain-JSON file
/// the user saves/loads through the system document picker.
///
/// Deliberately excludes anything security-sensitive or per-container:
/// the master password hash/salt never enter [AppSettings.toJson] in the
/// first place, and container records (which is where bookmarks/pinned
/// paths and keystore material actually live -- see
/// [ContainerRepository], all of it Keystore-backed, not plain text) are
/// out of scope for this bundle entirely. Only app-wide preferences and
/// the toolbar layout travel.
///
/// The toolbar layout itself is *not* fully container-agnostic, though:
/// [FileManagerToolbarConfig.folderLayoutModes]/`folderGridAspectRatios`/
/// `folderSortModes` are keyed by `containerUri:dirPath` (see
/// [FileManagerToolbarConfig.folderKey]) -- genuinely per-container path
/// data, the exact thing excluded above. [_buildBundleJson] strips those
/// three maps before serializing so the exported file matches that claim
/// instead of silently carrying container URIs and folder paths out to
/// wherever the user saves/shares the export.
///
/// This is deliberately an injected service rather than a static utility:
/// settings backup is an app workflow with three dependencies. Keeping them
/// explicit makes the workflow provider-overridable and prevents a
/// non-widget caller from bypassing the Riverpod-owned service graph.
class SettingsBackupService {
  static const _schemaVersion = 3;

  factory SettingsBackupService({
    required AppSettingsService appSettingsService,
    required FileManagerToolbarService toolbarService,
    required VaultFileIoApi fileIoApi,
    required VaultPanicApi panicApi,
    required VaultLifecycleApi lifecycleApi,
  }) => SettingsBackupService._(
    appSettingsService,
    toolbarService,
    fileIoApi,
    panicApi,
    lifecycleApi,
  );

  const SettingsBackupService._(
    this._appSettingsService,
    this._toolbarService,
    this._fileIoApi,
    this._panicApi,
    this._lifecycleApi,
  );

  final AppSettingsService _appSettingsService;
  final FileManagerToolbarService _toolbarService;
  final VaultFileIoApi _fileIoApi;
  final VaultPanicApi _panicApi;
  final VaultLifecycleApi _lifecycleApi;

  Future<String> _buildBundleJson() async {
    final editorAppearance = await const TextEditorAppearanceService().load();
    final settings = await _appSettingsService.loadSettings();
    final toolbarConfig = await _toolbarService.load();
    final panicSettings = await _panicApi.getPanicSettings();
    final panicKit = await _panicApi.getPanicKitStatus();
    final shareTarget = await _lifecycleApi.isShareTargetEnabled();

    // See the class doc above: these three maps are per-container path
    // data (containerUri:dirPath keys), not app-wide preferences, so they
    // don't belong in a file meant to be portable/shareable. Strip them
    // rather than exporting them and relying on the import side to ignore
    // them -- a bundle sitting on cloud storage or in a chat attachment is
    // the actual point where this data shouldn't be present in the first
    // place.
    final exportableToolbarConfig = toolbarConfig.copyWith(
      folderLayoutModes: const {},
      folderGridAspectRatios: const {},
      folderSortModes: const {},
    );
    final exportableSettings = settings.copyWith(
      fileManagerSkin: toolbarConfig.skin,
      editorAppearancePrefs: editorAppearance.toJson(),
      appSkinSchemaVersion: 1,
    );

    final bundle = {
      'schemaVersion': _schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'appSettings': exportableSettings.toJson(),
      'fileManagerToolbar': exportableToolbarConfig.toJson(),
      'panicTier': panicSettings.configuredTier.level,
      'quickTileEnabled': panicSettings.quickTileEnabled,
      'panicKitEnabled': panicKit.responderEnabled,
      'panicKitEnforcement': panicKit.pairingEnforcementEnabled,
      'shareTargetEnabled': shareTarget,
    };
    return const JsonEncoder.withIndent('  ').convert(bundle);
  }

  /// Opens the system "save as" picker and writes the current settings +
  /// file-manager toolbar config to it. Returns false if the user
  /// cancelled or the write failed.
  Future<bool> exportToFile() async {
    final json = await _buildBundleJson();
    return _fileIoApi.exportAppSettingsFile(
      json,
      'vaultexplorer_settings.json',
    );
  }

  /// Opens the system file picker and parses the picked file as a
  /// settings bundle, without persisting anything yet -- callers should
  /// confirm with the user before calling [applyImportedBundle], since
  /// that overwrites the current settings. Returns null if the user
  /// cancelled the picker. Throws [InvalidSettingsBackupException] if the
  /// picked file isn't a recognizable bundle.
  Future<ImportedSettingsBundle?> pickAndParseFile() async {
    final raw = await _fileIoApi.importAppSettingsFile();
    if (raw == null) return null;

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw const InvalidSettingsBackupException(
        'That file is not a valid settings export.',
      );
    }

    final appSettingsJson = decoded['appSettings'];
    final toolbarJson = decoded['fileManagerToolbar'];
    if (appSettingsJson is! Map<String, dynamic> ||
        toolbarJson is! Map<String, dynamic>) {
      throw const InvalidSettingsBackupException(
        'That file is not a valid settings export.',
      );
    }

    final panicTierLevel = decoded['panicTier'] as int?;

    return ImportedSettingsBundle(
      appSettings: AppSettings.fromJson(appSettingsJson),
      toolbarConfig: FileManagerToolbarConfig.fromJson(toolbarJson),
      panicTier: panicTierLevel != null
          ? PanicTier.fromLevel(panicTierLevel)
          : null,
      quickTileEnabled: decoded['quickTileEnabled'] as bool?,
      panicKitEnabled: decoded['panicKitEnabled'] as bool?,
      panicKitEnforcement: decoded['panicKitEnforcement'] as bool?,
      shareTargetEnabled: decoded['shareTargetEnabled'] as bool?,
    );
  }

  /// Persists a bundle already returned by [pickAndParseFile], overwriting
  /// the current [AppSettings], toolbar config, panic settings, and share target.
  Future<void> applyImportedBundle(ImportedSettingsBundle bundle) async {
    // Older exports predate app-skin settings and editor appearance backup.
    // Keep this device's editor choices when importing one, and migrate the
    // file-manager skin from the bundled toolbar config without losing it.
    await const TextEditorAppearanceService().load();
    final currentSettings = await _appSettingsService.loadSettings();
    final importedSettings = bundle.appSettings.copyWith(
      fileManagerSkin: bundle.toolbarConfig.skin,
      editorAppearancePrefs: bundle.appSettings.editorAppearancePrefs.isNotEmpty
          ? bundle.appSettings.editorAppearancePrefs
          : currentSettings.editorAppearancePrefs,
      fileManagerFollowsAppSkin: bundle.appSettings.appSkinSchemaVersion < 1
          ? false
          : bundle.appSettings.fileManagerFollowsAppSkin,
      editorFollowsAppSkin: bundle.appSettings.appSkinSchemaVersion < 1
          ? false
          : bundle.appSettings.editorFollowsAppSkin,
      appSkinSchemaVersion: 1,
    );
    await _appSettingsService.replaceSettings(importedSettings);
    await _toolbarService.save(bundle.toolbarConfig);
    if (bundle.panicTier != null) {
      await _panicApi.setPanicTier(bundle.panicTier!);
    }
    if (bundle.quickTileEnabled != null) {
      await _panicApi.setQuickTileEnabled(bundle.quickTileEnabled!);
    }
    if (bundle.panicKitEnabled != null) {
      await _panicApi.setPanicKitEnabled(bundle.panicKitEnabled!);
    }
    if (bundle.panicKitEnforcement != null) {
      await _panicApi.setPanicKitPairingEnforcement(
        bundle.panicKitEnforcement!,
      );
    }
    if (bundle.shareTargetEnabled != null) {
      await _lifecycleApi.setShareTargetEnabled(bundle.shareTargetEnabled!);
    }
  }
}
