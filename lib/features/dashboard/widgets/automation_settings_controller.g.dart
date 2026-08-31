// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AutomationSettings)
final automationSettingsProvider = AutomationSettingsFamily._();

final class AutomationSettingsProvider
    extends $NotifierProvider<AutomationSettings, AutomationSettingsState> {
  AutomationSettingsProvider._({
    required AutomationSettingsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'automationSettingsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$automationSettingsHash();

  @override
  String toString() {
    return r'automationSettingsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  AutomationSettings create() => AutomationSettings();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AutomationSettingsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AutomationSettingsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AutomationSettingsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$automationSettingsHash() =>
    r'1fa496df57c06f44a07a267f002a1c6efb1b4ae6';

final class AutomationSettingsFamily extends $Family
    with
        $ClassFamilyOverride<
          AutomationSettings,
          AutomationSettingsState,
          AutomationSettingsState,
          AutomationSettingsState,
          (String, String)
        > {
  AutomationSettingsFamily._()
    : super(
        retry: null,
        name: r'automationSettingsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AutomationSettingsProvider call(String uri, String containerFormat) =>
      AutomationSettingsProvider._(
        argument: (uri, containerFormat),
        from: this,
      );

  @override
  String toString() => r'automationSettingsProvider';
}

abstract class _$AutomationSettings extends $Notifier<AutomationSettingsState> {
  late final _$args = ref.$arg as (String, String);
  String get uri => _$args.$1;
  String get containerFormat => _$args.$2;

  AutomationSettingsState build(String uri, String containerFormat);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AutomationSettingsState, AutomationSettingsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AutomationSettingsState, AutomationSettingsState>,
              AutomationSettingsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
