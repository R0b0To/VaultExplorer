// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_destination_picker_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LocalDestinationPicker)
final localDestinationPickerProvider = LocalDestinationPickerFamily._();

final class LocalDestinationPickerProvider
    extends
        $NotifierProvider<LocalDestinationPicker, LocalDestinationPickerState> {
  LocalDestinationPickerProvider._({
    required LocalDestinationPickerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'localDestinationPickerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$localDestinationPickerHash();

  @override
  String toString() {
    return r'localDestinationPickerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  LocalDestinationPicker create() => LocalDestinationPicker();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocalDestinationPickerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocalDestinationPickerState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LocalDestinationPickerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$localDestinationPickerHash() =>
    r'b5021e23bc12e44c31f3c78e1f5ed613d3811dc1';

final class LocalDestinationPickerFamily extends $Family
    with
        $ClassFamilyOverride<
          LocalDestinationPicker,
          LocalDestinationPickerState,
          LocalDestinationPickerState,
          LocalDestinationPickerState,
          (String, String)
        > {
  LocalDestinationPickerFamily._()
    : super(
        retry: null,
        name: r'localDestinationPickerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LocalDestinationPickerProvider call(String rootLabel, String rootPath) =>
      LocalDestinationPickerProvider._(
        argument: (rootLabel, rootPath),
        from: this,
      );

  @override
  String toString() => r'localDestinationPickerProvider';
}

abstract class _$LocalDestinationPicker
    extends $Notifier<LocalDestinationPickerState> {
  late final _$args = ref.$arg as (String, String);
  String get rootLabel => _$args.$1;
  String get rootPath => _$args.$2;

  LocalDestinationPickerState build(String rootLabel, String rootPath);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<LocalDestinationPickerState, LocalDestinationPickerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                LocalDestinationPickerState,
                LocalDestinationPickerState
              >,
              LocalDestinationPickerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
