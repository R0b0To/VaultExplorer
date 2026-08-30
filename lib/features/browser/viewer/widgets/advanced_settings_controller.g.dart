// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'advanced_settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AdvancedSettingsController)
final advancedSettingsControllerProvider = AdvancedSettingsControllerFamily._();

final class AdvancedSettingsControllerProvider
    extends
        $NotifierProvider<AdvancedSettingsController, AdvancedSettingsState> {
  AdvancedSettingsControllerProvider._({
    required AdvancedSettingsControllerFamily super.from,
    required AdvancedSettingsParams super.argument,
  }) : super(
         retry: null,
         name: r'advancedSettingsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$advancedSettingsControllerHash();

  @override
  String toString() {
    return r'advancedSettingsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AdvancedSettingsController create() => AdvancedSettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AdvancedSettingsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AdvancedSettingsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AdvancedSettingsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$advancedSettingsControllerHash() =>
    r'3262b7c43df934422117cb925d0f4ce20181e003';

final class AdvancedSettingsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AdvancedSettingsController,
          AdvancedSettingsState,
          AdvancedSettingsState,
          AdvancedSettingsState,
          AdvancedSettingsParams
        > {
  AdvancedSettingsControllerFamily._()
    : super(
        retry: null,
        name: r'advancedSettingsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AdvancedSettingsControllerProvider call(AdvancedSettingsParams params) =>
      AdvancedSettingsControllerProvider._(argument: params, from: this);

  @override
  String toString() => r'advancedSettingsControllerProvider';
}

abstract class _$AdvancedSettingsController
    extends $Notifier<AdvancedSettingsState> {
  late final _$args = ref.$arg as AdvancedSettingsParams;
  AdvancedSettingsParams get params => _$args;

  AdvancedSettingsState build(AdvancedSettingsParams params);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AdvancedSettingsState, AdvancedSettingsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AdvancedSettingsState, AdvancedSettingsState>,
              AdvancedSettingsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
