// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'logcat_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LogcatController)
final logcatControllerProvider = LogcatControllerProvider._();

final class LogcatControllerProvider
    extends $NotifierProvider<LogcatController, LogcatState> {
  LogcatControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'logcatControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$logcatControllerHash();

  @$internal
  @override
  LogcatController create() => LogcatController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LogcatState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LogcatState>(value),
    );
  }
}

String _$logcatControllerHash() => r'0e0de2869dbf5eef9187c389d3d22326e3d1d552';

abstract class _$LogcatController extends $Notifier<LogcatState> {
  LogcatState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LogcatState, LogcatState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LogcatState, LogcatState>,
              LogcatState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
