// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'logcat_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(logcatService)
final logcatServiceProvider = LogcatServiceProvider._();

final class LogcatServiceProvider
    extends $FunctionalProvider<LogcatService, LogcatService, LogcatService>
    with $Provider<LogcatService> {
  LogcatServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'logcatServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$logcatServiceHash();

  @$internal
  @override
  $ProviderElement<LogcatService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LogcatService create(Ref ref) {
    return logcatService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LogcatService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LogcatService>(value),
    );
  }
}

String _$logcatServiceHash() => r'829a49ef8026a9ccbbadb7a65acb40f3ec5f652e';
