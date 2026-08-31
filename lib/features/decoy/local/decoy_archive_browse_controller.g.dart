// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decoy_archive_browse_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DecoyArchiveBrowse)
final decoyArchiveBrowseProvider = DecoyArchiveBrowseFamily._();

final class DecoyArchiveBrowseProvider
    extends $NotifierProvider<DecoyArchiveBrowse, DecoyArchiveBrowseState> {
  DecoyArchiveBrowseProvider._({
    required DecoyArchiveBrowseFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'decoyArchiveBrowseProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$decoyArchiveBrowseHash();

  @override
  String toString() {
    return r'decoyArchiveBrowseProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  DecoyArchiveBrowse create() => DecoyArchiveBrowse();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DecoyArchiveBrowseState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DecoyArchiveBrowseState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DecoyArchiveBrowseProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$decoyArchiveBrowseHash() =>
    r'fc53fda6eb74ed627539d03784ccca701f23a660';

final class DecoyArchiveBrowseFamily extends $Family
    with
        $ClassFamilyOverride<
          DecoyArchiveBrowse,
          DecoyArchiveBrowseState,
          DecoyArchiveBrowseState,
          DecoyArchiveBrowseState,
          (String, String)
        > {
  DecoyArchiveBrowseFamily._()
    : super(
        retry: null,
        name: r'decoyArchiveBrowseProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DecoyArchiveBrowseProvider call(String filePath, String archiveName) =>
      DecoyArchiveBrowseProvider._(
        argument: (filePath, archiveName),
        from: this,
      );

  @override
  String toString() => r'decoyArchiveBrowseProvider';
}

abstract class _$DecoyArchiveBrowse extends $Notifier<DecoyArchiveBrowseState> {
  late final _$args = ref.$arg as (String, String);
  String get filePath => _$args.$1;
  String get archiveName => _$args.$2;

  DecoyArchiveBrowseState build(String filePath, String archiveName);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<DecoyArchiveBrowseState, DecoyArchiveBrowseState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DecoyArchiveBrowseState, DecoyArchiveBrowseState>,
              DecoyArchiveBrowseState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
