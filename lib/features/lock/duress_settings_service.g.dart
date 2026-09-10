// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'duress_settings_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(duressSettingsService)
final duressSettingsServiceProvider = DuressSettingsServiceProvider._();

final class DuressSettingsServiceProvider
    extends
        $FunctionalProvider<
          DuressSettingsService,
          DuressSettingsService,
          DuressSettingsService
        >
    with $Provider<DuressSettingsService> {
  DuressSettingsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'duressSettingsServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$duressSettingsServiceHash();

  @$internal
  @override
  $ProviderElement<DuressSettingsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DuressSettingsService create(Ref ref) {
    return duressSettingsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DuressSettingsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DuressSettingsService>(value),
    );
  }
}

String _$duressSettingsServiceHash() =>
    r'e9275cb39b6ccfc1940d1fda8b759ba42d002547';
