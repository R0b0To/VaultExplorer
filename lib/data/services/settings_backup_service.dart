import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/api/vault_panic_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';

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

/// A settings file parsed but not yet applied.
///
/// For a current export [appSettings] and [toolbarConfig] are *partial*: only
/// their configuration/behavior fields are meaningful and the rest are
/// defaults, which [SettingsBackupService.applyImportedBundle] never copies.
/// For an export made before appearance moved to App skin -> Export
/// ([includesInterface] is true) they are the complete old snapshot.
class ImportedSettingsBundle {
  final AppSettings appSettings;
  final FileManagerToolbarConfig toolbarConfig;
  final bool includesInterface;
  final PanicTier? panicTier;
  final bool? quickTileEnabled;
  final bool? panicKitEnabled;
  final bool? panicKitEnforcement;
  final bool? shareTargetEnabled;

  const ImportedSettingsBundle({
    required this.appSettings,
    required this.toolbarConfig,
    this.includesInterface = false,
    this.panicTier,
    this.quickTileEnabled,
    this.panicKitEnabled,
    this.panicKitEnforcement,
    this.shareTargetEnabled,
  });
}

/// What is persisted after an import, so the caller can push the real values
/// into live state instead of the partial ones inside the bundle.
class AppliedSettings {
  final AppSettings settings;
  final FileManagerToolbarConfig toolbarConfig;

  const AppliedSettings({required this.settings, required this.toolbarConfig});
}

/// Settings -> Export/Import: bundles the app's *configuration* -- security
/// and lock behavior, defaults, playback/import handling, language and the
/// file manager's behavior options -- into one plain-JSON file the user
/// saves/loads through the system document picker.
///
/// Everything about how the app *looks or is laid out* is deliberately not in
/// here. Skins, theme mode, toolbar layout, grid/list sizing, editor
/// appearance and the media viewer's button layout travel with
/// App skin -> Export ([SkinBackupService]) instead, so each file has one
/// meaning: this one is "how the app behaves", that one is "how it looks".
/// [AppSettings.configurationToJson] and
/// [FileManagerToolbarConfig.behaviorToJson] define the split.
///
/// Also excluded, as before: anything security-sensitive or per-container.
/// The master password hash/salt never enter [AppSettings.toJson] in the first
/// place, and container records (bookmarks/pinned paths and keystore material,
/// see [ContainerRepository]) are out of scope entirely. The per-folder
/// per-container UI memory ([FileManagerToolbarConfig.perFolderKeys]) is never
/// part of either export. It includes path layouts keyed by
/// `containerUri:dirPath` and collapsed bookmark groups keyed by container
/// URI.
///
/// Files written before the split (schema 3 and older) carried everything.
/// They are still restored in full, so an old backup keeps working.
///
/// This is deliberately an injected service rather than a static utility:
/// settings backup is an app workflow with five dependencies. Keeping them
/// explicit makes the workflow provider-overridable and prevents a
/// non-widget caller from bypassing the Riverpod-owned service graph.
class SettingsBackupService {
  /// 4: appearance moved to the skin export, and `fileManagerToolbar` became
  /// `fileManagerBehavior`. Older files are recognized by that key (see
  /// [pickAndParseFile]), not by this number.
  static const _schemaVersion = 4;

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
    final settings = await _appSettingsService.loadSettings();
    final toolbarConfig = await _toolbarService.load();
    final panicSettings = await _panicApi.getPanicSettings();
    final panicKit = await _panicApi.getPanicKitStatus();
    final shareTarget = await _lifecycleApi.isShareTargetEnabled();

