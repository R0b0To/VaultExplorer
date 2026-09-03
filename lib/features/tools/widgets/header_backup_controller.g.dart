// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'header_backup_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(HeaderBackup)
final headerBackupProvider = HeaderBackupProvider._();

final class HeaderBackupProvider
    extends $NotifierProvider<HeaderBackup, HeaderBackupState> {
  HeaderBackupProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'headerBackupProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$headerBackupHash();

  @$internal
  @override
  HeaderBackup create() => HeaderBackup();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HeaderBackupState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HeaderBackupState>(value),
    );
  }
}

String _$headerBackupHash() => r'f58ab8f3bba382a2ae5ff31344a71edcb4354fcc';

abstract class _$HeaderBackup extends $Notifier<HeaderBackupState> {
  HeaderBackupState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<HeaderBackupState, HeaderBackupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HeaderBackupState, HeaderBackupState>,
              HeaderBackupState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
