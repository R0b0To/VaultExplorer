// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'change_password_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ChangePassword)
final changePasswordProvider = ChangePasswordFamily._();

final class ChangePasswordProvider
    extends $NotifierProvider<ChangePassword, ChangePasswordState> {
  ChangePasswordProvider._({
    required ChangePasswordFamily super.from,
    required (String, String, int, int) super.argument,
  }) : super(
         retry: null,
         name: r'changePasswordProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$changePasswordHash();

  @override
  String toString() {
    return r'changePasswordProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ChangePassword create() => ChangePassword();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChangePasswordState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChangePasswordState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChangePasswordProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$changePasswordHash() => r'2e7f52758244902820fe392fe772a278c36698d3';

final class ChangePasswordFamily extends $Family
    with
        $ClassFamilyOverride<
          ChangePassword,
          ChangePasswordState,
          ChangePasswordState,
          ChangePasswordState,
          (String, String, int, int)
        > {
  ChangePasswordFamily._()
    : super(
        retry: null,
        name: r'changePasswordProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ChangePasswordProvider call(
    String uri,
    String containerFormat,
    int initialCipherId,
    int initialHashId,
  ) => ChangePasswordProvider._(
    argument: (uri, containerFormat, initialCipherId, initialHashId),
    from: this,
  );

  @override
  String toString() => r'changePasswordProvider';
}

abstract class _$ChangePassword extends $Notifier<ChangePasswordState> {
  late final _$args = ref.$arg as (String, String, int, int);
  String get uri => _$args.$1;
  String get containerFormat => _$args.$2;
  int get initialCipherId => _$args.$3;
  int get initialHashId => _$args.$4;

  ChangePasswordState build(
    String uri,
    String containerFormat,
    int initialCipherId,
    int initialHashId,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ChangePasswordState, ChangePasswordState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ChangePasswordState, ChangePasswordState>,
              ChangePasswordState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3, _$args.$4),
    );
  }
}
