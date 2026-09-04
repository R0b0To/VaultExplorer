// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_backup_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Settings backup is used from a screen but composes services that have no
/// widget context of their own. Providing that composition keeps its file I/O
/// and persisted-settings dependencies overrideable in tests.

@ProviderFor(settingsBackupService)
final settingsBackupServiceProvider = SettingsBackupServiceProvider._();

/// Settings backup is used from a screen but composes services that have no
/// widget context of their own. Providing that composition keeps its file I/O
/// and persisted-settings dependencies overrideable in tests.

final class SettingsBackupServiceProvider
    extends
        $FunctionalProvider<
          SettingsBackupService,
          SettingsBackupService,
          SettingsBackupService
        >
    with $Provider<SettingsBackupService> {
  /// Settings backup is used from a screen but composes services that have no
  /// widget context of their own. Providing that composition keeps its file I/O
  /// and persisted-settings dependencies overrideable in tests.
  SettingsBackupServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsBackupServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsBackupServiceHash();

  @$internal
  @override
  $ProviderElement<SettingsBackupService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SettingsBackupService create(Ref ref) {
    return settingsBackupService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsBackupService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsBackupService>(value),
    );
  }
}

String _$settingsBackupServiceHash() =>
    r'7ae5e0ca8564e6b154f62b57cde7ee4c242111a5';
