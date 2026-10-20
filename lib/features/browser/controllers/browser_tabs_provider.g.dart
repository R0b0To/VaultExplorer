// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'browser_tabs_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BrowserTabs)
final browserTabsProvider = BrowserTabsFamily._();

final class BrowserTabsProvider
    extends $NotifierProvider<BrowserTabs, BrowserTabsState> {
  BrowserTabsProvider._({
    required BrowserTabsFamily super.from,
    required BrowserTabsConfig super.argument,
  }) : super(
         retry: null,
         name: r'browserTabsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$browserTabsHash();

  @override
  String toString() {
    return r'browserTabsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BrowserTabs create() => BrowserTabs();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserTabsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserTabsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BrowserTabsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$browserTabsHash() => r'233c04390f4208fd075d608d0ce2352519ccd35d';

final class BrowserTabsFamily extends $Family
    with
        $ClassFamilyOverride<
          BrowserTabs,
          BrowserTabsState,
          BrowserTabsState,
          BrowserTabsState,
          BrowserTabsConfig
        > {
  BrowserTabsFamily._()
    : super(
        retry: null,
        name: r'browserTabsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  BrowserTabsProvider call(BrowserTabsConfig config) =>
      BrowserTabsProvider._(argument: config, from: this);

  @override
  String toString() => r'browserTabsProvider';
}

abstract class _$BrowserTabs extends $Notifier<BrowserTabsState> {
  late final _$args = ref.$arg as BrowserTabsConfig;
  BrowserTabsConfig get config => _$args;

  BrowserTabsState build(BrowserTabsConfig config);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BrowserTabsState, BrowserTabsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BrowserTabsState, BrowserTabsState>,
              BrowserTabsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
