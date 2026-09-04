// Provider access to long-lived services and compatibility bridges.
//
// ContainerRepository and FileOperationService are constructed here with
// explicit engine dependencies. They remain keep-alive mutable services while
// their remaining stateful consumers are migrated; converting either into a
// state-bearing Notifier is a follow-up, not a prerequisite for dependency
// injection.
//
// ThumbnailCacheService intentionally keeps its process-wide in-memory cache,
// but receives its typed engine APIs during application bootstrap. Static
// bootstrap-only callers therefore remain valid.
//
// FileManagerToolbarService is constructed here as a keep-alive service. Its
// persisted configuration is represented reactively by
// FileManagerToolbarSettings where the UI needs to observe it.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/logcat_service.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/data/services/settings_backup_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/core/utils/sensitive_clipboard.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';

part 'legacy_services_providers.g.dart';

@Riverpod(keepAlive: true)
ContainerRepository containerRepository(Ref ref) =>
    ContainerRepository.withCryptoApi(ref.watch(vaultCryptoApiProvider));

@Riverpod(keepAlive: true)
Raw<FileOperationService> fileOperationService(Ref ref) =>
    FileOperationService.withEngineApis(
      engineEvents: ref.watch(vaultEngineEventsProvider),
      fileIoApi: ref.watch(vaultFileIoApiProvider),
      lifecycleApi: ref.watch(vaultLifecycleApiProvider),
    );

@Riverpod(keepAlive: true)
ContainerToolService containerToolService(Ref ref) =>
    NativeContainerToolService(
      ref.watch(vaultEngineEventsProvider),
      ref.watch(vaultFileIoApiProvider),
      ref.watch(vaultLifecycleApiProvider),
      ref.watch(vaultSplitJoinApiProvider),
      ref.watch(vaultRepairApiProvider),
      ref.watch(vaultHashApiProvider),
    );

@Riverpod(keepAlive: true)
FileManagerToolbarService fileManagerToolbarService(Ref ref) =>
    FileManagerToolbarService();

@Riverpod(keepAlive: true)
AppSettingsService appSettingsService(Ref ref) => const AppSettingsService();

@Riverpod(keepAlive: true)
LogcatService logcatService(Ref ref) => const LogcatService();

@Riverpod(keepAlive: true)
PasswordHasher passwordHasher(Ref ref) =>
    PasswordHasher(ref.watch(vaultCryptoApiProvider));

@Riverpod(keepAlive: true)
SecureScreenPolicy secureScreenPolicy(Ref ref) =>
    SecureScreenPolicy(ref.watch(vaultFileIoApiProvider));

@Riverpod(keepAlive: true)
SensitiveClipboard sensitiveClipboard(Ref ref) =>
    SensitiveClipboard(ref.watch(vaultFileIoApiProvider));

@Riverpod(keepAlive: true)
ThumbnailCacheService thumbnailCacheService(Ref ref) =>
    const ThumbnailCacheService();

/// Settings backup is used from a screen but composes services that have no
/// widget context of their own. Providing that composition keeps its file I/O
/// and persisted-settings dependencies overrideable in tests.
@Riverpod(keepAlive: true)
SettingsBackupService settingsBackupService(Ref ref) => SettingsBackupService(
  appSettingsService: ref.watch(appSettingsServiceProvider),
  toolbarService: ref.watch(fileManagerToolbarServiceProvider),
  fileIoApi: ref.watch(vaultFileIoApiProvider),
);