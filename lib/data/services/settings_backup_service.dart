import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/quick_capture_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/api/vault_panic_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/skin_backup_service.dart';

part 'settings_backup_service.g.dart';

/// Settings backup is used from a screen but composes services that have no
/// widget context of their own. Providing that composition keeps its file I/O
/// and persisted-settings dependencies overrideable in tests.
@Riverpod(keepAlive: true)
SettingsBackupService settingsBackupService(Ref ref) => SettingsBackupService(
  appSettingsService: ref.watch(appSettingsServiceProvider),
  toolbarService: ref.watch(fileManagerToolbarServiceProvider),
  skinBackupService: ref.watch(skinBackupServiceProvider),
  fileIoApi: ref.watch(vaultFileIoApiProvider),
  panicApi: ref.watch(vaultPanicApiProvider),
  lifecycleApi: ref.watch(vaultLifecycleApiProvider),
  quickCaptureApi: ref.watch(quickCaptureApiProvider),
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
/// [appSettings] and [toolbarConfig] are *partial* for a current file: only
/// their configuration/behavior fields are meaningful and the rest are
/// defaults, which [SettingsBackupService.applyImportedBundle] never copies.
/// The look and layout of a current file travel in [interfaceSettings], and
/// the optional theme library in [skins]. For an export made before
/// appearance was split off ([includesInterface] is true) [appSettings] and
/// [toolbarConfig] are the complete old snapshot.
class ImportedSettingsBundle {
  final AppSettings appSettings;
  final FileManagerToolbarConfig toolbarConfig;
  final bool includesInterface;

  /// Look and layout of the app, file manager, media viewer and text editor.
  /// Null for a file that only carries configuration (schema 4).
  final ImportedInterface? interfaceSettings;

  /// The custom themes the file was exported with. Null when it was exported
  /// without themes.
  final List<CustomAppSkin>? skins;

  final PanicTier? panicTier;
  final bool? quickTileEnabled;
  final bool? panicKitEnabled;
  final bool? panicKitEnforcement;
  final bool? shareTargetEnabled;
  final bool? usbAttachPromptEnabled;
  final bool? quickCaptureTileEnabled;

  const ImportedSettingsBundle({
    required this.appSettings,
    required this.toolbarConfig,
    this.includesInterface = false,
    this.interfaceSettings,
    this.skins,
    this.panicTier,
    this.quickTileEnabled,
    this.panicKitEnabled,
    this.panicKitEnforcement,
    this.shareTargetEnabled,
    this.usbAttachPromptEnabled,
    this.quickCaptureTileEnabled,
  });

  /// Whether applying this file also replaces look and layout, not just
  /// behavior. The caller words its confirmation dialog from this.
  bool get restoresInterface => includesInterface || interfaceSettings != null;

  /// Whether the file carries custom themes that will be added to the library.
  bool get hasThemes => skins != null && skins!.isNotEmpty;
}

/// What is persisted after an import, so the caller can push the real values
/// into live state instead of the partial ones inside the bundle.
class AppliedSettings {
  final AppSettings settings;
  final FileManagerToolbarConfig toolbarConfig;

  const AppliedSettings({required this.settings, required this.toolbarConfig});
}

/// Settings -> Export/Import: one plain-JSON file, saved/loaded through the
/// system document picker, that holds everything a person configured:
///
/// * app settings -- security and lock behavior, defaults, playback and import
///   handling, language, theme mode and the other app-level options;
/// * file manager settings -- behavior options plus toolbar, list/grid sizing,
///   item actions, detail columns and the file skin;
/// * media player settings -- gestures, playback, decoders, equalizer, and the
///   viewer's button layout;
/// * text editor settings -- appearance, accessory bar, auto-save, font size;
/// * optionally ([exportToFile]'s `includeThemes`) the custom app themes.
///
/// The file is two halves that already exist elsewhere: the configuration half
/// ([AppSettings.configurationToJson], [FileManagerToolbarConfig.behaviorToJson])
/// and the `interface` section that App skin -> Export can also write
/// ([SkinBackupService.buildInterfaceSection]). Reusing that section means a
/// restore goes through the same, tested apply path as a skin file.
///
/// App skin -> Export is still the way to share themes on their own.
///
/// Deliberately never exported, because it is a credential or belongs to one
/// container or file rather than to the app:
///
/// * the master password, pattern and PIN hashes and the duress credentials;
/// * the automation API token and its per-vault stored passwords, and whether
///   the wipe-on-reboot trigger is armed;
/// * container records, bookmarks and pins ([ContainerRepository]);
/// * per-folder memory ([FileManagerToolbarConfig.perFolderKeys]), camera
///   capture state and saved playback positions.
///
/// Files written before the split (schema 3 and older) carried everything in
/// one snapshot, and files from schema 4 only the configuration half. Both are
/// still read.
///
/// This is deliberately an injected service rather than a static utility:
/// settings backup is an app workflow with several dependencies. Keeping them
/// explicit makes the workflow provider-overridable and prevents a
/// non-widget caller from bypassing the Riverpod-owned service graph.
class SettingsBackupService {
  /// 5: adds the `interface` section (and, optionally, `skins`) so that one
  /// file holds the whole configuration, plus `usbAttachPromptEnabled` and
  /// `quickCaptureTileEnabled`. 4 split appearance off into the skin export
  /// and renamed `fileManagerToolbar` to `fileManagerBehavior`. Older files are
  /// recognized by their keys (see [pickAndParseFile]), not by this number.
  static const _schemaVersion = 5;

  factory SettingsBackupService({
    required AppSettingsService appSettingsService,
    required FileManagerToolbarService toolbarService,
    required SkinBackupService skinBackupService,
    required VaultFileIoApi fileIoApi,
    required VaultPanicApi panicApi,
    required VaultLifecycleApi lifecycleApi,
    required QuickCaptureApi quickCaptureApi,
  }) => SettingsBackupService._(
    appSettingsService,
    toolbarService,
    skinBackupService,
    fileIoApi,
    panicApi,
    lifecycleApi,
    quickCaptureApi,
  );

  const SettingsBackupService._(
    this._appSettingsService,
    this._toolbarService,
    this._skinBackupService,
    this._fileIoApi,
    this._panicApi,
    this._lifecycleApi,
    this._quickCaptureApi,
  );

  final AppSettingsService _appSettingsService;
  final FileManagerToolbarService _toolbarService;
  final SkinBackupService _skinBackupService;
  final VaultFileIoApi _fileIoApi;
  final VaultPanicApi _panicApi;
  final VaultLifecycleApi _lifecycleApi;
  final QuickCaptureApi _quickCaptureApi;

  Future<String> _buildBundleJson({required bool includeThemes}) async {
    final settings = await _appSettingsService.loadSettings();
    final toolbarConfig = await _toolbarService.load();
    final panicSettings = await _panicApi.getPanicSettings();
    final panicKit = await _panicApi.getPanicKitStatus();
    final shareTarget = await _lifecycleApi.isShareTargetEnabled();
    final usbAttachPrompt = await _lifecycleApi.isUsbAttachPromptEnabled();
    final quickCapture = await _quickCaptureApi.getQuickCaptureSettings();
    final interfaceSection = await _skinBackupService.buildInterfaceSection();

    final bundle = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'appSettings': settings.configurationToJson(),
      'fileManagerBehavior': toolbarConfig.behaviorToJson(),
      // Look and layout of the app, file manager, media viewer and text
      // editor. Same section, same reader, as App skin -> Export.
      'interface': interfaceSection,
      if (includeThemes)
        'skins': settings.customAppSkins.map((skin) => skin.toJson()).toList(),
      'panicTier': panicSettings.configuredTier.level,
      'quickTileEnabled': panicSettings.quickTileEnabled,
      'panicKitEnabled': panicKit.responderEnabled,
      'panicKitEnforcement': panicKit.pairingEnforcementEnabled,
      'shareTargetEnabled': shareTarget,
      'usbAttachPromptEnabled': usbAttachPrompt,
      'quickCaptureTileEnabled': quickCapture.tileEnabled,
    };
    return const JsonEncoder.withIndent('  ').convert(bundle);
  }

  /// Opens the system "save as" picker and writes the current configuration
  /// to it. With [includeThemes] the file also carries the custom app skins;
  /// without it the active skin is still recorded, and is only re-selected on
  /// import when the importing device has it. Returns false if the user
  /// cancelled or the write failed.
  Future<bool> exportToFile({bool includeThemes = false}) async {
    final json = await _buildBundleJson(includeThemes: includeThemes);
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

    const invalid = InvalidSettingsBackupException(
      'That file is not a valid settings export.',
    );

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw invalid;
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
      throw invalid;
    }

    // Schema 5 adds the look-and-layout section and, optionally, the themes.
    // Files without them (schema 4) simply leave this device's look alone.
    ImportedInterface? interfaceSettings;
    if (decoded.containsKey('interface')) {
      try {
        interfaceSettings = parseInterfaceSection(decoded['interface']);
      } catch (_) {
        throw invalid;
      }
    }
    List<CustomAppSkin>? skins;
    if (decoded.containsKey('skins')) {
      try {
        skins = parseSkinList(decoded['skins']);
      } catch (_) {
        throw invalid;
      }
    }

    final panicTierLevel = decoded['panicTier'] as int?;

    return ImportedSettingsBundle(
      appSettings: AppSettings.fromJson(appSettingsJson),
      toolbarConfig: FileManagerToolbarConfig.fromJson(toolbarJson),
      includesInterface: includesInterface,
      interfaceSettings: interfaceSettings,
      skins: skins,
      panicTier: panicTierLevel != null
          ? PanicTier.fromLevel(panicTierLevel)
          : null,
      quickTileEnabled: decoded['quickTileEnabled'] as bool?,
      panicKitEnabled: decoded['panicKitEnabled'] as bool?,
      panicKitEnforcement: decoded['panicKitEnforcement'] as bool?,
      shareTargetEnabled: decoded['shareTargetEnabled'] as bool?,
      usbAttachPromptEnabled: decoded['usbAttachPromptEnabled'] as bool?,
      quickCaptureTileEnabled: decoded['quickCaptureTileEnabled'] as bool?,
    );
  }

  /// Persists a bundle already returned by [pickAndParseFile].
  ///
  /// The configuration half always replaces this device's. A current file's
  /// `interface` section then replaces its look and layout through
  /// [SkinBackupService.applyInterface], after any themes in the file have been
  /// added to the skin library so the recorded active skin can resolve to one
  /// of them. A file without those parts (schema 4) leaves the look, layout and
  /// skins exactly as they are, and a bundle from before the split
  /// ([ImportedSettingsBundle.includesInterface]) replaces everything it
  /// carried, as it always did.
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
        collapsedBookmarkGroupUris: currentToolbar.collapsedBookmarkGroupUris,
      );
    } else {
      toolbar = currentToolbar.withBehaviorFrom(importedToolbar);
    }

    var settings = await _appSettingsService.updateSettings((current) {
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
    var appliedToolbar = toolbar;

    // Themes first, so the active skin recorded in the interface section can
    // resolve to one of them.
    final skins = bundle.skins;
    if (skins != null && skins.isNotEmpty) {
      settings = await _appSettingsService.updateSettings(
        (current) => _withSkins(current, skins),
      );
    }
    final importedInterface = bundle.interfaceSettings;
    if (importedInterface != null) {
      final applied = await _skinBackupService.applyInterface(
        importedInterface,
      );
      settings = applied.settings;
      appliedToolbar = applied.toolbarConfig;
    }

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
    if (bundle.usbAttachPromptEnabled != null) {
      await _lifecycleApi.setUsbAttachPromptEnabled(
        bundle.usbAttachPromptEnabled!,
      );
    }
    if (bundle.quickCaptureTileEnabled != null) {
      await _quickCaptureApi.setQuickCaptureTileEnabled(
        bundle.quickCaptureTileEnabled!,
      );
    }
    return AppliedSettings(settings: settings, toolbarConfig: appliedToolbar);
  }

  /// Adds [imported] to the skin library, replacing a skin that has the same
  /// id. Unlike App skin -> Import, which always adds a copy, a restore must be
  /// repeatable: importing your own backup again must not duplicate every
  /// theme. The active custom skin is refreshed when its library entry was
  /// replaced, so the two never disagree.
  static AppSettings _withSkins(
    AppSettings current,
    List<CustomAppSkin> imported,
  ) {
    final library = [...current.customAppSkins];
    for (final skin in imported) {
      final index = library.indexWhere((saved) => saved.id == skin.id);
      if (index < 0) {
        library.add(skin);
      } else {
        library[index] = skin;
      }
    }
    final active = current.customAppSkin;
    return current.copyWith(
      customAppSkins: library,
      customAppSkin: library.firstWhere(
        (skin) => skin.id == active.id,
        orElse: () => active,
      ),
    );
  }
}
