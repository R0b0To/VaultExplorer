// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AppSettingsController)
final appSettingsControllerProvider = AppSettingsControllerProvider._();

final class AppSettingsControllerProvider
    extends $NotifierProvider<AppSettingsController, AppSettingsViewState> {
  AppSettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appSettingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appSettingsControllerHash();

  @$internal
  @override
  AppSettingsController create() => AppSettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppSettingsViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppSettingsViewState>(value),
    );
  }
}

String _$appSettingsControllerHash() =>
    r'fb7b832dbe0af2b0f0adcfe05fa0c498830be4bf';

abstract class _$AppSettingsController extends $Notifier<AppSettingsViewState> {
  AppSettingsViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AppSettingsViewState, AppSettingsViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppSettingsViewState, AppSettingsViewState>,
              AppSettingsViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