    final bundle = {
      'schemaVersion': _schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'appSettings': settings.configurationToJson(),
      'fileManagerBehavior': toolbarConfig.behaviorToJson(),
      'panicTier': panicSettings.configuredTier.level,
      'quickTileEnabled': panicSettings.quickTileEnabled,
      'panicKitEnabled': panicKit.responderEnabled,
      'panicKitEnforcement': panicKit.pairingEnforcementEnabled,
      'shareTargetEnabled': shareTarget,
    };
    return const JsonEncoder.withIndent('  ').convert(bundle);
  }

  /// Opens the system "save as" picker and writes the current configuration
  /// to it. Returns false if the user cancelled or the write failed.
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
    // Schema 3 and older stored the whole toolbar config under
    // `fileManagerToolbar`; newer files store only its behavior options.
    final legacyToolbarJson = decoded['fileManagerToolbar'];
    final behaviorJson = decoded['fileManagerBehavior'];
    final includesInterface = legacyToolbarJson is Map<String, dynamic>;
    final toolbarJson = includesInterface ? legacyToolbarJson : behaviorJson;
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
      includesInterface: includesInterface,
      panicTier: panicTierLevel != null
          ? PanicTier.fromLevel(panicTierLevel)
          : null,
      quickTileEnabled: decoded['quickTileEnabled'] as bool?,
      panicKitEnabled: decoded['panicKitEnabled'] as bool?,
      panicKitEnforcement: decoded['panicKitEnforcement'] as bool?,
      shareTargetEnabled: decoded['shareTargetEnabled'] as bool?,
    );
  }

  /// Persists a bundle already returned by [pickAndParseFile].
  ///
  /// A current bundle only replaces this device's configuration; skins and
  /// the interface layout are left exactly as they are. A bundle from before
  /// the split ([ImportedSettingsBundle.includesInterface]) replaces
  /// everything it carried, as it always did.
  ///
  /// Per-folder layout memory on this device is kept either way: exports never
  /// contain it, so importing one must not wipe it.
  Future<AppliedSettings> applyImportedBundle(
    ImportedSettingsBundle bundle,
  ) async {
    final currentToolbar = await _toolbarService.load();
    final importedToolbar = bundle.toolbarConfig;
    final FileManagerToolbarConfig toolbar;
    if (bundle.includesInterface) {
      toolbar = importedToolbar.copyWith(
        folderLayoutModes: currentToolbar.folderLayoutModes,
        folderGridAspectRatios: currentToolbar.folderGridAspectRatios,
        folderSortModes: currentToolbar.folderSortModes,
        collapsedBookmarkGroupUris:
            currentToolbar.collapsedBookmarkGroupUris,
      );
    } else {
      toolbar = currentToolbar.withBehaviorFrom(importedToolbar);
    }

    final settings = await _appSettingsService.updateSettings((current) {
      final imported = bundle.appSettings;
      if (!bundle.includesInterface) {
        return current.withConfigurationFrom(imported);
      }
      // Pre-split bundle: take everything it carried. Exports that predate
      // app skins have no follow-the-app-skin flags and keep their own
      // file-manager/editor looks; older ones also lack editor preferences,
      // which then stay as this device has them.
      final predatesAppSkins = imported.appSkinSchemaVersion < 1;
      return current
          .withConfigurationFrom(imported)
          .withInterfaceFrom(imported)
          .copyWith(
            appSkinPreset: imported.appSkinPreset,
            useOledBlackTheme: imported.useOledBlackTheme,
            customAppSkin: imported.customAppSkin,
            customAppSkins: imported.customAppSkins,
            fileManagerSkin: toolbar.skin,
            editorAppearancePrefs: imported.editorAppearancePrefs.isNotEmpty
                ? imported.editorAppearancePrefs
                : current.editorAppearancePrefs,
            fileManagerFollowsAppSkin: predatesAppSkins
                ? false
                : imported.fileManagerFollowsAppSkin,
            editorFollowsAppSkin: predatesAppSkins
                ? false
                : imported.editorFollowsAppSkin,
            appSkinSchemaVersion: 1,
          );
    });
    await _toolbarService.save(toolbar);

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
    return AppliedSettings(settings: settings, toolbarConfig: toolbar);
  }
}
