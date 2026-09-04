// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(appSettingsService)
final appSettingsServiceProvider = AppSettingsServiceProvider._();

final class AppSettingsServiceProvider
    extends
        $FunctionalProvider<
          AppSettingsService,
          AppSettingsService,
          AppSettingsService
        >
    with $Provider<AppSettingsService> {
  AppSettingsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appSettingsServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appSettingsServiceHash();

  @$internal
  @override
  $ProviderElement<AppSettingsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppSettingsService create(Ref ref) {
    return appSettingsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppSettingsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppSettingsService>(value),
    );
  }
}

String _$appSettingsServiceHash() =>
    r'4dbeefa668ea01b87e0aee909479f9d965efda61';
