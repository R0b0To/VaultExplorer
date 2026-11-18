// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'advanced_rename_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AdvancedRenameForm)
final advancedRenameFormProvider = AdvancedRenameFormProvider._();

final class AdvancedRenameFormProvider
    extends $NotifierProvider<AdvancedRenameForm, AdvancedRenameFormState> {
  AdvancedRenameFormProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'advancedRenameFormProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$advancedRenameFormHash();

  @$internal
  @override
  AdvancedRenameForm create() => AdvancedRenameForm();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AdvancedRenameFormState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AdvancedRenameFormState>(value),
    );
  }
}

String _$advancedRenameFormHash() =>
    r'c06d9db7ad526bc96f8f7f52d6106311c8f3eb09';

abstract class _$AdvancedRenameForm extends $Notifier<AdvancedRenameFormState> {
  AdvancedRenameFormState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AdvancedRenameFormState, AdvancedRenameFormState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AdvancedRenameFormState, AdvancedRenameFormState>,
              AdvancedRenameFormState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
